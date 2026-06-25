import SwiftUI

/// Kenar çubuğu hedefleri.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case smartScan
    case systemData
    case monitor
    case security
    case privacy
    case uninstaller
    case duplicates
    case spaceLens
    case maintenance
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: "Akıllı Tarama"
        case .systemData: "Sistem Verileri"
        case .monitor: "Sistem Monitörü"
        case .security: "Güvenlik Taraması"
        case .privacy: "Tarayıcı Gizliliği"
        case .uninstaller: "Uygulama Kaldırıcı"
        case .duplicates: "Yinelenen Dosyalar"
        case .spaceLens: "Disk Haritası"
        case .maintenance: "Bakım"
        case .settings: "Ayarlar"
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles"
        case .systemData: "macwindow.on.rectangle"
        case .monitor: "gauge.with.dots.needle.67percent"
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
        switch model.selectedSection ?? .smartScan {
        case .smartScan:
            SmartScanView(model: model)
        case .systemData:
            SystemDataView()
        case .monitor:
            SystemMonitorView()
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
