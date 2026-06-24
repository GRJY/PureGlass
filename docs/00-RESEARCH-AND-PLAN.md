# PureGlass — Araştırma ve Uygulama Planı

> **Amaç:** CleanMyMac benzeri, çalışma mantığını birebir anlayıp **kendimiz yazdığımız**, native, şeffaf (Liquid Glass) bir macOS masaüstü temizlik uygulaması. Sistem dosyalarına kadar derin temizlik yapabilen, ama **hangi dosya yolunu sildiğini detaylı gösteren** güvenli bir araç.
>
> **Neden kendimiz yazıyoruz:** (1) Dışarıdaki ücretli yazılımların maliyeti, (2) veri gizliliği/güvenlik zaafiyeti riski — her şey lokalde, telemetri yok, (3) 256 GB diski maksimum performansla kullanmak.

---

## 0. Ortam (Doğrulandı)

| Bileşen | Sürüm | Not |
|---|---|---|
| macOS | **26.5.1 (Tahoe)** build 25F80 | Liquid Glass tam destekli |
| Xcode | **26.4.1** | SwiftUI Liquid Glass API'leri mevcut |
| Swift | **6.3.1** | Strict concurrency (Swift 6) |
| Mimari | Apple Silicon (arm64) | |
| Disk | 228 GiB APFS, ~37 GiB boş | Hedef: maksimize et |

---

## 1. CleanMyMac Nasıl Çalışır? (Araştırma Bulguları)

CleanMyMac sadece "cache siler" bir araç değil; bir **tarama motoru + modüler temizlik + güvenlik katmanı** kombinasyonu. Çalışma akışı her zaman: **Tara → Kullanıcıya göster → Onayla → Sil (Çöp'e)**.

### 1.1 Ana Modüller
- **Smart Scan** — tek tıkla tüm modülleri çalıştıran "hızlı bakım".
- **System Junk** — en büyük kazanç. ~13–16 alt kategori: kullanıcı/sistem cache, kullanıcı/sistem log, dil dosyaları (unused localizations), Xcode junk (DerivedData/Archives), eski güncellemeler, bozuk login item'lar, bozuk preference'lar, universal binaries, kullanılmayan disk image'lar, döküman versiyonları.
- **Mail Attachments** — indirilen mail eklerinin yerel kopyaları.
- **Trash Bins** — tüm disklerdeki çöp kutuları.
- **Large & Old Files** — >100MB veya 1+ yıl eski dosyalar.
- **Uninstaller** — uygulamayı + tüm artıklarını (container, prefs, caches, login item) bulup kaldırma.
- **Privacy** — tarayıcı geçmişi/çerez (Safari/Chrome/Firefox).
- **Malware Removal** — imza tabanlı tarama (CleanMyMac'te "Moonlock Engine").
- **Optimization / Maintenance** — login item yönetimi, RAM, Spotlight reindex vb.
- **Space Lens** — disk kullanımının treemap görselleştirmesi.

### 1.2 Tarama Motorunun Kalbi (Uninstaller için "App Matching")
CleanMyMac ve açık kaynak klonları (PureMac/MacSai) bir uygulamanın artıklarını bulmak için **çok seviyeli (10 level) sezgisel eşleştirme** kullanır: bundle ID, team identifier, entitlements, Spotlight metadata (`mdfind`), container keşfi, şirket-adı sezgisi, kısmi yol eşleşmesi. 120+ dosya sistemi yolunu tarar.

### 1.3 Güvenlik Modeli (kritik — bizim de uygulayacağımız)
- **Trash-first:** Hiçbir şey kalıcı silinmez; `FileManager.trashItem` ile Çöp'e taşınır. (Geri alınabilir.)
- **Allow-list / safe-root:** Silinecek yollar yalnızca bilinen güvenli kök dizinlere karşı doğrulanır.
- **Blocklist:** `/System`, `/usr`, `/bin`, `/Library` çekirdeği, Apple uygulamaları asla dokunulmaz.
- **TOCTOU koruması:** Sembolik linkler silmeden önce/sonra yeniden çözülür (symlink ile koruma dizinine kaçış engellenir).
- **Akıllı seçim:** En son/ilk döküman versiyonu, en güncel yedek otomatik seçilmez.
- **Açık onay:** Yıkıcı işlem öncesi her zaman kullanıcı onayı.

---

## 2. macOS Gerçekleri: Neyi Silebiliriz, Neyi Silemeyiz?

> Bu bölüm "revize gerekmesin" hedefi için en kritik kısım. Yanlış varsayım = çalışmayan/zarar veren uygulama.

### 2.1 İzin Modeli
- **Full Disk Access (FDA)** bir *entitlement değildir.* Kullanıcı **manuel olarak** Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi'nden vermek zorunda. App Store dışı dağıtım gerektirir.
- Uygulama **sandbox'sız (non-sandboxed)** olmalı. Sandbox'lı bir uygulamaya FDA verip container dışına okuma denerse `sandboxd` onu anında öldürür. → **App Store yok, Developer ID + notarization ile doğrudan dağıtım.**
- **SIP (System Integrity Protection):** `/System`, korumalı sistem dosyaları root için bile yazılamaz. **FDA, SIP'i geçemez.** → Gerçekten "sistem dosyası" dediğimiz korumalı çekirdek **silinemez ve silinmemeli.** "Derin sistem temizliği" = SIP korumalı *olmayan* sistem cache/log alanları (`/Library/Caches`, `/private/var/log`, `/private/var/folders` vb. erişilebilir kısımlar) + root-owned öğeler için ayrıcalıklı yardımcı (helper).
- **Root-owned öğeler** (örn. `/Library/Caches` altındaki bazı şeyler) için **XPC privileged helper** (SMAppService / `SMJobBless` yerine modern `SMAppService`) gerekir. MVP'de bunu *opsiyonel* tutacağız; önce kullanıcı-alanı (`~/`) temizliği.

### 2.2 Güvenli Silinebilir Alanlar (Yeşil — kullanıcı alanı, FDA ile)
- `~/Library/Caches/*` (içerik — klasörün kendisi değil) — uygulama yeniden üretir.
- `~/Library/Logs/*`
- `~/Library/Application Support/<app>/Cache` türevleri
- `~/Library/Developer/Xcode/DerivedData`, `.../Archives` (dikkatli), `.../iOS DeviceSupport`, CoreSimulator caches
- `~/Library/Containers/<app>/Data/Library/Caches`
- Geliştirici cache: `~/.npm`, `~/.cache`, `~/Library/Caches/Homebrew`, `~/Library/pnpm`, yarn, Docker
- Çöp kutuları: `~/.Trash` ve diğer disklerdeki `.Trashes`
- Mail ekleri: `~/Library/Mail/.../Attachments`
- Tarayıcı cache (privacy modülü)

### 2.3 Dikkatli (Sarı — onay/akıllı seçim)
- Büyük & eski dosyalar (kullanıcı dosyaları — asla otomatik seçme)
- iOS yedekleri (`~/Library/Application Support/MobileSync/Backup`) — en güncel asla seçme
- Döküman versiyonları
- İndirilenler (yalnızca bozuk/yarım)

### 2.4 Yasak (Kırmızı — asla)
- `/System/*`, `/usr/*` (`/usr/local` hariç), `/bin`, `/sbin`
- `/Library` çekirdek framework'leri, `/private/var/db` çekirdeği
- SIP korumalı her şey (`com.apple.rootless` xattr)
- Apple imzalı uygulamalar
- Aktif kullanılan / kilitli dosyalar

---

## 3. Hedef Mimari (PureMac & MacSai referans alınarak)

Her ikisi de Swift 6 + SwiftUI. Kanıtlanmış katmanlı yapı:

```
PureGlass/                         # Ana uygulama (non-sandboxed)
├── App/                            # Giriş noktası, WindowGroup, glass window
├── Core/  (PureGlassKit hedefi)   # UI'dan bağımsız çekirdek mantık
│   ├── Scanning/
│   │   ├── LocationsDatabase.swift # Taranacak yolların tek kaynağı (kategori+risk seviyesi)
│   │   ├── ScanEngine.swift        # Eşzamanlı (TaskGroup) tarama, boyut hesaplama
│   │   └── AppPathFinder.swift     # Uninstaller için çok-seviyeli eşleştirme
│   ├── Cleaning/
│   │   ├── CleaningEngine.swift    # trashItem, allow-list doğrulama, TOCTOU
│   │   └── SafetyGuard.swift       # blocklist + safe-root + symlink çözümü
│   ├── Permissions/
│   │   └── PermissionCoordinator.swift  # FDA tespiti, prompt, post-grant retry
│   └── Models/                     # ScanCategory, FileItem, CleanResult, RiskLevel
├── Features/                       # SwiftUI ekranlar (ViewModel + View)
│   ├── SmartScan/
│   ├── SystemJunk/
│   ├── LargeOldFiles/
│   ├── Uninstaller/
│   ├── Privacy/
│   ├── SpaceLens/   (treemap)
│   └── Settings/
├── DesignSystem/                   # Liquid Glass bileşenleri, renk, tipografi, animasyon
└── (opsiyonel ileride) PureGlassHelper/  # XPC privileged helper (root öğeler)
```

**Önemli ilkeler:**
- `LocationsDatabase` = tek doğruluk kaynağı. Her yol: `path`, `category`, `riskLevel (green/yellow/red)`, `description`, `requiresFDA`, `requiresRoot`.
- Çekirdek (`Core`) UI'dan tamamen bağımsız → test edilebilir.
- Tüm I/O `async/await` + `TaskGroup` ile eşzamanlı (256 GB'ı hızlı taramak için).
- `@Observable` (yeni Observation framework) ile state.

---

## 4. Liquid Glass UI Yaklaşımı

> Tasarım hedefi: **canlı, akıcı, net, taze, şeffaf.** Liquid Glass yalnızca **fonksiyonel katmanda** (kontroller, sidebar, toolbar, floating action) — içerik katmanında (dosya listeleri) DEĞİL.

### 4.1 Şeffaf Pencere
- `WindowGroup { ... }.windowStyle(.hiddenTitleBar)` — başlık çubuğu ve toolbar arka planını kaldırır.
- Arka plan: `.containerBackground(.thinMaterial, for: .window)` (modern yol) veya `NSVisualEffectView` (`.active`, `.hudWindow`/`.sidebar` material) `NSViewRepresentable` ile.
- ⚠️ **macOS 26 (Tahoe) uyarısı:** `NSGlassEffectView`'in doğrudan SwiftUI içeriğine sarılması bazı durumlarda boş/yanlış tonlanmış içerik üretiyor. → **Pencere şeffaflığı için `NSVisualEffectView` fallback yolunu kullan; `glassEffect`'i pencere kabuğuna değil, içindeki kontrollere uygula.**

### 4.2 Glass Bileşenleri (doğrulanmış API)
```swift
// Temel
.glassEffect()                                  // .regular + capsule (varsayılan)
.glassEffect(.regular.tint(.accentColor))       // sadece CTA için tint
.glassEffect(.clear, in: .rect(cornerRadius: 16))

// Birden fazla glass öğeyi grupla (glass-on-glass'ı önler, morph sağlar)
GlassEffectContainer(spacing: 24) {
    ForEach(actions) { $0.glassEffect() }
}

// Morphing (genişle/daralla)
@Namespace var ns
... .glassEffect().glassEffectID("id", in: ns)

// Buton stilleri
.buttonStyle(.glass)            // ikincil, şeffaf
.buttonStyle(.glassProminent)   // birincil (CTA), .tint ile
```

### 4.3 Kurallar (do/don't)
- ✅ Glass yalnızca navigasyon/kontrol katmanı; `GlassEffectContainer` ile grupla; tint'i yalnızca ana eylem için.
- ❌ Glass'ı liste/tablo/içeriğe uygulama; glass üstüne glass yığma; renkli/yoğun arka plan üstünde dimming'siz kullanma.
- Erişilebilirlik (Reduce Transparency / Increase Contrast) sistemce otomatik — override etme.

### 4.4 "Hangi dosyayı siliyorum" görünürlüğü (kullanıcının ana isteği)
- Her tarama sonucu **tam yol** (`/Users/.../Caches/...`), **boyut**, **kategori**, **risk rozeti (yeşil/sarı/kırmızı)** ile listelenir.
- Silme sırasında **canlı log akışı**: her dosya yolu silinirken anlık görünür (terminal hissi veren, monospace, akıcı kayan bir panel).
- Silme sonrası özet: kazanılan alan + Çöp'e taşınan öğe sayısı + "Geri Al" hatırlatması.

---

## 5. Adım Adım Uygulama Planı (Fazlar)

> Her faz sonunda derlenebilir/çalışır bir durum. Acele yok; her adım kendi içinde doğrulanır.

### FAZ 0 — Proje İskeleti & Dağıtım Temeli
1. Xcode projesi oluştur (macOS App, SwiftUI, **non-sandboxed**). Min hedef macOS 26.
2. `Core` (PureGlassKit) ayrı target olarak; unit test target'ı ekle.
3. `Info.plist`: `NSSystemAdministrationUsageDescription` vb. açıklamalar.
4. Git init + `.gitignore`. İlk "Hello, glass window" — şeffaf pencere çalışıyor.
- **Çıktı:** Boş ama şeffaf, başlıksız, glass pencere açılıyor.

### FAZ 1 — Tasarım Sistemi (Liquid Glass)
1. `DesignSystem`: renk paleti, tipografi, boşluk ölçeği, animasyon eğrileri.
2. Yeniden kullanılabilir glass bileşenleri: `GlassCard`, `GlassButton`, `GlassSidebar`, `RiskBadge`, `LiveLogPanel`, `ProgressRing`.
3. `NSVisualEffectView` sarmalayıcı + macOS 26 fallback.
4. Reduce Transparency desteğini test et.
- **Çıktı:** Statik veriyle tasarım galerisi (bileşen showcase) ekranı.

### FAZ 2 — Çekirdek: Locations DB + Güvenlik
1. `RiskLevel`, `ScanCategory`, `FileItem`, `Models`.
2. `LocationsDatabase`: tüm güvenli yolların kategorize listesi (Bölüm 2.2–2.4).
3. `SafetyGuard`: blocklist + safe-root doğrulama + symlink çözümü (TOCTOU). **Unit testlerle** (örn. `/System` reddedilir, symlink kaçışı reddedilir).
- **Çıktı:** %100 test kapsamlı güvenlik katmanı. Hiçbir UI yok ama mantık kanıtlı.

### FAZ 3 — Tarama Motoru
1. `ScanEngine`: `TaskGroup` ile eşzamanlı dizin gezme, `URLResourceKey` prefetch (APFS hızlı boyut), iptal edilebilir.
2. Kategori başına boyut/öğe toplama, ilerleme yayını (`AsyncStream`).
3. İzin gerektiren yollarda zarif düşüş (FDA yoksa o kategoriyi "kilitli" göster).
- **Çıktı:** Konsoldan/test ekranından gerçek tarama; doğru boyutlar.

### FAZ 4 — İzinler (FDA)
1. `PermissionCoordinator`: FDA durumu tespiti (kontrollü bir korumalı yola okuma denemesi), Sistem Ayarları'na deep-link, polling + post-grant otomatik retry.
2. İlk açılış onboarding'i (animasyonlu, glass) — neden FDA gerektiğini açıklar.
- **Çıktı:** FDA verilince kilitli kategoriler otomatik açılır.

### FAZ 5 — Temizlik Motoru
1. `CleaningEngine`: `FileManager.trashItem` (trash-first), `SafetyGuard`'dan geçmeyen her şeyi reddet, her silme için canlı olay yay (yol + sonuç).
2. Hata toleransı: bir dosya silinemezse atla, raporla, devam et.
3. "Geri Al" = Çöp'ten geri (kullanıcıya hatırlatma; Çöp zaten geri alınabilir).
- **Çıktı:** Gerçek silme; canlı yol akışı; kazanılan alan özeti.

### FAZ 6 — Özellik Ekranları (UI + ViewModel)
Sırayla, her biri tam çalışır:
1. **System Junk** (en yüksek değer) → 2. **Smart Scan** → 3. **Large & Old Files** → 4. **Uninstaller** (`AppPathFinder`) → 5. **Privacy** → 6. **Trash/Mail** → 7. **Space Lens** (treemap).
- Her ekran: tara → yol+boyut+risk listesi → seç → onayla → canlı sil → özet.

### FAZ 7 — Cila & Performans
1. Eşzamanlılık ayarı (256 GB tam tarama hedefi: hızlı, donmayan UI).
2. Animasyon akıcılığı (morphing, geçişler), boş/yükleniyor/hata durumları.
3. Bellek profili (büyük tarama sonuçlarında).

### FAZ 8 — Paketleme & Dağıtım
1. Developer ID ile imzalama + **notarization** (Gatekeeper için).
2. `.dmg` veya `.app` üretimi. (İsteğe bağlı: kendi `brew tap`'imiz — sildiğin mac-sai/puremac gibi, ama kendi kontrolümüzde.)
- **Çıktı:** Çift tıkla kurulabilen, imzalı, lokalde çalışan uygulama.

### FAZ 9 (Opsiyonel/İleri) — Root Temizlik
1. `SMAppService` ile XPC privileged helper (root-owned `/Library/Caches`, `/private/var/log` vb.).
2. Dar allow-list, ayrı onay akışı.

---

## 6. Doğrulama (Her Faz İçin)
- **Birim test:** `SafetyGuard` (blocklist/symlink), `LocationsDatabase` tutarlılığı, `AppPathFinder` eşleştirme.
- **Manuel/entegrasyon:** Geçici test dosyaları oluştur (`~/Library/Caches/PureGlassTest/...`), tara → doğru boyut → sil → Çöp'te olduğunu doğrula. **Asla** gerçek `/System`'e dokunma testlerinde.
- **Güvenlik testi:** `/System`, symlink-kaçış, kilitli dosya → reddedilmeli.
- **UI:** Reduce Transparency açık/kapalı; FDA verili/verisiz; boş/dolu sonuç.
- **Performans:** Tam disk taraması süresi ölç; UI 60fps korunmalı.
- **Çalıştırma:** `xcodebuild` ile derle + uygulamayı aç, gerçek küçük temizlik yap, Çöp'ü kontrol et.

---

## 7. Riskler & Kararlar
- **App Store yok** (FDA + non-sandbox zorunlu) → doğrudan dağıtım, notarization şart.
- **SIP korumalı "sistem dosyaları" silinemez** — "derin sistem temizliği" = erişilebilir sistem cache/log + (ileride) root helper ile root-owned cache. Bunu UI'da dürüstçe belirt.
- **Trash-first** asla taviz verilmez (veri güvenliği = senin ana motivasyonun).
- **Telemetri yok / tamamen offline** (gizlilik motivasyonu).

---

## 8. Kaynaklar
- [CleanMyMac — System Junk (MacPaw)](https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk)
- [CleanMyMac — Full Disk Access (MacPaw)](https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access)
- [Which hidden files you can safely delete (AppleInsider)](https://appleinsider.com/inside/macos/tips/which-hidden-files-you-can-safely-delete-from-your-mac)
- [Is it safe to delete cache files (iBoysoft)](https://iboysoft.com/wiki/library-caches-mac.html)
- [Permissions, SIP and TCC (Eclectic Light)](https://eclecticlight.co/2025/11/08/explainer-permissions-privacy-and-tcc/)
- [Apple — glassEffect(_:in:)](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [Apple — GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
- [Apple — Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Liquid Glass Reference (conorluddy)](https://github.com/conorluddy/LiquidGlassReference)
- [Transparent window in SwiftUI macOS (Apple Forums)](https://developer.apple.com/forums/thread/694837)
- [Customizing macOS window background (Nil Coalescing)](https://nilcoalescing.com/blog/CustomizingMacOSWindowBackgroundInSwiftUI/)
- [macOS 26 transparent/glass background issue (cmux #2459)](https://github.com/manaflow-ai/cmux/issues/2459)
- [Beyond App Sandbox (AppCoda)](https://www.appcoda.com/mac-app-sandbox/)
- **Referans uygulamalar (açık kaynak):** [PureMac](https://github.com/momenbasel/PureMac) · [MacSai](https://github.com/iliyami/MacSai)
