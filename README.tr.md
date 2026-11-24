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
| Kurulumdan sonra DNS sunucusu düşerse ya da ağ değişirse internet tamamen gidiyor | Bekçi görevi açılışta, 15 dakikada bir ve ağ değişiminde denetler: DNS'i değiştirir, profili yeniden bulur ya da hizmeti durdurur |
| Engel listesi elle güncelleniyor | Liste günde bir kez bu depodan güncellenir (her satır doğrulanır) |
| Klasör taşınınca hizmet bozuluyor | `C:\Program Files\GoodbyeDPI-TR` altına sabit kurulur |
| Dosyaları silmek hizmeti kaldırmaz | `kaldir` hizmeti ve kendi kurulum kayıtlarını temizler. Paylaşılan WinDivert kaydı varsa kurulu `bin` klasörünü korur. |
| Kaspersky/Avast çakışmaları elle bulunuyor | `doktor` komutu çakışan yazılımları, VPN'leri ve diğer DPI araçlarını listeler |
| ZIP içinde ikili dosyalar dağıtılıyor | Resmi ValdikSS sürümü indirilir; zip ve içindeki her dosya SHA256 ile doğrulanır |
| Kaldırmak için indirilen klasörü saklamak gerekiyor | Başlat menüsü kısayolu ve Programlar ve Özellikler kaydı eklenir |

## Kullanım

1. [Releases](https://github.com/Bluetwinklez/goodbyedpi-tr/releases) sayfasından son ZIP'i indirip bir klasöre çıkarın.
2. `GoodbyeDPI-TR.cmd` dosyasına çift tıklayın (yönetici izni ister).
3. Menüden **1) Çalışan ayarı bul ve kur** seçeneğini seçin.

Komut satırından (yönetici PowerShell):

```powershell
.\gdpi-tr.ps1 bul                   # çalışan profili ve DNS'i bul
.\gdpi-tr.ps1 kur                   # hizmet olarak kur (ayar yoksa önce bulur)
.\gdpi-tr.ps1 durum                 # hizmet, bekçi, profil ve erişim durumu
.\gdpi-tr.ps1 durum -Json           # yönetici izni ve ağ testi olmadan yapılandırılmış durum
.\gdpi-tr.ps1 hiz -Tekrar 5         # bağlantı aşamalarının sürelerini ölç (yönetici gerekmez, hiçbir şeyi değiştirmez)
.\gdpi-tr.ps1 hiz -Kaydet           # ölçümü kaydet ve önceki kayıtla karşılaştır
.\gdpi-tr.ps1 hiz -Gecmis           # kayıtlı ölçümleri listele
.\gdpi-tr.ps1 hiz -DnsSirala        # DNS sunucu adaylarını gecikmeye göre sırala (hiçbir şeyi değiştirmez)
.\gdpi-tr.ps1 hiz -Oneriler         # hızı sınırlayabilecek sistem ayarlarını listele (salt okunur)
.\gdpi-tr.ps1 hiz -AB               # hizmet kapalı ve açıkken aynı hedefleri ölçüp farkı göster (yönetici gerekir)
.\gdpi-tr.ps1 hiz -Indirme          # isteğe bağlı gerçek indirme testi (en çok 5 MB/deneme; isteğe bağlı -IndirmeUrl)
.\gdpi-tr.ps1 duraklat              # yeniden başlatma sonrasında da duraklat
.\gdpi-tr.ps1 devam                 # hizmeti yeniden etkinleştir
.\gdpi-tr.ps1 liste-guncelle        # engelli alan adı listesini güncelle
.\gdpi-tr.ps1 doktor                # sorun tarama
.\gdpi-tr.ps1 rapor                 # gizlilik korumalı yerel JSON raporu
.\gdpi-tr.ps1 kaldir                # tamamen kaldır
.\gdpi-tr.ps1 kaldir -Eski          # eski GoodbyeDPI-Turkey hizmetini de kaldır
.\gdpi-tr.ps1 bul -Hedef ornek.com  # farklı bir siteye göre ayar bul
.\gdpi-tr.ps1 bul -Genel            # hileleri tüm trafiğe uygula (önerilmez)
```

Kurulumdan sonra indirdiğiniz klasörü silebilirsiniz; araç `C:\Program Files\GoodbyeDPI-TR` altında kalır ve Başlat menüsünden açılır.

`hiz` bir hat hızı testi değildir ve bant genişliğinizi artırmaz. Her hedef için (varsayılan liste ve iki kontrol sitesi) `-Tekrar` kez HTTPS isteği atar; DNS, TCP, TLS, sunucu bekleme ve ilk bayt sürelerinin ortanca ve p90 değerlerini gösterir. Verim değeri yalnızca örnek yeterince büyükse görünür. 0 ms DNS süresi çoğunlukla sistem çözümleyicisinin önbellekten yanıt verdiği anlamına gelir. Çözümleyici bağlantı başladıktan sonra yanıt verirse TCP süresi boş kalabilir; diğer süreler geçerlidir. Komut bu sitelere doğrudan bağlanır ve `-Kaydet` vermedikçe hiçbir şey kaydetmez. `-Kaydet` ile sayısal bir özet (ortanca, p90, başarı sayıları, hizmet durumu ve profil adı; IP veya yol yok) `%LOCALAPPDATA%\GoodbyeDPI-TR\olcumler.json` dosyasına eklenir, son 50 ölçüm tutulur ve ilk bayt süresi önceki kayıtla karşılaştırılır. Yalnızca en az 30 ms ve %20 değişim "daha hızlı" veya "daha yavaş" diye anılır; daha küçük farklar olası ölçüm gürültüsü olarak belirtilir. Bu dosya kullanıcıya özeldir ve bekçi tarafından okunmaz. `durum -Json` son kayıtlı ölçümü `SonOlcum` alanında verir.

Profil araması DNS sunucusu seçerken artık her adayı doğrudan UDP ile ölçer (işletim sistemi önbelleği araya girmez), her hedefin ilk sorgusunun yanıtlanmasını, sorguların en az yarısının yanıtlanmasını ve hiçbirinin engelli adres döndürmemesini ister ve çalışan ilk sunucu yerine ortanca gecikmesi en düşük olanı seçer. Daha önce kaydedilmiş sunucu, en iyiden %20 ve 15 ms'den fazla yavaş değilse korunur; küçük farklar yüzünden sunucu değişmez. `hiz -DnsSirala` aynı sıralamayı hiçbir şeyi değiştirmeden gösterir.

Bekçi DNS sunucusunu yalnızca üç denemede de yanıt alamazsa değiştirir (tek bir kayıp UDP paketi arıza sayılmaz). Düzenli profil araması mevcut profil ve DNS ile aynı sonucu verirse hizmeti yeniden başlatmaz, çalışır halde bırakır.

`hiz -Oneriler`, hiçbir şeyi değiştirmeden ve yönetici izni istemeden, gerçek hızı sık sınırlayan ve bu aracın dışında kalan birkaç şeyi okur: 100 Mbps'e veya yarım dupleksa düşmüş Ethernet bağlantısı, düşük Wi-Fi bağlantı hızı, birden fazla açık bağdaştırıcı, açık VPN/tünel bağdaştırıcısı, Güç tasarrufu planı ve sistem proxy'si. Yalnızca olası nedenleri yazar; hiçbir şey bulunmaması bağlantının sağlıklı olduğu anlamına gelmez ve hiçbir ayar değiştirilmez.

DPI engeli aşılması gerektiğinde profil araması artık çalışan ilk profilde durmaz. İlk çalışan profilden sonra en fazla iki profil daha dener (riskli `--set-ttl` profillerini hiç denemez) ve her birinde bağlantı kurulumundan ilk bayta kadar geçen süreyi (DNS hariç) ölçer. Başka bir profil en az 30 ms ve %20 daha hızlı değilse en güvenli çalışan profil korunur; kayıtlı profil de o kadar yavaş değilse korunur. Bir profilin hızı güvenilir ölçülemezse en güvenli çalışan profil kullanılır. Profil araması yönetici izni ve WinDivert sürücüsü gerektirdiğinden bu bölüm mock'lu otomatik testlerle doğrulandı; gerçek bir Windows makinesinde ayrıca denenmesi gerekir.

Menüde **8** hizmeti duraklatır, **9** tekrar çalıştırır. Windows yeniden başlasa da duraklatma korunur ve bekçi denetimleri atlar.

JSON ayarları kaydedilirken önceki geçerli nesne aynı klasörde `.bak` dosyasında saklanır. Ana dosya bozulursa yedek okunur ve uyarı gösterilir. Bir profili uygulamadan önce kurtarılan ayarları kontrol edin. Yedekleri asıl dosyayla aynı erişim izinleriyle koruyun.

İlk kurulumdan önce özel alan adlarını, satır başına bir tane gelecek şekilde paketteki `listeler/kullanici.txt` dosyasına ekleyin. Uygulama zaten kuruluysa kurulum klasöründeki aynı dosyayı yönetici olarak düzenleyin, sonra yeniden kurun. Yeniden kurulum, kurulu kullanıcı listesini korur.

Eski bir GoodbyeDPI hizmeti kuruluysa GoodbyeDPI-TR'yi kurmadan önce eski hizmeti kendi kaldırma aracıyla kaldırın. Ayrı bir GoodbyeDPI işlemi çalışıyorsa profil aramasından önce o işlemi kapatın.

Kaldırma, paylaşılan WinDivert sürücüsünü ve eski sürümün ProgramData veri klasörünü korur. Windows hizmetin silinmesini bekletirse Hizmetler penceresini kapatın, gerekirse Windows'u yeniden başlatın ve kaldırmayı tekrar çalıştırın.

## Nasıl çalışır

1. **DNS:** Türk İSS'leri engelli alan adları için `195.175.254.2` adresini döndürüyor ve 53. porttaki başka DNS sunucularına giden sorguları engelliyor. Araç, standart dışı portta dinleyen sunucuları test eder (Quad9 `9953`, OpenDNS `443`, Yandex `1253`). Gerçek adres dönen ilk sunucuyu seçer ve GoodbyeDPI'ın `--dns-addr` özelliğiyle DNS sorgularını oraya yönlendirir.
2. **DPI:** DNS'ten bağımsız ölçüm yapmak için hedefleri DoH ile çözer ve HTTPS bağlantısını dener. Bağlantı sıfırlanıyorsa profilleri sırayla dener: önce parçalama ve yanlış checksum/seq kullanan güvenli olanlar, en son siteleri bozabilen `--set-ttl` profilleri. Hem hedefleri hem de kontrol sitesini açan ilk profil seçilir.
   Bilinen İSS'lerde (ASN `ipinfo.io` üzerinden öğrenilir) o hatta çalıştığı doğrulanan profil önce denenir.
3. **Hizmet:** Seçilen profil, `--blacklist` ve DNS yönlendirmesiyle birlikte `GoodbyeDPI-TR` adlı otomatik başlayan bir Windows hizmeti olarak kurulur. Çöktüğünde yeniden başlatılır. IPv6 DNS yalnızca makinede genel IPv6 adresi varsa ve sunucu IPv6'dan yanıt veriyorsa yönlendirilir.
4. **Bekçi:** `GoodbyeDPI-TR Bekci` zamanlanmış görevi SYSTEM olarak çalışır ve `C:\Program Files\GoodbyeDPI-TR\veri\bekci.log` dosyasına yazar.
   - DNS sunucusu yanıt vermiyorsa başka bir sunucuya geçer. Hiçbiri yanıt vermiyorsa hizmeti durdurur; internet kesilmez.
   - Hizmet genel interneti bozuyorsa hizmeti durdurur ve profili yeniden arar.
   - Hedefler üst üste iki denetimde açılmazsa profili yeniden arar (en fazla 6 saatte bir).
   - Listeyi günde bir kez günceller.

2026-10-21 tarihinde Türk Telekom hattında test edildi: `discord.com` ve `www.roblox.com` engelliydi. Çalışan profil `modern-5` (`-5`), çalışan DNS Quad9 `9.9.9.10:9953` oldu. Bekçinin DNS değiştirme ve profil yeniden bulma yolları bozuk ayarla denenerek doğrulandı.

Ayarlar ve günlük `C:\Program Files\GoodbyeDPI-TR\veri` altında tutulur. Bu klasöre yalnızca yöneticiler yazabilir; böylece normal bir kullanıcı SYSTEM olarak çalışan hizmetin dosyalarını veya ayarlarını değiştiremez.

## Sınırlar

- Discord sesli kanalları UDP kullanır; GoodbyeDPI UDP trafiğine hile uygulamaz. Ses çalışmazsa [SplitWire-Turkey](https://github.com/cagritaskn/SplitWire-Turkey) veya bir VPN gerekir.
- `-q` içeren profiller QUIC'i (HTTP/3) tüm sistemde engeller. Tarayıcılar TCP'ye geçer, bu bir sorun çıkarmaz.
- ARM64 Windows desteklenmez; WinDivert'in ARM64 sürücüsü yok.
- Windows 10 1803 veya daha yenisi gerekir (dahili `curl.exe`).

## Geliştirme

```powershell
Invoke-Pester .\tests
```

GitHub Actions her gönderimde Pester ve PSScriptAnalyzer çalıştırır. `v*` etiketi gönderildiğinde CRLF satır sonlu sürüm ZIP'ini Releases'a yükler.

## Lisans

Bu depodaki betikler MIT lisanslıdır. GoodbyeDPI Apache-2.0, WinDivert LGPL-3.0/GPL-2.0 lisanslıdır; ikisi de kurulum sırasında resmi kaynaktan indirilir.

## Diğer GoodbyeDPI kurulumlarıyla çakışma

`bul` ve `kur`, başka `goodbyedpi.exe` süreçlerini veya eski `GoodbyeDPI` hizmetini **izinsiz durdurmaz ya da kaldırmaz**. Çakışma varsa açıklayıcı bir uyarı verir; önce ilgili uygulamayı kendiniz kapatın. Eski hizmeti bilinçli olarak kaldırmak için `kaldir -Eski` kullanılabilir. Bu seçenek bile farklı uygulamaların bağımsız süreçlerine dokunmaz.

`kaldir`, bu uygulamanın hizmetini ve kurulum dosyalarını siler; sistemde ortak kullanılan `WinDivert` sürücülerini otomatik kaldırmaz. Ağ sürücülerinin elle kaldırılması yalnızca hangi programın kullandığından emin olunduğunda yapılmalıdır.

## Gizlilik korumalı teşhis raporu

Menüden **10) Gizlilik korumalı teşhis raporu oluştur** seçeneğini veya PowerShell'den `./gdpi-tr.ps1 rapor` komutunu kullanın. Komut satırında yönetici izni gerekmez. Kullanıcının geçici klasöründe `GoodbyeDPI-TR-rapor-*.json` dosyası oluşur.

Rapor sürüm, servis/bekçi durumu, profil adı, DNS sağlayıcı adı ve etkin alan adı sayısını içerir. **IP adresi, kullanıcı adı, tam dosya yolu, hedef alan adı, ham günlük veya hesap bilgisi içermez.** Herhangi bir sunucuya bilgi göndermez, bağlantı testi yapmaz ve servisleri değiştirmez. Paylaşmadan önce içeriği yine de inceleyin.

## Hata durumunda geri alınabilen liste güncellemesi

`liste-guncelle` önce indirilen alan adlarını doğrular, geçici dosyada yeni birleşik listeyi oluşturur ve etkin listelerin yedeğini alır. Hizmet yeni listeyle yeniden başlatılamazsa hem Türkiye listesini hem etkin listeyi eski haline getirip hizmeti eski ayarlarla yeniden başlatmayı dener. Kullanıcının eklediği alan adları korunur. Bekçi başarısız güncellemeyi başarılı saymaz; 1 saat arayla yeniden dener. Gerçek servis/sürücü davranışı yeni sürüm yayınlanmadan önce Windows ortamında kontrol edilmelidir.

## Yayın ZIP dosyasının doğrulanması

Yeni sürümler Türkçe kullanım kılavuzunu (`README.tr.md`), güvenlik politikasını ve bir SHA-256 doğrulama dosyasını (`.zip.sha256`) içerir. ZIP dosyasını indirdikten sonra PowerShell'de `Get-FileHash -Algorithm SHA256 .\GoodbyeDPI-TR-vX.Y.Z.zip` çalıştırıp sonucu aynı sürümdeki `.zip.sha256` dosyasındaki değerle karşılaştırın.

Bu yöntem indirdiğiniz dosyanın beklenen sürüm dosyasıyla aynı olduğunu doğrular; projenin kaynağına veya dağıtım hesabına duyulan güvenin yerini tutmaz.
