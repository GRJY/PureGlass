import SwiftUI

/// Canlı silme/tarama log satırı (UI modeli).
/// FAZ 5'te `CleaningEngine` olayları bu modele eşlenecek.
struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let path: String
    var status: Status

    enum Status: Equatable {
        case scanning
        case deleting
        case deleted
        case skipped
        case failed

        var icon: String {
            switch self {
            case .scanning: "magnifyingglass"
            case .deleting: "arrow.triangle.2.circlepath"
            case .deleted: "checkmark.circle.fill"
            case .skipped: "minus.circle.fill"
            case .failed: "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .scanning: .secondary
            case .deleting: DS.Palette.accent
            case .deleted: DS.Palette.safe
            case .skipped: DS.Palette.caution
            case .failed: DS.Palette.danger
            }
        }
    }
}

/// Silinen/taranan dosya yollarını canlı gösteren, otomatik aşağı kayan panel.
///
/// İÇERİK katmanı olduğu için Liquid Glass DEĞİL — kasıtlı olarak koyu, yarı saydam
/// "terminal" zemini kullanır (glass-on-glass yığmaktan kaçınmak için tasarım kuralı).
struct LiveLogPanel: View {
    let lines: [LogLine]
    var height: CGFloat = 220

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(lines) { line in
                        row(line).id(line.id)
                    }
                }
                .padding(DS.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lines.last?.id) {
                guard let last = lines.last?.id else { return }
                withAnimation(DS.Anim.snappy) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .frame(height: height)
        .background(.black.opacity(0.28), in: .rect(cornerRadius: DS.Radius.m))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.m)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func row(_ line: LogLine) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: line.status.icon)
                .foregroundStyle(line.status.color)
                .font(.caption)
                .frame(width: 16)
            Text(line.path)
                .font(.dsMono)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
