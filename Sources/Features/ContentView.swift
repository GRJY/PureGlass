import SwiftUI

/// Kenar çubuğu hedefleri.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case smartScan
    case uninstaller
    case spaceLens
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: "Akıllı Tarama"
        case .uninstaller: "Uygulama Kaldırıcı"
        case .spaceLens: "Disk Haritası"
        case .settings: "Ayarlar"
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles"
        case .uninstaller: "trash.square"
        case .spaceLens: "chart.pie"
        case .settings: "gearshape"
        }
    }

    var available: Bool {
        switch self {
        case .smartScan, .settings, .spaceLens: true
        case .uninstaller: false   // yakında
        }
    }
}

/// Ana pencere: glass kenar çubuğu + detay.
struct ContentView: View {
    @State private var model = AppViewModel()
    @State private var selection: SidebarItem?

    init() {
        // Opt-in QA kancası: PUREGLASS_START=spaceLens ile doğrudan Disk Haritası'nda açılır.
        let start = ProcessInfo.processInfo.environment["PUREGLASS_START"]
        _selection = State(initialValue: start == "spaceLens" ? .spaceLens : .smartScan)
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                NavigationLink(value: item) {
                    Label {
                        HStack {
                            Text(item.title)
                            if !item.available {
                                Text("Yakında")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } icon: {
                        Image(systemName: item.symbol)
                    }
                }
                .disabled(!item.available)
            }
            .navigationTitle("PureGlass")
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } detail: {
            detail
                .background(VisualEffectView(material: .underWindowBackground).ignoresSafeArea())
        }
        .task {
            // Opt-in QA kancası: PUREGLASS_AUTOSCAN=1 ile açılınca otomatik tara (salt-okunur).
            if ProcessInfo.processInfo.environment["PUREGLASS_AUTOSCAN"] == "1", model.phase == .idle {
                await model.scan()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .smartScan {
        case .smartScan:
            SmartScanView(model: model)
        case .settings:
            SettingsView(model: model)
        case .spaceLens:
            SpaceLensView()
        case .uninstaller:
            ComingSoonView(title: "Uygulama Kaldırıcı",
                           symbol: "trash.square",
                           detail: "Uygulamaları tüm artıklarıyla (container, prefs, cache, login item) birlikte kaldırma. Çok-seviyeli eşleştirme motoru ile yakında.")
        }
    }
}

/// Henüz gelmemiş özellikler için dürüst yer tutucu.
struct ComingSoonView: View {
    let title: String
    let symbol: String
    let detail: String

    var body: some View {
        VStack(spacing: DS.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text(title).font(.dsDisplay(32))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("Yakında")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, DS.Spacing.m)
                .padding(.vertical, DS.Spacing.xs)
                .glassEffect(.regular.tint(DS.Palette.caution.opacity(0.3)), in: .capsule)
        }
        .padding(DS.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
