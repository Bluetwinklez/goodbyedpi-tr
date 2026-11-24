# GoodbyeDPI-TR

[![CI](https://github.com/Bluetwinklez/goodbyedpi-tr/actions/workflows/ci.yml/badge.svg)](https://github.com/Bluetwinklez/goodbyedpi-tr/actions/workflows/ci.yml)
[![Secret scanning](https://github.com/Bluetwinklez/goodbyedpi-tr/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/Bluetwinklez/goodbyedpi-tr/actions/workflows/secret-scan.yml)
[![Lisans: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> **[English Guide (README.md)](README.md)** · **[Değişiklik Günlüğü](CHANGELOG.md)** · **[Güvenlik Politikası](SECURITY.md)** · **[VM Doğrulama Listesi](docs/VM_TEST_CHECKLIST.md)**

Türkiye ağ koşulları için [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) kurulum, teşhis ve hizmet yönetim aracı. [GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey) fork'unun sık karşılaşılan sorunlarını gidermek için yeniden yazıldı.

> **VPN değildir:** Trafiğinizi şifrelemez, IP adresinizi gizlemez. Yalnızca alan adı (DNS) ve SNI tabanlı erişim engellerini aşar; IP tabanlı engellerde işe yaramaz.

---

## Neden GoodbyeDPI-TR?

| GoodbyeDPI-Turkey sorunu | GoodbyeDPI-TR çözümü |
|---|---|
| Hileler tüm trafiğe uygulanır; oyunlar, bankalar ve devlet siteleri bozulabilir | Varsayılan olarak yalnızca `listeler/` içindeki alan adlarına uygulanır |
| İSS'e göre farklı `.cmd` dosyalarını elle denemek gerekir | `bul` komutu güvenli profilleri ve DNS adaylarını ölçerek en iyisini seçer |
| DNS sorguları tek sunucuya gider; sunucu düşerse internet kesilir | Quad9 (`9953`), OpenDNS (`443`), Yandex (`1253`) doğrudan UDP gecikmesiyle ölçülür |
| Kurulum sonrası bağlantı bozulursa elle onarmak gerekir | Kurulum ve liste güncellemelerinde bağlantı testi ve otomatik geri alma (rollback) vardır |
| Ağ değişiminde veya DNS kopmasında hizmet bozulur | `SYSTEM` bekçi görevi DNS'i ve bağlantıyı izler, gereksiz yeniden başlatma yapmaz |
| Klasör taşınınca hizmet bozulur, kaldırmak zordur | `C:\Program Files\GoodbyeDPI-TR` altına kurulur; `kaldir` ile temizce silinir |
| ZIP içinde doğrulanmamış ikili dosyalar dağıtılır | Resmi ValdikSS paketi indirilir; ZIP ve her ikili dosya SHA-256 ile doğrulanır |

---

## Hızlı Başlangıç

1. [Releases](https://github.com/Bluetwinklez/goodbyedpi-tr/releases) sayfasından son sürüm ZIP dosyasını ve `.zip.sha256` özetini indirin.
2. İndirilen ZIP dosyasını PowerShell'de doğrulayın:
   ```powershell
   Get-FileHash -Algorithm SHA256 .\GoodbyeDPI-TR-vX.Y.Z.zip
   Get-Content .\GoodbyeDPI-TR-vX.Y.Z.zip.sha256
   ```
3. Klasöre çıkarıp **`GoodbyeDPI-TR.cmd`** dosyasına çift tıklayın (yönetici izni ister).
4. Menüden **1) Çalışan ayarı bul ve kur (önerilen)** seçeneğini seçin.

Kurulum sonrası araç `C:\Program Files\GoodbyeDPI-TR` altında kalır, Başlat menüsüne ve Programlar ve Özellikler listesine eklenir; indirdiğiniz klasörü silebilirsiniz.

---

## Komutlar

### Kurulum ve Hizmet Yönetimi

| Komut | Yetki | Açıklama |
|---|---|---|
| `.\gdpi-tr.ps1 bul` | Yönetici | Çalışan en hızlı güvenli profili ve DNS sunucusunu bul |
| `.\gdpi-tr.ps1 kur` | Yönetici | Hizmet ve bekçi görevini kur veya yükselt |
| `.\gdpi-tr.ps1 durum` | Yönetici | Hizmet, bekçi, profil ve canlı erişim durumu |
| `.\gdpi-tr.ps1 durum -Json` | Kullanıcı | Yönetici izni ve ağ testi olmadan yapılandırılmış JSON durum |
| `.\gdpi-tr.ps1 duraklat` | Yönetici | Hizmeti yeniden başlatma sonrası da kalıcı duraklat (`Disabled`) |
| `.\gdpi-tr.ps1 devam` | Yönetici | Duraklatılan hizmeti yeniden etkinleştir |
| `.\gdpi-tr.ps1 doktor` | Yönetici | Çakışan VPN, antivirüs ve diğer DPI yazılımlarını tara |
| `.\gdpi-tr.ps1 rapor` | Kullanıcı | Özel bilgi içermeyen çevrimdışı teşhis JSON raporu üret |
| `.\gdpi-tr.ps1 kaldir` | Yönetici | Hizmeti, bekçi görevini ve uygulama dosyalarını güvenle kaldır |
| `.\gdpi-tr.ps1 kaldir -Eski` | Yönetici | Eski `GoodbyeDPI` hizmetini de kaldır |

### Hız ve Bağlantı Teşhisi (`hiz`)

Tüm `hiz` kipleri **`-Json`** çıktısını destekler (yalnızca `-AB` yönetici izni gerektirir):

| Komut | Yetki | Açıklama |
|---|---|---|
| `.\gdpi-tr.ps1 hiz [-Tekrar N]` | Kullanıcı | DNS, TCP, TLS, sunucu ve ilk bayt sürelerini ölç (ortanca & p90) |
| `.\gdpi-tr.ps1 hiz -Kaydet` | Kullanıcı | Sayısal özeti yerelde kaydet ve önceki kayıtla karşılaştır |
| `.\gdpi-tr.ps1 hiz -Gecmis` | Kullanıcı | Kayıtlı ölçümleri listele (son 50 kayıt) |
| `.\gdpi-tr.ps1 hiz -DnsSirala` | Kullanıcı | DNS adaylarını doğrudan UDP gecikmesine göre sırala (salt okunur) |
| `.\gdpi-tr.ps1 hiz -Oneriler` | Kullanıcı | Hızı sınırlayabilecek sistem ayarlarını tara (salt okunur) |
| `.\gdpi-tr.ps1 hiz -AB` | Yönetici | Hizmet kapalı ve açıkken aynı hedefleri karşılaştır (kilitli, eski duruma döner) |
| `.\gdpi-tr.ps1 hiz -Indirme` | Kullanıcı | İsteğe bağlı gerçek indirme testi (en çok 5 MB/deneme, `-IndirmeUrl` destekli) |

### Alan Adı Listeleri

| Komut | Yetki | Açıklama |
|---|---|---|
| `.\gdpi-tr.ps1 liste-guncelle` | Yönetici | `turkiye.txt` listesini indir, doğrula ve rollback korumalı uygula |
| `.\gdpi-tr.ps1 alan-listele [-Json]` | Kullanıcı | `listeler/kullanici.txt` içindeki özel alan adlarını listele |
| `.\gdpi-tr.ps1 alan-ekle -Hedef ornek.com` | Yönetici | Özel listeye alan adı ekle ve çalışan hizmeti güvenle yenile |
| `.\gdpi-tr.ps1 alan-sil -Hedef ornek.com` | Yönetici | Özel listeden alan adı kaldır ve çalışan hizmeti güvenle yenile |

> **Etkileşimli menü (`GoodbyeDPI-TR.cmd`):** **1–10** arası seçenekler kurulum, durum, doktor, liste güncelleme, kaldırma, duraklatma (**8**), devam (**9**) ve gizlilik raporunu (**10**) sunar. **11** numaralı seçenek **Hız ve Teşhis alt menüsünü**, **12** numaralı seçenek **Özel Alan Adı alt menüsünü** açar.

---

## Nasıl Çalışır?

1. **Kapsamlı liste ve özel alan adları:** İşlem varsayılan olarak yalnızca `listeler/turkiye.txt` ve `listeler/kullanici.txt` içindeki alan adlarına uygulanır. Özel siteleri `alan-ekle` / `alan-sil` / `alan-listele` ile (veya menü **12**'den) yönetebilirsiniz. Yeniden kurulum `kullanici.txt` dosyanızı korur. `-Genel` seçeneği tüm trafiği etkilediği için önerilmez.
2. **Gecikme tabanlı DNS seçimi:** Standart dışı porttaki DNS adayları (Quad9 `9953`, OpenDNS `443`, Yandex `1253`) işletim sistemi önbelleği olmadan doğrudan UDP ile ölçülür; engel IP'si (`195.175.254.x`) döndürenler elenir ve en düşük ortanca gecikmeli sunucu seçilir. Kayıtlı sunucu en iyiden **%20 + 15 ms**'den fazla yavaş değilse değiştirilmez.
3. **Ölçüme dayalı güvenli profil seçimi:** İlk çalışan profilden sonra en fazla iki güvenli profil daha denenir (riskli `--set-ttl` profillerine gereksiz geçilmez). Başka bir profil en az **30 ms ve %20** daha hızlı değilse en güvenli çalışan profil korunur.
4. **Bekçi görevi (`GoodbyeDPI-TR Bekci`):** `SYSTEM` hesabıyla açılışta, 15 dakikada bir ve ağ değişiminde çalışır (`C:\Program Files\GoodbyeDPI-TR\veri\bekci.log`):
   - Ağ bağlantısı yoksa hiçbir şeye dokunmaz.
   - DNS sunucusunu yalnızca **3 ardışık** denemede yanıt alınamazsa değiştirir.
   - Düzenli profil taraması mevcut profil ve DNS ile aynı sonucu verirse hizmeti gereksiz yeniden başlatmaz.
   - Hizmet duraklatılmışsa (`duraklat` / menü **8**) yeniden başlatma sonrası da `Disabled` kalır ve bekçi denetimleri atlar.
   - Liste güncellemeleri günde bir denenir; hata olursa 1 saat sonra yeniden denenir ve başarısızlıkta eski listeler geri yüklenir.

### Hız Ölçümü Notları
- `hiz` bir hat hızı testi değildir ve bant genişliğinizi artırmaz. Yalnızca **30 ms ve %20** üzerindeki farklar "daha hızlı" / "daha yavaş" olarak işaretlenir; daha küçük farklar ölçüm gürültüsü sayılır.
- `-Kaydet`, yalnızca sayısal özetleri (IP veya yol olmadan) `%LOCALAPPDATA%\GoodbyeDPI-TR\olcumler.json` dosyasına yazar; bekçi bu kullanıcı dosyasını okumaz. `durum -Json` son ölçümü `SonOlcum` alanında verir.
- `hiz -AB` ortak işlem kilidi (`Invoke-KilitliIslem`) içinde çalışır; kurulu olmayan veya duraklatılmış hizmette reddeder, hata/kesinti durumunda bile `finally` bloğunda hizmeti ilk haline döndürür.
- `hiz -Indirme` tamamen isteğe bağlıdır, deneme başına en çok **5 MB** / **20 sn** sınırla doğrudan `NUL`'a akar (diske yazmaz) ve `-IndirmeUrl` için yalnızca geçerli `https://` adreslerini kabul eder.

---

## Güvenlik ve Kurtarma

- **İkili doğrulama:** Resmi `ValdikSS/GoodbyeDPI` arşivi ve içindeki her dosya sabitlenmiş SHA-256 özetleriyle doğrulanır.
- **Kısıtlı kurulum klasörü:** Ayarlar ve günlük `C:\Program Files\GoodbyeDPI-TR\veri` altında tutulur (yalnızca yöneticiler yazabilir).
- **Atomik JSON ve `.bak` yedeği:** Her ayar yazımında son geçerli nesne `.bak` dosyasında saklanır; ana dosya bozulursa yedekten uyarıyla okunur.
- **Çakışma ve ortak sürücü koruması:** `bul` ve `kur`, başka `goodbyedpi.exe` süreçlerini veya eski `GoodbyeDPI` hizmetini izinsiz durdurmaz. `kaldir`, paylaşılan `WinDivert` kaydı varsa sürücüyü ve `bin` klasörünü korur.
- **Gizlilik korumalı teşhis (`rapor`):** Yalnızca sürüm, hizmet/bekçi durumu, profil, DNS sağlayıcı adı ve alan adı sayısını içerir; **IP adresi, kullanıcı adı, tam dosya yolu, hedef alan adı veya ham günlük içermez.**

Ayrıntılar için [SECURITY.md](SECURITY.md) ve [SECURITY_AUDIT.md](SECURITY_AUDIT.md) dosyalarına bakın.

---

## Sınırlar

- Windows 10 (1803+) veya Windows 11, x86/x64 gerekir (dahili `curl.exe`).
- **ARM64 desteklenmez** (WinDivert'in ARM64 sürücüsü yok).
- Discord sesli kanalları UDP kullanır; GoodbyeDPI UDP trafiğine hile uygulamaz.
- `-q` içeren profiller QUIC'i (HTTP/3) tüm sistemde engeller; tarayıcılar TCP'ye geçer.
- Otomatik testler hizmet ve sürücü çağrılarını mock'lar; gerçek Windows VM sürüm kapısı [docs/VM_TEST_CHECKLIST.md](docs/VM_TEST_CHECKLIST.md) ile izlenir.

---

## Geliştirme

```powershell
# Birim testlerini çalıştır
Invoke-Pester .\tests

# Depo ayarlarıyla PSScriptAnalyzer çalıştır
Invoke-ScriptAnalyzer -Path .\gdpi-tr.ps1 -Settings .\.PSScriptAnalyzerSettings.psd1

# VM doğrulama kanıt betiği (salt okunur)
.\scripts\vm-verify.ps1 -Asama sonrasi -CiktiDizini C:\vm-kanit
```

GitHub Actions her gönderimde Pester 4.10.1, PSScriptAnalyzer 1.23.0 (`Error` + `Warning`), release ZIP + SHA-256 smoke testi, Gitleaks taraması ve `v*` etiketinde `$Script:Surum` tutarlılık doğrulaması çalıştırır.

## Lisans

Bu depodaki betikler [MIT Lisansı](LICENSE) ile lisanslanmıştır. GoodbyeDPI (Apache-2.0) ve WinDivert (LGPL-3.0 / GPL-2.0) kendi lisanslarına tabidir.
