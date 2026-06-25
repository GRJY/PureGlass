import SwiftUI
import AppKit
import PureGlassKit

/// Disk Haritası: bir dizinin içeriğini boyuta göre treemap olarak gösterir,
/// dizine tıklayınca içine iner (drill-down), breadcrumb ile geri çıkılır.
struct SpaceLensView: View {
    private let scanner = DiskMapScanner()
    private let home = FileManager.default.homeDirectoryForCurrentUser

    @State private var stack: [URL] = []
    @State private var entries: [DiskMapEntry] = []
    @State private var loading = false
    @State private var scanID = 0

    private var current: URL { stack.last ?? home }
    private var totalSize: Int64 { entries.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            Divider().opacity(0.3)
            content
        }
        .task { if stack.isEmpty { stack = [home]; await load() } }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(Array(stack.enumerated()), id: \.offset) { index, url in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                Button {
                    navigate(to: index)
                } label: {
                    Text(index == 0 ? "Ana Klasör" : url.lastPathComponent)
                        .font(.callout.weight(index == stack.count - 1 ? .semibold : .regular))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == stack.count - 1 ? Color.primary : Color.secondary)
            }
            Spacer()
            if !loading {
                Text("\(totalSize.formattedBytes) • \(entries.count) öğe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                NSWorkspace.shared.open(current)
            } label: {
                Label("Finder'da Aç", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Bu klasörü (\(current.path)) Finder'da aç")
        }
        .padding(DS.Spacing.m)
    }

    // MARK: - İçerik

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: DS.Spacing.m) {
                ProgressView().controlSize(.large)
                Text("Boyutlar hesaplanıyor…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            VStack(spacing: DS.Spacing.s) {
                Image(systemName: "chart.pie").font(.system(size: 48)).foregroundStyle(.tint)
                Text("Bu klasör boş veya okunamıyor").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TreemapView(entries: displayEntries) { entry in
                if entry.url == current {
                    return   // "Diğer" toplu kutusu — gezinme yok
                } else if entry.isDirectory {
                    stack.append(entry.url)
                    Task { await load() }
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                }
            }
            .padding(DS.Spacing.m)
        }
    }

    /// Çok küçük öğeleri tek bir "Diğer" kutusunda toplar (kalabalık + sayısal bozulmayı önler).
    private var displayEntries: [DiskMapEntry] {
        guard !entries.isEmpty else { return [] }
        let total = entries.reduce(0) { $0 + $1.size }
        guard total > 0 else { return entries }

        let threshold = Double(total) * 0.008                 // toplamın %0,8'i
        var kept = entries.filter { Double($0.size) >= threshold }
        if kept.count > 40 { kept = Array(kept.prefix(40)) }   // en fazla 40 kutu

        let keptSize = kept.reduce(0) { $0 + $1.size }
        let restSize = total - keptSize
        let restCount = entries.count - kept.count
        if restSize > 0, restCount > 0 {
            kept.append(DiskMapEntry(
                url: current,                                 // tıklanınca gezinmeyen toplu kutu
                name: "Diğer (\(restCount) öğe)",
                size: restSize, isDirectory: false, fileCount: restCount
            ))
        }
        return kept
    }

    // MARK: - Yükleme / gezinme

    private func navigate(to index: Int) {
        guard index < stack.count - 1 else { return }
        stack = Array(stack.prefix(index + 1))
        Task { await load() }
    }

    private func load() async {
        loading = true
        scanID += 1
        let id = scanID
        let dir = current
        let found = await scanner.children(of: dir)
        // Yarış koşulu: yalnızca en son istek sonucu uygula.
        if id == scanID {
            entries = found
            loading = false
        }
    }
}

/// Treemap çizimi: her dizin/dosya boyutuyla orantılı bir dikdörtgen.
struct TreemapView: View {
    let entries: [DiskMapEntry]
    let onTap: (DiskMapEntry) -> Void

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let frames = squarifiedTreemap(weights: entries.map { Double($0.size) }, in: rect)
            ZStack(alignment: .topLeading) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let f = frames[index]
                    if f.width > 3, f.height > 3 {
                        TreemapTile(entry: entry, color: color(for: entry), size: f.size)
                            .frame(width: f.width, height: f.height)
                            .offset(x: f.minX, y: f.minY)
                            .onTapGesture { onTap(entry) }
                            .help("\(entry.name) — \(entry.size.formattedBytes)")
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
    }

    /// Ada göre kararlı renk (her açılışta aynı).
    private func color(for entry: DiskMapEntry) -> Color {
        let sum = entry.name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hue = Double(sum % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.85)
    }
}

private struct TreemapTile: View {
    let entry: DiskMapEntry
    let color: Color
    let size: CGSize

    private var showLabel: Bool { size.width > 56 && size.height > 30 }
    private var showSize: Bool { size.width > 70 && size.height > 46 }

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(color.gradient)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.black.opacity(0.22), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if showLabel {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if showSize {
                            Text(entry.size.formattedBytes)
                                .font(.caption2)
                                .opacity(0.85)
                        }
                    }
                    .foregroundStyle(.black.opacity(0.82))
                    .padding(6)
                }
            }
            .padding(1)
            .clipped()   // etiket/içerik kutu sınırını taşmasın
    }
}
