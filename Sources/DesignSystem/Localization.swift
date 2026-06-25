import SwiftUI
import Observation

/// Çalışma-zamanı TR/EN dil yöneticisi. Tek kaynak; değişince tüm görünümler yenilenir.
/// Çeviri, çağrı yerinde iki dilli verilir: `L("Türkçe", "English")`.
@MainActor
@Observable
final class Loc {
    static let shared = Loc()

    enum Lang: String { case tr, en }

    var lang: Lang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: Self.key) }
    }

    private static let key = "PureGlassLanguage"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key), let l = Lang(rawValue: raw) {
            lang = l
        } else {
            // İlk açılış: sistem dili Türkçe ise TR, değilse EN.
            lang = (Locale.current.language.languageCode?.identifier == "tr") ? .tr : .en
        }
    }

    func pick(_ tr: String, _ en: String) -> String { lang == .tr ? tr : en }
}

/// Kısa global yardımcı. Görünüm gövdesinde çağrıldığında dil değişimini izler.
@MainActor
func L(_ tr: String, _ en: String) -> String { Loc.shared.pick(tr, en) }

/// Sağ üst köşedeki TR/EN geçiş kontrolü (kutusuz, aktif olan mavi).
struct LanguageToggle: View {
    @Bindable private var loc = Loc.shared

    var body: some View {
        HStack(spacing: 2) {
            segment(.tr, "TR")
            Text("/").foregroundStyle(.tertiary).font(.iCaption2)
            segment(.en, "EN")
        }
    }

    private func segment(_ l: Loc.Lang, _ title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { loc.lang = l }
        } label: {
            Text(title)
                .font(.iCaption.weight(loc.lang == l ? .bold : .regular))
                .foregroundStyle(loc.lang == l ? DS.Palette.accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(l == .tr ? "Türkçe" : "English")
    }
}
