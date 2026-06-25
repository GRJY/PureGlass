# PureGlass — Sistem Monitörü & Fan Kontrolü Araştırması

> **Amaç:** CPU yönetimi, sıcaklık/termal veriler ve fan kontrolünü PureGlass'e ekleyip
> "tüm verilere tek panelden hâkim olunan" bir Mac kontrol merkezi yapmak.
>
> **Hedef cihaz (doğrulandı):** MacBook Pro 13" — **MacBookPro17,1, Apple M1**, 4P+4E çekirdek, **fanlı**.

---

## 1. Kritik gerçek: Apple Silicon ≠ Intel, ve M1 ≠ M3+

- Sıcaklık/fan verisi **SMC** (System Management Controller) üzerinden okunur ama **anahtarlar her çipte farklıdır** (M1, M2, M3, M4, M5 ayrı haritalar gerektirir). SMC "kararsız" bir API'dir.
- **Fan YAZMA (kontrol):**
  - **M1 / M2:** tek bir SMC yazımı yeterli → **çalışır** ✅
  - **M3+:** `thermalmonitord` "korumalı mod" uyguluyor; `F0Md`/`F0Tg` yazımı `Ftst` (force/test) ayarlanmadan bloklu → **sorunlu/çalışmaz** ⚠️ (Macs Fan Control'ün bile açık hata kayıtları var)
  - **M5:** fan anahtarları farklı veri tiplerine geçmiş.
- **Bizim için iyi haber:** Hedef Mac **M1** → fan kontrolü teknik olarak mümkün. (Yine de kodu çip-tespitiyle yazıp M3+'da kontrolü kapatacağız.)

---

## 2. Neyi nasıl okuyacağız (hepsi YETKİSİZ — root gerekmez)

| Veri | Yöntem | Not |
|---|---|---|
| **CPU kullanımı** (toplam + P/E) | `host_processor_info` / `host_statistics` (Mach API) | Public, root yok |
| **RAM / bellek baskısı** | `host_statistics64` (vm_statistics) | Public |
| **Termal baskı** (throttle var mı) | `ProcessInfo.thermalState` (nominal/fair/serious/critical) + `pmset -g therm` (CPU_Speed_Limit) | **Public API** — en güvenilir "kısılıyor mu" göstergesi |
| **CPU/GPU sıcaklığı** | SMC anahtarları (M1: P-core `Tp01,Tp05,Tp09,Tp0D…`, E-core `Tp0T…`, GPU `Tg05,Tg0D,Tg0L,Tg0T`) **veya** IOHIDEventSystem termal sensörleri | SMC okuma root istemez; IOHID daha stabil ama daha karmaşık |
| **Batarya sıcaklığı** | SMC `TB0T/TB1T/TB2T` | |
| **Fan RPM** (anlık/min/maks/hedef) | SMC `F0Ac` (anlık), `F0Mn` (min), `F0Mx` (maks), `F0Tg` (hedef), `F0Md` (mod), `FNum` (sayı) | Okuma root istemez |
| **Güç (CPU/GPU watt)** | `powermetrics` (sudo) **veya** IOReport | powermetrics zengin ama root + ağır |

**SMC okuma mekanizması:** IOKit `AppleSMC` servisini `IOServiceOpen` ile aç → `IOConnectCallStructMethod` ile `SMCKeyData` struct gönder (key + komut). Değerler tip-kodlu gelir (`flt` float32, `sp78`, `fpe2`…); anahtarın `keyInfo`'sundan veri tipini okuyup ona göre çöz. (Kanıtlı uygulama: **exelban/stats**, **beltex/SMCKit**, **smcFanControl**.)

---

## 3. Fan KONTROLÜ (yazma) — root + dikkat

- **Yazma root ister.** Uygulamamız kullanıcı olarak çalışıyor; SMC'ye root yazmak için:
  - SMAppService privileged helper → **ücretli Developer ID gerekir** (yok).
  - **Çözüm:** SMC yazımını yapan **küçük bir CLI yardımcı binary** paketleyip, onu `AdminShell` (do shell script with administrator privileges) ile **tek parola istemiyle root** çalıştırmak. (Privileged cleaner'da kanıtlanan yaklaşım.)
- **Kontrol akışı (M1):** `F0Md = 1` (zorunlu mod) → `F0Tg = hedef RPM` (tip-kodlu yaz). Otomatiğe dönüş: `F0Md = 0`.
- **GÜVENLİK (taviz yok):**
  - Hedef RPM **sadece `F0Mn`..`F0Mx`** aralığında kabul edilir.
  - Uygulamadan çıkışta / "Otomatik" düğmesiyle **her zaman `F0Md=0`'a döndür** (fanı kapalı bırakma).
  - Çip M1/M2 değilse **kontrolü tamamen gizle** (sadece okuma).
  - "Fanı tamamen durdurma" seçeneği YOK — yalnızca min..maks arası hız.

---

## 4. Önerilen plan (fazlar)

### FAZ A — Sistem Monitörü (salt-okunur, root yok) ← önce bu
Yeni sidebar bölümü: **"Sistem Monitörü"**. Canlı (1 sn) gösterge:
- CPU kullanımı (toplam + P/E çekirdek grafiği), RAM/bellek baskısı
- **Termal durum** (ProcessInfo.thermalState rozeti: Normal/Orta/Yüksek/Kritik) + CPU hız limiti (%)
- CPU & GPU sıcaklığı (SMC, M1 anahtar haritası) — okunabilirse
- Fan RPM (anlık / maks)
- (Opsiyonel) Güç: powermetrics sadece kullanıcı isterse (sudo)

**Çekirdek:** `SystemMetrics` (Mach API), `SMCReader` (IOKit, salt-okunur), `ThermalMonitor` (ProcessInfo). Tam test edilebilir (struct decode, key map).

### FAZ B — Fan Kontrolü (M1/M2, root yardımcı ile)
- Çip M1/M2 ise: "Otomatik / Manuel" geçişi + RPM kaydırıcı (F0Mn..F0Mx).
- Bundled `pgsmc` yardımcı binary + `AdminShell` ile root yazım.
- Güçlü uyarılar, çıkışta otomatik geri dönüş.
- M3+ ise: "Bu çipte fan kontrolü desteklenmiyor (Apple kısıtlaması)" notu + sadece okuma.

### FAZ C — Menü çubuğu entegrasyonu
- Menü panelindeki canlı disk göstergesinin yanına **CPU % + sıcaklık + fan RPM** mini göstergeleri.

---

## 5. Dürüst sınırlar
- SMC anahtarları çip-bağımlı; her M-serisi için harita gerekir (başta M1; sonra genişletiriz).
- Fan kontrolü **M3+'da Apple tarafından kısıtlı** — orada sadece okuma sunacağız (yalan vaat yok).
- powermetrics tabanlı güç/sıcaklık root ister; varsayılan değil, opsiyonel.
- Reading bile bazı SMC anahtarlarında modelden modele değişebilir; bulunamayan değer "—" gösterilir.

## 6. Kaynaklar
- [exelban/stats](https://github.com/exelban/stats) — referans menü-çubuğu monitörü (Intel + Apple Silicon, MIT)
- [beltex/SMCKit](https://github.com/beltex/SMCKit) — Swift SMC kütüphanesi (SMC.swift protokolü)
- [dkorunic/iSMC](https://github.com/dkorunic/iSMC) — M1–M5 SMC CLI (anahtar haritaları)
- [hholtmann/smcFanControl](https://github.com/hholtmann/smcFanControl) — fan yazma (F0Md/F0Tg, fpe2 encode)
- [fermion-star/apple_sensors](https://github.com/fermion-star/apple_sensors) — M1 sıcaklık sensör anahtarları
- [stats#2928](https://github.com/exelban/stats/issues/2928) — M3/M4 fan kontrolü neden çalışmıyor
- Apple: `ProcessInfo.thermalState` (public termal durum API'si)
