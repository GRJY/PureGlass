# 11 — Ağ & Ağ Ayarları — Araştırma

PureGlass 1.2 hedefi: **ağ izleme + kolay ağ ayarları**. Sistemin internetle ne kadar
sağlam/stabil bağlı olduğunu gösteren metrikler + DNS gibi şeyleri tek tıkla değiştiren
kısayollar. Tümü lokalde, telemetri yok.

Bu Mac'te (MacBookPro17,1, M1, macOS 26, en0/Wi-Fi) doğrulanmıştır.

---

## 1. Neyi okuyabiliyoruz (root YOK)

### Bağlantı bilgisi
- **Aktif arayüz + ağ geçidi:** `route -n get default` → `interface: en0`, `gateway: 192.168.0.1`. ✅
- **Arayüz → servis adı eşlemesi** (networksetup servis adı ister, arayüz değil):
  `networksetup -listnetworkserviceorder` çıktısında `(Hardware Port: Wi-Fi, Device: en0)`.
- **IP / netmask:** `ipconfig getifaddr en0`, SCNetworkConfiguration veya `getifaddrs`.
- **Bağlantı tipi:** servis adı (Wi-Fi / Ethernet / Thunderbolt Bridge…).

### Wi-Fi (CoreWLAN, root yok) ✅
`CWWiFiClient.shared().interface()`:
- `rssiValue()` → **-54 dBm** (sinyal gücü; ~-50 mükemmel, -70 zayıf, -80 kötü)
- `noiseMeasurement()` → -93 dBm (SNR = rssi − noise hesaplanır)
- `transmitRate()` → **573 Mbps** (anlık link hızı)
- `wlanChannel()?.channelNumber` → 40 (5GHz)
- `interfaceName` → en0
- ⚠️ `ssid()` → **boş** döndü. macOS 14+'da SSID okumak **Konum Servisleri izni** (CoreLocation)
  gerektirir. Sinyal/hız/kanal izinsiz gelir; SSID için ya CLLocationManager izni istenir
  ya da SSID gösterilmez (sinyal gücü zaten yeterli bağlam).

### Kararlılık (stability) — ping ölçümü
`ping -c N <host>` (ör. ağ geçidi + 1.1.1.1):
```
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 18.516/21.733/26.827/3.643 ms
```
- **Gecikme (latency):** avg = 21.7 ms ✅
- **Jitter:** stddev = 3.6 ms (kararlılığın anahtar metriği — düşük = stabil) ✅
- **Paket kaybı:** % ✅
- Canlı: sürekli ping ile gecikme zaman serisi → CPU grafiği gibi smooth çizgi + anlık jitter/kayıp.
- İki hedef: **ağ geçidi** (yerel ağ/router sağlığı) ve **1.1.1.1** (internet sağlığı) ayrı izlenir.

### Hız testi — Apple resmi aracı ✅
`/usr/bin/networkQuality` (Monterey+ yerleşik). `networkQuality -c` → bitince JSON:
- `dl_throughput`, `ul_throughput` (bit/s) → indirme/yükleme Mbps
- `responsiveness` (RPM — yük altında tepkisellik, yüksek = iyi)
- ~15–25 sn sürer, gerçek bant genişliği kullanır → kullanıcı butonla başlatır, ilerleme gösterilir.
- Kendi sunucu/altyapımız gerekmez; Apple/Cloudflare uçları kullanılır, gizlilik dostu.

### Mevcut DNS (root yok)
- `networksetup -getdnsservers <service>` → IP listesi veya "There aren't any..." (= Otomatik/DHCP).
- `scutil --dns` → etkin nameserver'lar. Bu Mac: **8.8.8.8 (Google)**.

---

## 2. Neyi değiştirebiliyoruz (root / admin — AdminShell, tek parola)

`networksetup` değişiklikleri yönetici hakkı ister → `pgsmc` gibi değil, doğrudan
**AdminShell** (`do shell script ... with administrator privileges`) ile, tek parola istemiyle.

### DNS yönetimi (kolay kısayollar)
- **Preset uygula:** `networksetup -setdnsservers <service> <ip1> <ip2>`
  - Cloudflare: `1.1.1.1 1.0.0.1` (en hızlı + gizlilik)
  - Google: `8.8.8.8 8.8.4.4`
  - Quad9 (kötü amaçlı engelleme): `9.9.9.9 149.112.112.112`
  - OpenDNS: `208.67.222.222 208.67.220.220`
- **Otomatiğe dön (DHCP):** `networksetup -setdnsservers <service> empty`
- **Özel DNS:** kullanıcı kendi IP'lerini girer.
- Değişiklik sonrası DNS önbelleği temizlenir (`dscacheutil -flushcache; killall -HUP mDNSResponder`).
- ✅ Güvenli ve geri alınabilir: tek tıkla "Otomatik"e dönülür.

### Diğer kısayollar
- **DNS önbelleğini temizle:** (zaten Bakım'da var; ağda da kısayol).
- **DHCP kirasını yenile (IP yenile):** `networksetup -setdhcp <service>` veya `ipconfig set en0 DHCP`.
- **Wi-Fi aç/kapat:** `networksetup -setairportpower en0 off|on`.

### Yapmayacaklarımız (güvenlik)
- Proxy/VPN yapılandırması, statik IP zorlama, paket yakalama → kapsam dışı (riskli/karmaşık).
- Genel IP sorgusu (whatismyip) dış istek gerektirir → **varsayılan kapalı**, opsiyonel; telemetri-yok ilkesini korur.

---

## 3. Fazlı plan

### FAZ A — Ağ Monitörü (salt-okunur, root yok) ← önce bu
Yeni "Ağ" sidebar bölümü + kartlar:
- **Bağlantı:** arayüz, tip (Wi-Fi/Ethernet), IP, ağ geçidi, aktif DNS.
- **Wi-Fi sinyali:** RSSI → kalite çubuğu/yüzde + link hızı (Mbps) + kanal.
- **Kararlılık (canlı):** ağ geçidi + 1.1.1.1'e sürekli ping → gecikme grafiği (Canvas, smooth),
  anlık jitter ve paket kaybı; renkli durum (yeşil/sarı/kırmızı).
- **Hız testi:** "Testi Başlat" → networkQuality → indirme/yükleme/RPM.

### FAZ B — Ağ Ayarları & Kısayollar (admin, tek parola)
- DNS preset'leri (Cloudflare/Google/Quad9/OpenDNS/Otomatik/Özel) + uygula → flush.
- DNS önbelleği temizle, DHCP yenile, Wi-Fi aç/kapat.
- Hepsi geri alınabilir; uygulanınca durum anında güncellenir.

### FAZ C — Menü paneline mini ağ durumu (opsiyonel)
- Panelde küçük "Ağ" göstergesi: sinyal + gecikme + DNS adı.

---

## 4. Mimari (taslak)
- **Core (PureGlassKit, test edilir, UI-bağımsız):**
  - `NetworkInfo` — aktif servis/arayüz, IP, ağ geçidi, tip (route/getifaddrs/SCNetworkConfiguration).
  - `WiFiInfo` — CoreWLAN sarmalayıcı (rssi, rate, channel, noise; SSID opsiyonel/izinli).
  - `PingMonitor` — sürekli ping → latency serisi, jitter, kayıp (Process tabanlı, parse).
  - `SpeedTest` — networkQuality sarmalayıcı (JSON parse).
  - `DNSManager` — oku (`-getdnsservers`/scutil), yaz (AdminShell), preset'ler, servis-adı çözümü.
- **Features:** `NetworkView` + `NetworkViewModel` (canlı), AdminShell ile değişiklikler.
- Çizim: kararlılık grafiği için **Canvas** (Sistem Monitörü CPU grafiği gibi — yanıp sönme yok).

## 5. Doğrulanan komut/araç özeti
| İhtiyaç | Yöntem | Root | Durum |
|---|---|---|---|
| Aktif arayüz/ağ geçidi | `route -n get default` | yok | ✅ |
| Wi-Fi sinyal/hız/kanal | CoreWLAN | yok | ✅ |
| SSID | CoreWLAN + Konum izni | yok* | ⚠️ izin gerekir |
| Gecikme/jitter/kayıp | `ping` | yok | ✅ |
| Hız (indirme/yükleme) | `networkQuality -c` | yok | ✅ |
| Mevcut DNS | `networksetup -getdnsservers` / `scutil --dns` | yok | ✅ |
| DNS değiştir | `networksetup -setdnsservers` | **admin** | AdminShell |
| DHCP yenile / Wi-Fi aç-kapa | `networksetup` | **admin** | AdminShell |
