import SwiftUI
import Foundation
import Observation

struct MaintenanceTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let command: String
    let needsAdmin: Bool
}

@MainActor
@Observable
final class MaintenanceViewModel {
    var running: String?
    var results: [String: Bool] = [:]   // id -> başarılı mı

    // Tüm yollar mutlak — `do shell script` ve sınırlı PATH altında çalışması için doğrulandı.
    let tasks: [MaintenanceTask] = [
        .init(id: "dns", title: L("DNS Önbelleğini Temizle", "Flush DNS Cache"), detail: L("İnternet sitelerine bağlanma sorunlarını çözebilir.", "Can fix problems connecting to websites."), symbol: "network", command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder", needsAdmin: true),
        .init(id: "spotlight", title: L("Spotlight'ı Yeniden İndeksle", "Reindex Spotlight"), detail: L("Arama sonuçları bozuksa indeksi sıfırlar.", "Resets the index if search results are broken."), symbol: "magnifyingglass", command: "/usr/bin/mdutil -E /", needsAdmin: true),
        .init(id: "launchservices", title: "Launch Services'i Yenile", detail: L("'Birlikte Aç' menüsündeki yinelenen/yanlış uygulamaları düzeltir.", "Fixes duplicate/wrong apps in the 'Open With' menu."), symbol: "app.badge.checkmark", command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r -domain local -domain system -domain user", needsAdmin: false),
        .init(id: "quicklook", title: L("Quick Look Önbelleğini Sıfırla", "Reset Quick Look Cache"), detail: L("Boşluk tuşuyla önizlemeler bozuksa düzeltir.", "Fixes broken spacebar previews."), symbol: "eye", command: "/usr/bin/qlmanage -r cache", needsAdmin: false),
        .init(id: "purge", title: L("Belleği Boşalt (RAM)", "Free Up Memory (RAM)"), detail: L("Kullanılmayan belleği serbest bırakır.", "Frees up unused memory."), symbol: "memorychip", command: "/usr/sbin/purge", needsAdmin: true),
        .init(id: "fonts", title: L("Font Önbelleğini Temizle", "Clear Font Cache"), detail: L("Font görüntüleme sorunlarını çözebilir.", "Can fix font rendering issues."), symbol: "textformat", command: "/usr/bin/atsutil databases -remove", needsAdmin: true),
        .init(id: "dockfinder", title: L("Dock & Finder'ı Yenile", "Restart Dock & Finder"), detail: L("Donan Dock/Finder'ı yeniden başlatır.", "Restarts a frozen Dock/Finder."), symbol: "macwindow", command: "/usr/bin/killall Dock Finder", needsAdmin: false),
    ]

    func run(_ task: MaintenanceTask) async {
        running = task.id
        results[task.id] = nil
        var ok = false
        do {
            if task.needsAdmin {
                try AdminShell.run(task.command)        // ana iş parçacığı, parola istemi
            } else {
                try await Task.detached { try MaintenanceViewModel.shell(task.command) }.value
            }
            ok = true
        } catch {
            ok = false
        }
        results[task.id] = ok
        running = nil
    }

    nonisolated static func shell(_ command: String) throws {
        let p = Process()
        p.executableURL = URL(filePath: "/bin/sh")
        p.arguments = ["-c", command]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "PureGlass", code: Int(p.terminationStatus))
        }
    }
}

struct MaintenanceView: View {
    @State private var model = MaintenanceViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Bakım", "Maintenance")).font(.dsDisplay(32))
                    Text(L("Mac'in tipik sorunlarını çözen sistem bakım işlemleri. Bazıları yönetici parolası ister.", "System maintenance tasks that fix common Mac problems. Some require an admin password."))
                        .font(.iCallout).foregroundStyle(.secondary)
                }
                .padding(.bottom, DS.Spacing.s)

                ForEach(model.tasks) { task in
                    taskCard(task)
                }
            }
            .padding(DS.Spacing.xxl)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .task {
            // QA: PUREGLASS_RUNMAINT=<id> ile bir görevi otomatik çalıştırıp sonucu yaz.
            if let id = ProcessInfo.processInfo.environment["PUREGLASS_RUNMAINT"],
               let task = model.tasks.first(where: { $0.id == id }) {
                await model.run(task)
                let res = model.results[id] == true ? "OK" : "FAIL"
                try? res.write(toFile: "/tmp/pg_maint.txt", atomically: true, encoding: .utf8)
            }
        }
    }

    private func taskCard(_ task: MaintenanceTask) -> some View {
        GlassCard {
            HStack(spacing: DS.Spacing.m) {
                Image(systemName: task.symbol).font(.title2).foregroundStyle(.tint).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: DS.Spacing.s) {
                        Text(task.title).font(.iHeadline)
                        if task.needsAdmin {
                            Text(L("parola", "password")).font(.iCaption2).foregroundStyle(.tertiary)
                        }
                        if let ok = model.results[task.id] {
                            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(ok ? DS.Palette.safe : DS.Palette.danger).font(.iCaption)
                        }
                    }
                    Text(task.detail).font(.iCallout).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.run(task) }
                } label: {
                    if model.running == task.id { ProgressView().controlSize(.small) }
                    else { Text(L("Çalıştır", "Run")) }
                }
                .buttonStyle(.glass).controlSize(.large)
                .disabled(model.running != nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
