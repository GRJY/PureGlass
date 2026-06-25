import SwiftUI

/// Kenar çubuğu hedefleri.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case smartScan
    case systemData
    case security
    case uninstaller
    case spaceLens
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: "Akıllı Tarama"
        case .systemData: "Sistem Verileri"
        case .security: "Güvenlik Taraması"
        case .uninstaller: "Uygulama Kaldırıcı"
        case .spaceLens: "Disk Haritası"
        case .settings: "Ayarlar"
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles"
        case .systemData: "macwindow.on.rectangle"
        case .security: "shield.lefthalf.filled"
        case .uninstaller: "trash.square"
        case .spaceLens: "chart.pie"
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
        case .security:
            SecurityView()
        case .settings:
            SettingsView(model: model)
        case .spaceLens:
            SpaceLensView()
        case .uninstaller:
            UninstallerView()
        }
    }
}
