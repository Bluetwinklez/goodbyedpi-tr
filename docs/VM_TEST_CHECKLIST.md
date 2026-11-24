# GoodbyeDPI-TR — Windows VM Doğrulama Kontrol Listesi (Sürüm Kapısı)

Bu kontrol listesi, yeni bir sürümü (ör. `v1.2.0`) yayımlamadan önce mock'lu Pester testlerinin kapsayamadığı **gerçek Windows hizmeti, WinDivert sürücüsü, görev zamanlayıcı, ACL izinleri, yeniden başlatma ve gerçek ağ** davranışlarını doğrulamak için hazırlanmıştır.

Her aşamanın kanıt çıktısı `scripts/vm-verify.ps1` ile otomatik toplanır.

---

## Ön Koşullar

- [ ] Temiz Windows 10 (1803+) veya Windows 11 x64 sanal makinesi (snapshot alınmış)
- [ ] Bir **Yönetici** hesabı ve bir **Standart Kullanıcı** hesabı
- [ ] Test edilecek release paketi (`GoodbyeDPI-TR-vX.Y.Z.zip`) ve `.sha256` dosyası
- [ ] (Önerilen) Engelli hedeflerin gerçekten test edilebildiği bir Türk İSS bağlantısı / VDS

---

## Bölüm 1 — Paket Bütünlüğü ve Başlangıç Anlık Görüntüsü

1. İndirilen ZIP dosyasının SHA-256 özetini doğrula:
   ```powershell
   Get-FileHash .\GoodbyeDPI-TR-vX.Y.Z.zip -Algorithm SHA256
   Get-Content .\GoodbyeDPI-TR-vX.Y.Z.zip.sha256
   ```
   - [ ] İki hash birebir eşleşiyor.
2. ZIP içeriğini bir klasöre çıkar ve şu dosyaların bulunduğunu doğrula:
   - [ ] `GoodbyeDPI-TR.cmd`, `gdpi-tr.ps1`, `README.md`, `README.tr.md`, `SECURITY.md`, `LICENSE`, `listeler\turkiye.txt`, `listeler\kullanici.txt`
3. Kurulum öncesi başlangıç kanıtını topla:
   ```powershell
   .\scripts\vm-verify.ps1 -Asama oncesi -CiktiDizini C:\vm-kanit
   ```
   - [ ] `vm-verify-oncesi-*.json` ve `.md` üretildi.

---

## Bölüm 2 — Temiz Kurulum, `bul` ve Temel Komutlar

Yönetici PowerShell oturumunda:

1. Profil ve DNS bulma:
   ```powershell
   .\gdpi-tr.ps1 bul
   ```
   - [ ] DNS adayları UDP ile ölçüldü, en hızlı çalışan sunucu seçildi.
   - [ ] Çalışan profil bulundu; gerekliyse ek profiller hız karşılaştırmasıyla elendi (`--set-ttl` gereksiz yere seçilmedi).
2. Hizmet olarak kurulum:
   ```powershell
   .\gdpi-tr.ps1 kur
   ```
   - [ ] Resmi ValdikSS paketi indirildi ve SHA-256 hash'leri doğrulandı.
   - [ ] `C:\Program Files\GoodbyeDPI-TR` altına kuruldu.
   - [ ] `GoodbyeDPI-TR` hizmeti `Running` ve `Auto` durumunda.
   - [ ] `GoodbyeDPI-TR Bekci` zamanlanmış görevi `SYSTEM` hesabıyla kayıtlı.
   - [ ] Başlat menüsü kısayolu ve Programlar ve Özellikler kaydı oluştu.
3. Okuma ve ölçüm komutları:
   ```powershell
   .\gdpi-tr.ps1 durum
   .\gdpi-tr.ps1 durum -Json
   .\gdpi-tr.ps1 rapor
   .\gdpi-tr.ps1 hiz -Tekrar 3 -Kaydet
   .\gdpi-tr.ps1 hiz -Gecmis
   .\gdpi-tr.ps1 hiz -DnsSirala
   .\gdpi-tr.ps1 hiz -Oneriler
   ```
   - [ ] `durum -Json` geçerli JSON döndürüyor, `SonOlcum` alanı doluyor.
   - [ ] `rapor` çıktısında kullanıcı adı, tam dosya yolu veya ham IP adresi bulunmuyor.
   - [ ] `hiz -DnsSirala` ve `hiz -Oneriler` hiçbir ayarı değiştirmeden temiz çalışıyor.

---

## Bölüm 3 — Yükseltme (`v1.1.1 -> yeni sürüm`) ve Rollback

1. Temiz snapshot üzerinde önce `v1.1.1` kur.
2. `C:\Program Files\GoodbyeDPI-TR\listeler\kullanici.txt` dosyasına özel bir test alan adı (ör. `ornek-kullanici-test.example`) ekle.
3. Yeni sürüm klasöründen `.\gdpi-tr.ps1 kur` çalıştır:
   - [ ] `kullanici.txt` içindeki özel satır korundu.
   - [ ] `ayarlar.json` ve `ayarlar.json.bak` geçerli JSON olarak oluştu.
   - [ ] Hizmet kesintisiz yeni sürümle çalışmaya devam ediyor.
4. Rollback senaryosu (isteğe bağlı ama önerilen):
   - İnterneti geçici kesip veya bozuk bir liste/paket koşulu oluşturup güncelleme/kurulum hata yolunu tetikle.
   - [ ] Önceki çalışan dosyalar, liste ve hizmet yolu bozulmadan geri yüklendi.

---

## Bölüm 4 — Kalıcı Duraklatma, Yeniden Başlatma, Uyku/Uyanma ve Kilit

1. Kalıcı duraklatma ve yeniden başlatma:
   ```powershell
   .\gdpi-tr.ps1 duraklat
   ```
   - [ ] Hizmet `Stopped`, başlangıç türü `Disabled`.
   - [ ] Windows'u yeniden başlat (`Restart-Computer`).
   - [ ] Açılış sonrası `.\gdpi-tr.ps1 durum -Json` çıktısında `Duraklatildi: true`, `Hizmet: Stopped`.
   - [ ] Bekçi görevini elle tetikle (`Start-ScheduledTask -TaskName 'GoodbyeDPI-TR Bekci'`) → hizmet **başlamamalı**.
   - [ ] `.\gdpi-tr.ps1 devam` → hizmet tekrar `Running` ve `Auto`.
2. Uyku / uyanma veya ağ kesintisi:
   - Ağ bağdaştırıcısını 30 sn devre dışı bırak (veya VM'i uyut/uyandır), bu sırada bekçiyi tetikle, sonra ağı geri aç.
   - [ ] `bekci.log` içinde ağ yokken hizmetin gereksiz yere durdurulmadığı / DNS'in değiştirilmediği görülüyor.
3. Eşzamanlı kilit yarışı:
   - İki ayrı yönetici PowerShell penceresinde aynı anda uzun süren iki komut (ör. `liste-guncelle` ve `bekci` veya `kur`) başlat.
   - [ ] İkinci işlem kilit nedeniyle güvenli şekilde reddediliyor veya sessizce çıkıyor; JSON/liste dosyaları bozulmuyor.

---

## Bölüm 5 — Güvenlik Doğrulaması (ACL, Junction, Standart Kullanıcı)

1. Kurulum sonrası otomatik kanıt ve güvenlik denetimini çalıştır:
   ```powershell
   .\scripts\vm-verify.ps1 -Asama sonrasi -CiktiDizini C:\vm-kanit -GdpiBetigi 'C:\Program Files\GoodbyeDPI-TR\gdpi-tr.ps1'
   ```
   - [ ] `KurulumDizini` ve `VeriDizini` ACL denetimi `Guvenli: true` (standart kullanıcıların yazma izni yok).
   - [ ] `HizmetSddl` denetimi `Guvenli: true` (standart kullanıcılar hizmeti değiştiremiyor).
   - [ ] Kurulum ağacında beklenmedik reparse point / junction yok.
   - [ ] `RaporGizlilik` denetimi `Guvenli: true`.
2. **Standart Kullanıcı** oturumuyla giriş yap:
   - [ ] `durum -Json`, `rapor`, `hiz -Tekrar 2`, `hiz -Oneriler` yönetici istemeden çalışıyor.
   - [ ] `C:\Program Files\GoodbyeDPI-TR\veri\ayarlar.json` veya `gdpi-tr.ps1` üzerine yazma denemesi `Access Denied` ile reddediliyor.

---

## Bölüm 6 — 24 Saat Bekçi Gözlemi

1. VM'i çalışan hizmetle birlikte en az **24 saat** açık bırak (normal kullanım + birkaç ağ yenilemesi).
2. 24 saat sonunda bekçi günlüğünü analiz et:
   ```powershell
   .\scripts\vm-verify.ps1 -Asama bekci24s -SaatPenceresi 24 -CiktiDizini C:\vm-kanit -GdpiBetigi 'C:\Program Files\GoodbyeDPI-TR\gdpi-tr.ps1'
   ```
   - [ ] Sabit ağda gereksiz `DnsDegisimi` sayısı = **0**.
   - [ ] Sabit ağda boşuna `HizmetYenidenBaslatma` sayısı = **0**.
   - [ ] `bekci.json` ve `ayarlar.json` hatasız okunuyor, `.bak` kurtarma uyarısı yok.

---

## Bölüm 7 — Güvenli Kaldırma ve Paylaşılan WinDivert

1. Normal kaldırma:
   ```powershell
   .\gdpi-tr.ps1 kaldir
   ```
   - [ ] `GoodbyeDPI-TR` hizmeti silindi.
   - [ ] `GoodbyeDPI-TR Bekci` zamanlanmış görevi silindi.
   - [ ] Başlat menüsü kısayolu ve Programlar ve Özellikler kaydı temizlendi.
   - [ ] `C:\Program Files\GoodbyeDPI-TR` klasörü kaldırıldı (paylaşılan WinDivert yoksa).
2. Paylaşılan WinDivert testi (ayrı snapshot veya tekrar kurulumda):
   - Başka bir WinDivert hizmet kaydı varken `kaldir` çalıştır.
   - [ ] Paylaşılan WinDivert sürücüsü ve kurulu `bin` klasörü korundu; başka araç bozulmadı.

---

## Sürüm Kapısı Kararı

- [ ] Bölüm 1–7 tamamlandı ve `C:\vm-kanit` raporlarında engelleyici bulgu yok.
- [ ] `gdpi-tr.ps1` içindeki `$Script:Surum` değeri hedef etiketle eşleştirildi (ör. `1.2.0`).
- [ ] `v1.2.0` etiketi ve GitHub Release yayımlanabilir.

