import SwiftUI

/// Kenar çubuğu hedefleri.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case smartScan
    case systemData
    case monitor
    case network
    case security
    case privacy
    case uninstaller
    case duplicates
    case spaceLens
    case maintenance
    case settings

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .smartScan: L("Akıllı Tarama", "Smart Scan")
        case .systemData: L("Sistem Verileri", "System Data")
        case .monitor: L("Sistem Monitörü", "System Monitor")
        case .network: L("Ağ", "Network")
        case .security: L("Güvenlik Taraması", "Security Scan")
        case .privacy: L("Tarayıcı Gizliliği", "Browser Privacy")
        case .uninstaller: L("Uygulama Kaldırıcı", "App Uninstaller")
        case .duplicates: L("Yinelenen Dosyalar", "Duplicate Files")
        case .spaceLens: L("Disk Haritası", "Disk Map")
        case .maintenance: L("Bakım", "Maintenance")
        case .settings: L("Ayarlar", "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles"
        case .systemData: "macwindow.on.rectangle"
        case .monitor: "gauge.with.dots.needle.67percent"
        case .network: "wifi"
        case .security: "shield.lefthalf.filled"
        case .privacy: "hand.raised"
        case .uninstaller: "trash.square"
        case .duplicates: "doc.on.doc"
        case .spaceLens: "chart.pie"
        case .maintenance: "wrench.and.screwdriver"
        case .settings: "gearshape"
        }
    }

}

/// Ana pencere: glass kenar çubuğu + detay.
struct ContentView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedSection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
            }
            .navigationTitle("PureGlass")
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                    Text("PureGlass").font(.dsTitle)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        } detail: {
            detail
                .background(VisualEffectView(material: .fullScreenUI).ignoresSafeArea())
                .overlay(alignment: .topTrailing) {
                    LanguageToggle()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.trailing, 10)
                        .padding(.top, 8)
                }
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
        switch model.selectedSection ?? .smartScan {
        case .smartScan:
            SmartScanView(model: model)
        case .systemData:
            SystemDataView()
        case .monitor:
            SystemMonitorView()
        case .network:
            NetworkView()
        case .security:
            SecurityView()
        case .privacy:
            PrivacyView()
        case .duplicates:
            DuplicateView()
        case .maintenance:
            MaintenanceView()
        case .settings:
            SettingsView(model: model)
        case .spaceLens:
            SpaceLensView()
        case .uninstaller:
            UninstallerView()
        }
    }
}
