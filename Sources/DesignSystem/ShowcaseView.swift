import SwiftUI
import PureGlassKit

/// FAZ 1 doğrulama ekranı: tüm tasarım sistemi bileşenlerini canlı gösterir.
/// İlerleme halkası dolarken log paneline örnek dosya yolları akar (akıcılık testi).
/// FAZ 6'da gerçek navigasyon/akışla değiştirilecek.
struct ShowcaseView: View {
    @State private var progress: Double = 0
    @State private var lines: [LogLine] = []
    @State private var reclaimed: Double = 0  // GB
    @State private var permissions = PermissionCoordinator()

    private let samplePaths: [(String, LogLine.Status)] = [
        ("~/Library/Caches/com.apple.Safari/WebKitCache", .deleted),
        ("~/Library/Logs/DiagnosticReports/old-report.crash", .deleted),
        ("~/Library/Developer/Xcode/DerivedData/App-abc123", .deleting),
        ("~/.npm/_cacache/index-v5", .deleted),
        ("~/Library/Caches/Homebrew/downloads", .deleted),
        ("/Library/Caches/com.example.helper", .skipped),
        ("~/Library/Containers/com.app/Data/Library/Caches", .deleted),
        ("/System/Library/Caches/protected", .failed),
        ("~/Library/Application Support/Slack/Cache", .deleted),
        ("~/Library/Mail/V10/Attachments/huge.zip", .deleting),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.xl) {
                header
                FullDiskAccessCard(coordinator: permissions)
                statsRow
                progressAndLog
                riskBadges
                buttons
                Text("PureGlass Tasarım Sistemi • FAZ 1")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, DS.Spacing.l)
            }
            .padding(DS.Spacing.xxl)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .task { await runDemo() }
    }

    // MARK: - Bölümler

    private var header: some View {
        GlassCard(cornerRadius: DS.Radius.xl, padding: DS.Spacing.xl) {
            VStack(spacing: DS.Spacing.s) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("PureGlass")
                    .font(.dsDisplay(40))
                Text("Native, şeffaf, gizliliğe saygılı Mac temizleyici")
                    .font(.dsSection)
                    .foregroundStyle(.secondary)
                Text("PureGlassKit \(PureGlassKitInfo.version) • lokalde çalışır, telemetri yok")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    private var statsRow: some View {
        HStack(spacing: DS.Spacing.m) {
            StatTile(title: "Kazanılacak alan",
                     value: String(format: "%.1f GB", reclaimed),
                     systemImage: "internaldrive",
                     tint: DS.Palette.safe)
            StatTile(title: "Taranan öğe",
                     value: "\(lines.count) / \(samplePaths.count)",
                     systemImage: "doc.on.doc")
            StatTile(title: "Boş alan",
                     value: "37 GB",
                     systemImage: "externaldrive.badge.checkmark",
                     tint: DS.Palette.accent)
        }
    }

    private var progressAndLog: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                HStack(spacing: DS.Spacing.xl) {
                    ProgressRing(progress: progress)
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        Text("Canlı temizlik")
                            .font(.dsTitle)
                        Text("Silinen her dosya yolu anlık olarak aşağıda görünür.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                LiveLogPanel(lines: lines)
            }
        }
    }

    private var riskBadges: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                Text("Risk seviyeleri")
                    .font(.dsTitle)
                HStack(spacing: DS.Spacing.m) {
                    ForEach(RiskLevel.allCases, id: \.self) { RiskBadge(level: $0) }
                    Spacer()
                }
            }
        }
    }

    private var buttons: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: DS.Spacing.m) {
                Button {
                    Task { await runDemo() }
                } label: {
                    Label("Yeniden Tara", systemImage: "arrow.clockwise")
                        .padding(.horizontal, DS.Spacing.s)
                        .padding(.vertical, DS.Spacing.xs)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .controlSize(.large)

                Button {
                } label: {
                    Label("Ayarlar", systemImage: "gearshape")
                        .padding(.horizontal, DS.Spacing.s)
                        .padding(.vertical, DS.Spacing.xs)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Demo sürücüsü

    private func runDemo() async {
        lines = []
        progress = 0
        reclaimed = 0
        for (index, item) in samplePaths.enumerated() {
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(DS.Anim.snappy) {
                lines.append(LogLine(path: item.0, status: item.1))
                progress = Double(index + 1) / Double(samplePaths.count)
                if item.1 == .deleted { reclaimed += Double.random(in: 0.4...2.1) }
            }
        }
    }
}

#Preview {
    ShowcaseView()
        .frame(width: 920, height: 720)
        .background(.black.opacity(0.3))
}
