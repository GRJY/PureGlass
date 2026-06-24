# PureGlass

Native, **şeffaf (Liquid Glass)**, gizliliğe saygılı bir macOS disk temizleyici.
CleanMyMac mantığını taban alır ama **tamamen senin kontrolünde, lokalde** çalışır:
hiçbir veri internete gitmez, telemetri yoktur ve **her silinen dosyanın tam yolunu** görürsün.

> **Neden?** Dışarıdaki ücretli temizleyicilerin maliyetinden ve veri gizliliği riskinden
> kaçınmak; 256 GB diski maksimum verimle kullanmak.

---

## Özellikler

- **Akıllı Tarama** — önbellek, günlük, geçici dosya ve geliştirici artıklarını (Xcode DerivedData, npm, vb.) tarar.
- **Her dosya yolu görünür** — silmeden önce tam yol + boyut + risk rozeti (yeşil/sarı/kırmızı) ile listelenir.
- **Canlı silme logu** — her dosya Çöp'e taşınırken yolu anlık akar.
- **Trash-first** — hiçbir şey kalıcı silinmez; her şey geri alınabilir Çöp Kutusu'na gider.
- **Şeffaf Liquid Glass arayüz** — macOS 26 (Tahoe) cam efektleri.
- **Tam offline** — telemetri/ağ erişimi yok.

## Gereksinimler

- macOS **26.0+** (Tahoe) — Liquid Glass için
- Apple Silicon
- Xcode **26+**, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Derleme & Çalıştırma

```bash
# Geliştirme
xcodegen generate
open PureGlass.xcodeproj        # Xcode'da ⌘R

# veya komut satırından
xcodebuild -project PureGlass.xcodeproj -scheme PureGlass -configuration Debug build

# Testler (çekirdek mantık — güvenlik, tarama, temizlik)
xcodebuild -project PureGlass.xcodeproj -scheme PureGlass -destination 'platform=macOS' test
```

## Dağıtım (.dmg)

```bash
./scripts/build-release.sh      # build/PureGlass.dmg üretir
```

İmzasız (ad-hoc) sürümde ilk açılışta Gatekeeper uyarısı çıkar:
**Finder → sağ tık → Aç → Aç**.

## Tam Disk Erişimi (FDA)

Derin temizlik için bazı korumalı klasörlerin okunması gerekir. FDA bir entitlement
değildir; **elle** verilir: uygulama içindeki "Ayarları Aç" düğmesi seni
**Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi**'ne götürür. İzni verince
uygulama otomatik algılar. (Bu yüzden uygulama **sandbox'sızdır** ve App Store'da olamaz.)

## Mimari

```
Sources/
  App/            Giriş noktası, şeffaf pencere (NSVisualEffectView), kök görünüm
  DesignSystem/   Liquid Glass bileşenleri (GlassCard, RiskBadge, LiveLogPanel…)
  Features/       AppViewModel + ekranlar (Akıllı Tarama, Ayarlar)
  Core/           = PureGlassKit framework (UI'dan bağımsız, test edilebilir):
    LocationsDatabase  taranacak yolların tek kaynağı (kategori + risk)
    SafetyGuard        silme öncesi son güvenlik kapısı (blocklist + symlink/TOCTOU)
    ScanEngine         eşzamanlı, iptal edilebilir tarama
    CleaningEngine     trash-first silme + canlı olaylar
    PermissionCoordinator  Full Disk Access durumu + otomatik yakalama
Tests/            PureGlassKit birim testleri (güvenlik/tarama/temizlik/izin)
```

## Güvenlik İlkeleri

- **Asla** dokunulmaz: `/System`, `/usr`, `/bin`, Apple uygulamaları, SIP korumalı her şey.
- Silme yalnızca izinli kök dizinlerin **gerçek** (symlink çözülmüş) alt öğelerinde.
- Her silme öncesi `SafetyGuard.validate` (TOCTOU koruması).
- Hepsi Çöp'e taşınır — geri alınabilir.

## Dürüst Sınır: "Sistem dosyalarına kadar derin temizlik"

macOS'ta **SIP korumalı gerçek sistem dosyaları (`/System` vb.) hiçbir araçla silinemez**
(CleanMyMac dahil; root bile silemez, FDA bunu geçemez). PureGlass'in "derin temizliği":
erişilebilir kullanıcı/sistem önbellek-günlük alanları + (ileride) root-yetkili XPC helper
ile root-sahipli cache'ler. UI bunu dürüstçe belirtir.

## İleride (opsiyonel)

- **Notarization** (geniş dağıtım için): ücretli Apple Developer hesabı gerektirir.
  Gerektiğinde: `ENABLE_HARDENED_RUNTIME=YES` + Developer ID ile imza + `notarytool submit`.
- Uninstaller (çok-seviyeli app eşleştirme), Disk Haritası (treemap), root temizlik (FAZ 9).

## Lisans / Gizlilik

Kişisel araç. Hiçbir veri toplanmaz veya gönderilmez.
