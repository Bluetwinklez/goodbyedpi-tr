# GoodbyeDPI-TR

Türkiye için [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) kurulum ve yönetim aracı. [GoodbyeDPI-Turkey](https://github.com/cagritaskn/GoodbyeDPI-Turkey) fork'unun sık şikâyet edilen sorunlarını gidermek için yeniden yazıldı.

> VPN değildir. Trafiğinizi şifrelemez, IP'nizi gizlemez. Yalnızca alan adı (DNS) ve SNI tabanlı erişim engellerini aşar. IP tabanlı engellerde işe yaramaz.

## Neden

| GoodbyeDPI-Turkey sorunu | GoodbyeDPI-TR |
|---|---|
| Hileler tüm trafiğe uygulanıyor; oyunlar, bankalar, devlet siteleri, yayın platformları bozuluyor | Varsayılan olarak yalnızca `listeler/` içindeki alan adlarına uygulanır |
| Sabit parametre; İSS'e göre 7 farklı `.cmd` dosyasını elle denemek gerekiyor | `bul` komutu 9 profili sırayla dener, çalışanı kendisi seçer |
| DNS tüm sorguları şifresiz olarak Yandex'e (Rusya) gönderiyor; Yandex'e ulaşılamazsa internet tamamen gidiyor | Önce Quad9 (filtresiz), sonra OpenDNS, en son Yandex denenir; yanıt vermeyen sunucu seçilmez |
| Kurulumdan sonra internet kesilirse kullanıcı ne olduğunu anlamıyor | Kurulumdan sonra bağlantı test edilir; bozulduysa otomatik geri alınır |
| Klasör taşınınca hizmet bozuluyor | `C:\Program Files\GoodbyeDPI-TR` altına sabit kurulur |
| Dosyaları silmek yetmiyor, WinDivert sürücüsü geride kalıyor | `kaldir` hizmeti, sürücüyü ve dosyaları siler |
| Kaspersky/Avast çakışmaları elle bulunuyor | `doktor` komutu çakışan yazılımları, VPN'leri ve diğer DPI araçlarını listeler |
| ZIP içinde ikili dosyalar dağıtılıyor | Resmi ValdikSS sürümü indirilir ve SHA256 ile doğrulanır |

## Kullanım

1. Depoyu indirin ve bir klasöre çıkarın.
2. `GoodbyeDPI-TR.cmd` dosyasına çift tıklayın (yönetici izni ister).
3. Menüden **1) Çalışan ayarı bul ve kur** seçeneğini seçin.

Komut satırından (yönetici PowerShell):

```powershell
.\gdpi-tr.ps1 bul                   # çalışan profili ve DNS'i bul
.\gdpi-tr.ps1 kur                   # hizmet olarak kur (ayar yoksa önce bulur)
.\gdpi-tr.ps1 durum                 # hizmet, profil ve erişim durumu
.\gdpi-tr.ps1 doktor                # sorun tarama
.\gdpi-tr.ps1 kaldir                # tamamen kaldır
.\gdpi-tr.ps1 kaldir -Eski          # eski GoodbyeDPI-Turkey hizmetini de kaldır
.\gdpi-tr.ps1 bul -Hedef ornek.com  # farklı bir siteye göre ayar bul
.\gdpi-tr.ps1 bul -Genel            # hileleri tüm trafiğe uygula (önerilmez)
```

Liste dışında bir site eklemek için `listeler/kullanici.txt` dosyasına satır başına bir alan adı yazın, sonra yeniden kurun.

## Nasıl çalışır

1. **DNS:** Türk İSS'leri engelli alan adları için `195.175.254.2` adresini döndürüyor ve 53. porttaki başka DNS sunucularına giden sorguları engelliyor. Araç, standart dışı portta dinleyen sunucuları test eder (Quad9 `9953`, OpenDNS `443`, Yandex `1253`). Gerçek adres dönen ilk sunucuyu seçer ve GoodbyeDPI'ın `--dns-addr` özelliğiyle DNS sorgularını oraya yönlendirir.
2. **DPI:** DNS'ten bağımsız ölçüm yapmak için hedefleri DoH ile çözer ve HTTPS bağlantısını dener. Bağlantı sıfırlanıyorsa profilleri sırayla dener: önce parçalama ve yanlış checksum/seq kullanan güvenli olanlar, en son siteleri bozabilen `--set-ttl` profilleri. Hem hedefleri hem de kontrol sitesini açan ilk profil seçilir.
3. **Hizmet:** Seçilen profil, `--blacklist` ve DNS yönlendirmesiyle birlikte `GoodbyeDPI-TR` adlı otomatik başlayan bir Windows hizmeti olarak kurulur. Çöktüğünde yeniden başlatılır.

2026-10-21 tarihinde Türk Telekom hattında test edildi: `discord.com` ve `www.roblox.com` engelliydi. Çalışan profil `modern-5` (`-5`), çalışan DNS Quad9 `9.9.9.10:9953` oldu.

## Sınırlar

- Discord sesli kanalları UDP kullanır; GoodbyeDPI UDP trafiğine hile uygulamaz. Ses çalışmazsa [SplitWire-Turkey](https://github.com/cagritaskn/SplitWire-Turkey) veya bir VPN gerekir.
- `-q` içeren profiller QUIC'i (HTTP/3) tüm sistemde engeller. Tarayıcılar TCP'ye geçer, bu bir sorun çıkarmaz.
- ARM64 Windows desteklenmez; WinDivert'in ARM64 sürücüsü yok.
- Windows 10 1803 veya daha yenisi gerekir (dahili `curl.exe`).

## Geliştirme

```powershell
Invoke-Pester .\tests
```

## Lisans

Bu depodaki betikler MIT lisanslıdır. GoodbyeDPI Apache-2.0, WinDivert LGPL-3.0/GPL-2.0 lisanslıdır; ikisi de kurulum sırasında resmi kaynaktan indirilir.
