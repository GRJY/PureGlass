import SwiftUI
import PureGlassKit

/// FAZ 0 karşılama ekranı: şeffaf cam pencerenin ve Liquid Glass kontrollerinin
/// çalıştığını doğrular. Sonraki fazlarda gerçek tarama/temizlik akışıyla değişecek.
struct RootView: View {
    var body: some View {
        ZStack {
            // Pencere şeffaflığı (masaüstünü örnekleyen cam zemin).
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                header
                actionButtons
            }
            .padding(40)

            // NSWindow'u şeffaf yapan görünmez yardımcı.
            WindowConfigurator()
                .frame(width: 0, height: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 54, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            Text("PureGlass")
                .font(.system(size: 42, weight: .bold, design: .rounded))

            Text("Native, şeffaf, gizliliğe saygılı Mac temizleyici")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("PureGlassKit \(PureGlassKitInfo.version) • lokalde çalışır, telemetri yok")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(36)
        .frame(maxWidth: 520)
        // Liquid Glass — yalnızca fonksiyonel katman (içerik değil).
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private var actionButtons: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 16) {
                Button {
                    // FAZ 6'da gerçek tarama akışına bağlanacak.
                } label: {
                    Label("Taramaya Başla", systemImage: "magnifyingglass")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .controlSize(.large)

                Button {
                    // FAZ 6 ayarlar ekranı.
                } label: {
                    Label("Ayarlar", systemImage: "gearshape")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
    }
}

#Preview {
    RootView()
        .frame(width: 920, height: 640)
}
