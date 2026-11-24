<#
  GoodbyeDPI-TR — Türkiye için GoodbyeDPI kurulum ve yönetim aracı.

  Orijinal GoodbyeDPI-Turkey fork'unun sorunlarını giderir:
    - Hileler tüm trafiğe değil, yalnızca listedeki alan adlarına uygulanır
      (oyunlar, bankalar, devlet siteleri bozulmaz).
    - İSS'ine göre çalışan profili ve DNS sunucusunu kendisi bulur.
    - Kurulumdan sonra interneti test eder; bozulursa geri alır.
    - Bekçi görevi DNS'i ve bağlantıyı düzenli denetler, bozulunca onarır.
    - Sabit bir klasöre kurulur, tam olarak kaldırılır.
    - GoodbyeDPI ikili dosyalarını resmi kaynaktan indirip SHA256 ile doğrular.

  Kullanım (yönetici PowerShell):
    .\gdpi-tr.ps1                 menü
    .\gdpi-tr.ps1 bul             çalışan profili ve DNS'i bul
    .\gdpi-tr.ps1 kur             bulunan ayarla hizmet olarak kur
    .\gdpi-tr.ps1 kaldir [-Eski]  tamamen kaldır (-Eski: eski GoodbyeDPI hizmetini de)
    .\gdpi-tr.ps1 durum           hizmet, bekçi ve erişim durumu
    .\gdpi-tr.ps1 duraklat        hizmeti durdur; yeniden açılışta başlatma
    .\gdpi-tr.ps1 devam           duraklatılan hizmeti tekrar etkinleştir
    .\gdpi-tr.ps1 doktor          çakışan yazılım ve sorun taraması
    .\gdpi-tr.ps1 rapor           özel bilgileri içermeyen yerel teşhis JSON'u üret
    .\gdpi-tr.ps1 test            hedef siteleri test et
    .\gdpi-tr.ps1 hiz [-Tekrar N] bağlantı aşamalarının sürelerini ölç (yönetici gerekmez)
    .\gdpi-tr.ps1 hiz -Kaydet     ölçümü kullanıcı klasörüne kaydet ve öncekiyle karşılaştır
    .\gdpi-tr.ps1 hiz -Gecmis     kayıtlı ölçümleri listele
    .\gdpi-tr.ps1 hiz -DnsSirala  DNS sunucu adaylarını gecikmeye göre sırala (hiçbir şeyi değiştirmez)
    .\gdpi-tr.ps1 hiz -Oneriler   hızı sınırlayabilecek sistem ayarlarını listele (salt okunur)
    .\gdpi-tr.ps1 hiz -AB         hizmet kapalı ve açıkken aynı hedefleri ölçüp farkı göster (yönetici gerekir)
    .\gdpi-tr.ps1 hiz -Indirme    isteğe bağlı gerçek indirme verimi testi (örnek başına en çok 5 MB, diske yazmaz)
    .\gdpi-tr.ps1 liste-guncelle  engelli alan adı listesini GitHub'dan güncelle
    .\gdpi-tr.ps1 bekci           bekçi görevinin çalıştırdığı denetim (elle gerekmez)
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('menu', 'bul', 'kur', 'kaldir', 'durum', 'duraklat', 'devam', 'doktor', 'test', 'liste-guncelle', 'bekci', 'rapor', 'hiz')]
    [string]$Komut = 'menu',
    [switch]$Eski,
    [switch]$Genel,
    [string[]]$Hedef,
    [switch]$Json,
    [ValidateRange(1, 20)]
    [int]$Tekrar = 5,
    [switch]$Kaydet,
    [switch]$Gecmis,
    [switch]$DnsSirala,
    [switch]$Oneriler,
    [switch]$AB,
    [switch]$Indirme,
    [string[]]$IndirmeUrl
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # PS 5.1'de ilerleme çubuğu indirmeyi çok yavaşlatıyor

# --- Sabitler -------------------------------------------------------------

$Script:Surum = '1.1.1'
$Script:HizmetAdi = 'GoodbyeDPI-TR'
$Script:GorevAdi = 'GoodbyeDPI-TR Bekci'
$Script:SistemDizini = [Environment]::SystemDirectory
$Script:ScExe = Join-Path $Script:SistemDizini 'sc.exe'
$Script:KurulumDizini = Join-Path $env:ProgramFiles 'GoodbyeDPI-TR'
# Veriler Program Files altında: yalnızca yöneticiler yazabilir. ProgramData'da normal
# kullanıcılar klasör oluşturabildiği için oradaki dosyalara güvenilemez.
$Script:VeriDizini = Join-Path $Script:KurulumDizini 'veri'
$Script:EskiVeriDizini = Join-Path $env:ProgramData 'GoodbyeDPI-TR'   # 1.0.0
$Script:AyarDosyasi = Join-Path $Script:VeriDizini 'ayarlar.json'
$Script:BekciDosyasi = Join-Path $Script:VeriDizini 'bekci.json'
$Script:GunlukDosyasi = Join-Path $Script:VeriDizini 'bekci.log'
$Script:KaynakDizini = $PSScriptRoot
$Script:KaldirmaAnahtari = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GoodbyeDPI-TR'
$Script:Kisayol = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\GoodbyeDPI-TR.lnk'
$Script:ListeUrl = 'https://raw.githubusercontent.com/Bluetwinklez/goodbyedpi-tr/main/listeler/turkiye.txt'
$Script:ProjeUrl = 'https://github.com/Bluetwinklez/goodbyedpi-tr'

# Resmi ValdikSS/GoodbyeDPI sürümü. Zip ve içindeki her dosyanın hash'i elle doğrulandı.
$Script:Paket = @{
    Url    = 'https://github.com/ValdikSS/GoodbyeDPI/releases/download/0.2.3rc3/goodbyedpi-0.2.3rc3-2.zip'
    Sha256 = '37F96B32D050DADCC930A639EBA68E1CCD57ED5C04A5F77DFCA908F01905A4C5'
    Klasor = 'goodbyedpi-0.2.3rc3-2'
    Dosyalar = @{
        'x86_64' = @{
            'goodbyedpi.exe'  = '8D412B094BB9C137FF25BA9A794D1122ECC84BB776DEBFF6C249723A13CC31CD'
            'WinDivert.dll'   = '6110BFA44667405179C3E15E12AF1B62037E447ED59B054B19042032995E6C7E'
            'WinDivert64.sys' = 'E69B5BA3F0CD6CFB2983E442636E7F0B342B61B15264B0328317D4559C82CF50'
        }
        'x86' = @{
            'goodbyedpi.exe'  = '66E202C9FCE9E769E2BC791B7FD6F56F21EAB59F607F4ED0724E0C68C430DD1F'
            'WinDivert.dll'   = '625FFDD95BFABFF32D0E8A95BEABCD303C01C8BBA73B90402D4E84D6E15DD8E5'
            'WinDivert32.sys' = '29CA5CEB59C9C6993A349E82B1FD46078E6F8A302764153AB84FA22E382FCDCA'
            'WinDivert64.sys' = 'E69B5BA3F0CD6CFB2983E442636E7F0B342B61B15264B0328317D4559C82CF50'
        }
    }
}

# Engelli olduğu bilinen test hedefleri ve engelsiz kontrol siteleri.
$Script:VarsayilanHedefler = @('discord.com', 'www.roblox.com')
$Script:KontrolSiteleri = @('www.google.com', 'www.turkiye.gov.tr')
# curl -w biçimi: kod|DNS|TCP|TLS|ilk bayt|toplam|indirme hızı|bayt (süreler başlangıçtan itibaren, saniye).
$Script:HizBicimi = '%{http_code}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}|%{speed_download}|%{size_download}'
# Verim yalnızca yeterince büyük örnekte anlamlıdır; küçük sayfalarda bağlantı kurulumu baskın olur.
$Script:HizVerimMinBayt = 65536
# İsteğe bağlı gerçek indirme testi (yalnızca -Indirme verildiğinde kullanılır; diske yazmaz, NUL'a akar).
$Script:IndirmeHedefleri = @('https://speed.cloudflare.com/__down?bytes=5242880')
$Script:IndirmeEnFazlaBayt = 5242880
$Script:IndirmeSureSn = 20
# Ölçüm geçmişi kullanıcıya özeldir (hiz yönetici gerektirmez). Bekçi bu dosyayı okumaz: SYSTEM hesabı
# kullanıcı tarafından yazılabilen veriye güvenmemeli.
$Script:OlcumDosyasi = $null
if ($env:LOCALAPPDATA) { $Script:OlcumDosyasi = Join-Path $env:LOCALAPPDATA 'GoodbyeDPI-TR\olcumler.json' }
$Script:OlcumSemaSurumu = 1
$Script:OlcumEnFazlaKayit = 50
# Karşılaştırmada değişim hem bu kadar ms hem bu kadar yüzde aşılmadıkça "belirgin" sayılmaz.
$Script:OlcumBelirginMs = 30
$Script:OlcumBelirginYuzde = 20

# Güvenliden riskliye sıralı. --set-ttl içerenler siteleri bozabildiği için sonda.
$Script:Profiller = @(
    @{ Ad = 'modern-9';        Arg = '-9' }
    @{ Ad = 'modern-7';        Arg = '-7' }
    @{ Ad = 'modern-6';        Arg = '-6' }
    @{ Ad = 'modern-8';        Arg = '-8' }
    @{ Ad = 'modern-5';        Arg = '-5' }
    @{ Ad = 'sni-bolme';       Arg = '-e 2 --frag-by-sni --reverse-frag --wrong-chksum --max-payload -q' }
    @{ Ad = 'ttl-3';           Arg = '--set-ttl 3' }
    @{ Ad = 'superonline-3';   Arg = '-3 --set-ttl 4' }
    @{ Ad = 'fork-varsayilan'; Arg = '-5 --set-ttl 5' }
)

# İSS'e göre önce denenecek profil (ASN numarası). Yalnızca kanıtı olanlar.
$Script:IssProfilleri = @{
    '9121'  = 'modern-5'        # Türk Telekom: 2026-10-21'de bu araçla doğrulandı
    '34984' = 'superonline-3'   # Superonline: GoodbyeDPI-Turkey #142'de kullanıcı bildirimi
}

# Standart dışı portta dinleyen genel DNS sunucuları (İSS'ler 53'ü yakalıyor).
$Script:DnsAdaylari = @(
    # Türk Telekom hattında 2026-10 itibarıyla doğrulandı; AdGuard 5353 ve OpenDNS 5353 yanıt vermiyor.
    @{ Ad = 'Quad9 (filtresiz)'; V4 = '9.9.9.10';       V6 = '2620:fe::10';        Port = 9953 }
    @{ Ad = 'OpenDNS';           V4 = '208.67.222.222'; V6 = '2620:119:35::35';    Port = 443 }
    @{ Ad = 'Yandex';            V4 = '77.88.8.8';      V6 = '2a02:6b8::feed:0ff'; Port = 1253 }
)
# Mevcut DNS sunucusu, en hızlının ortancasının bu çarpan + ms sınırı içindeyse değiştirilmez.
$Script:DnsHisterezisCarpan = 1.2
$Script:DnsHisterezisMs = 15

# DPI ölçümünde DNS engelini devre dışı bırakmak için DoH sunucuları (IP ile, sertifikada IP var).
$Script:DohAdaylari = @('https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query', 'https://94.140.14.140/dns-query')
$Script:Doh = $null

# Türkiye'deki erişim engeli sayfasının adres bloğu.
$Script:EngelBloklari = @('195.175.254.')

# Bekçinin kendiliğinden yeniden profil araması için bekleme süresi.
$Script:YenidenBulAraligi = New-TimeSpan -Hours 6

# --- Yardımcılar ----------------------------------------------------------

$Script:Sessiz = $false   # bekçi modunda ekrana yazmaz, günlüğe yazar

function Yaz([string]$Metin, [string]$Renk = 'Gray') {
    if ($Script:Sessiz) { Write-Gunluk $Metin.Trim() } else { Write-Host $Metin -ForegroundColor $Renk }
}
function Basari([string]$Metin) { Yaz "  [+] $Metin" 'Green' }
function Uyari([string]$Metin) { Yaz "  [!] $Metin" 'Yellow' }
function Hata([string]$Metin) { Yaz "  [x] $Metin" 'Red' }
function Baslik([string]$Metin) { Yaz ''; Yaz "== $Metin ==" 'Cyan' }

function Write-Gunluk([string]$Metin) {
    if (-not $Metin) { return }
    try {
        if (-not (Test-Path $Script:VeriDizini)) { return }
        $satir = '{0} {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Metin
        Add-Content -Path $Script:GunlukDosyasi -Value $satir -Encoding UTF8
        # Günlük 1 MB'ı geçerse son 500 satırı tut.
        if ((Get-Item $Script:GunlukDosyasi).Length -gt 1MB) {
            $son = Get-Content $Script:GunlukDosyasi -Tail 500 -Encoding UTF8
            Set-Content $Script:GunlukDosyasi $son -Encoding UTF8
        }
    } catch { }
}

function Test-Yonetici {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Mimari {
    $m = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $m = $env:PROCESSOR_ARCHITEW6432 }
    switch ($m) {
        'AMD64' { return 'x86_64' }
        'x86'   { return 'x86' }
        default { return $null }   # ARM64: WinDivert'in ARM sürücüsü yok
    }
}

function Get-Curl {
    # Git'in değil Windows'un curl'ü: Schannel kullanır, sistem sertifikalarına güvenir.
    $yol = Join-Path $Script:SistemDizini 'curl.exe'
    if (Test-Path $yol) { return $yol }
    return $null
}

function ConvertFrom-JsonNesnesi([string]$Metin) {
    $nesne = ConvertFrom-Json -InputObject $Metin -ErrorAction Stop
    if ($null -eq $nesne -or $nesne.GetType() -ne [System.Management.Automation.PSCustomObject]) {
        throw 'JSON dosyası bir ayar nesnesi içermeli.'
    }
    return $nesne
}

function Read-Json([string]$Yol, [System.Collections.Generic.List[string]]$Uyarilar) {
    if (-not [IO.File]::Exists($Yol) -and -not [IO.File]::Exists("$Yol.bak")) { return $null }
    if ([IO.File]::Exists($Yol)) {
        $metin = [IO.File]::ReadAllText($Yol, [Text.Encoding]::UTF8)
        try {
            return ConvertFrom-JsonNesnesi $metin
        } catch {
            if (-not [IO.File]::Exists("$Yol.bak")) { throw "Ayar dosyası geçersiz: $Yol" }
        }
    }
    $yedekMetin = [IO.File]::ReadAllText("$Yol.bak", [Text.Encoding]::UTF8)
    try {
        $yedek = ConvertFrom-JsonNesnesi $yedekMetin
    } catch {
        throw "Ayar dosyası ve yedeği kullanılamıyor: $Yol"
    }
    $mesaj = "Son geçerli ayar yedeği kullanılıyor: $Yol.bak"
    if ($null -ne $Uyarilar) { $Uyarilar.Add($mesaj) } else { Uyari $mesaj }
    return $yedek
}

function Save-Json($Nesne, [string]$Yol) {
    # Önce aynı diskte geçici dosyayı tamamla; yarım yazım mevcut ayarı bozmasın.
    $json = $Nesne | ConvertTo-Json -Depth 5
    ConvertFrom-JsonNesnesi $json | Out-Null
    $tamYol = [IO.Path]::GetFullPath($Yol)
    New-Item -ItemType Directory -Force -Path (Split-Path $tamYol) | Out-Null
    $gecici = $tamYol + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($gecici, $json, (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($tamYol)) {
            $gecerli = $false
            $onceki = [IO.File]::ReadAllText($tamYol, [Text.Encoding]::UTF8)
            try {
                ConvertFrom-JsonNesnesi $onceki | Out-Null
                $gecerli = $true
            } catch { }
            if ($gecerli) {
                [IO.File]::Replace($gecici, $tamYol, "$tamYol.bak")
            } else {
                # Bozuk ana dosya son geçerli yedeğin üzerine yazılmasın.
                [IO.File]::Replace($gecici, $tamYol, [NullString]::Value)
            }
        } else {
            [IO.File]::Move($gecici, $tamYol)
        }
    } finally {
        if ([IO.File]::Exists($gecici)) { [IO.File]::Delete($gecici) }
    }
}

function Read-Ayarlar([System.Collections.Generic.List[string]]$Uyarilar) {
    return Read-Json $Script:AyarDosyasi $Uyarilar
}
function Save-Ayarlar($Ayarlar) { Save-Json $Ayarlar $Script:AyarDosyasi }

# --- Liste ----------------------------------------------------------------

function Test-AlanAdi([string]$Alan) {
    return $Alan -match '^(?=.{2,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,63}$'
}

function Read-AlanAdlari([string[]]$Dosyalar) {
    $sonuc = New-Object System.Collections.Generic.List[string]
    foreach ($d in $Dosyalar) {
        if (-not (Test-Path $d)) { continue }
        foreach ($satir in Get-Content $d -Encoding UTF8) {
            $s = ($satir -replace '#.*$', '').Trim().ToLowerInvariant()
            if ($s -and -not $sonuc.Contains($s)) { $sonuc.Add($s) }
        }
    }
    return $sonuc.ToArray()
}

function Get-ListeDosyalari([string]$Kok) {
    $dizin = Join-Path $Kok 'listeler'
    if (-not (Test-Path $dizin)) { return @() }
    return @(Get-ChildItem $dizin -Filter *.txt | Sort-Object Name | ForEach-Object FullName)
}

function Get-KurulumListeKopyalari([string]$Kaynak, [string]$Hedef) {
    foreach ($dosya in Get-ListeDosyalari $Kaynak) {
        $ad = [IO.Path]::GetFileName($dosya)
        $hedefDosya = Join-Path $Hedef $ad
        if ($ad -eq 'kullanici.txt' -and (Test-Path -LiteralPath $hedefDosya)) { continue }
        [pscustomobject]@{ Kaynak = $dosya; Hedef = $hedefDosya }
    }
}

function Write-Liste([string[]]$Kaynaklar, [string[]]$Ekler, [string]$Cikti) {
    # GoodbyeDPI'ın liste okuyucusu yorum satırı ve BOM tanımaz; temiz ASCII dosya üret.
    $alanlar = @(Read-AlanAdlari $Kaynaklar) + @($Ekler | ForEach-Object { $_.ToLowerInvariant() })
    $alanlar = @($alanlar | Where-Object { $_ -and $_.Length -ge 2 } | Select-Object -Unique)
    $gecersiz = @($alanlar | Where-Object { -not (Test-AlanAdi $_) })
    foreach ($g in $gecersiz) { Uyari "Geçersiz alan adı atlandı: $g" }
    $alanlar = @($alanlar | Where-Object { Test-AlanAdi $_ })
    if (-not $alanlar) { throw 'Alan adı listesi boş.' }
    New-Item -ItemType Directory -Force -Path (Split-Path $Cikti) | Out-Null
    [IO.File]::WriteAllLines($Cikti, [string[]]$alanlar, (New-Object Text.ASCIIEncoding))
    return $Cikti
}

# --- Argümanlar -----------------------------------------------------------

function Get-GdpiArgumanlari {
    param(
        [Parameter(Mandatory)][string]$Profil,
        $Dns,
        [string[]]$ListeDosyalari,
        [switch]$Genel
    )
    $parca = New-Object System.Collections.Generic.List[string]
    $parca.Add($Profil)
    # Büyük veri aktarımlarını (indirme, oyun) atla: CPU ve uyumluluk için.
    if ($Profil -notmatch '--max-payload' -and $Profil -notmatch '-[5-9]\b') { $parca.Add('--max-payload') }
    if (-not $Genel) {
        foreach ($l in $ListeDosyalari) { $parca.Add("--blacklist `"$l`"") }
    }
    if ($Dns) {
        $parca.Add("--dns-addr $($Dns.V4) --dns-port $($Dns.Port)")
        # IPv6 yalnızca test edilip çalıştığı doğrulandıysa yönlendirilir.
        if ($Dns.V6 -and $Dns.V6Etkin) { $parca.Add("--dnsv6-addr $($Dns.V6) --dnsv6-port $($Dns.Port)") }
    }
    return ($parca -join ' ')
}

function Get-SiraliProfiller([string]$Asn) {
    # İSS için bilinen profil varsa başa alınır, diğerlerinin sırası korunur.
    $oncelik = $null
    if ($Asn -and $Script:IssProfilleri.ContainsKey($Asn)) { $oncelik = $Script:IssProfilleri[$Asn] }
    if (-not $oncelik) { return $Script:Profiller }
    return @($Script:Profiller | Where-Object { $_.Ad -eq $oncelik }) + @($Script:Profiller | Where-Object { $_.Ad -ne $oncelik })
}

function Get-Iss {
    # İSS'in ASN'sini öğrenir (yalnızca profil sırası için). Ulaşılamazsa $null.
    $curl = Get-Curl
    if (-not $curl) { return $null }
    $org = & $curl --disable -s --connect-timeout 3 -m 5 https://ipinfo.io/org 2>$null
    if ($LASTEXITCODE -eq 0 -and $org -match '^AS(\d+)\s*(.*)$') { return @{ Asn = $Matches[1]; Ad = $Matches[2].Trim() } }
    return $null
}

# --- DNS ------------------------------------------------------------------

function New-DnsSorgusu([string]$Alan, [uint16]$Kimlik = 0x1234) {
    $b = New-Object System.Collections.Generic.List[byte]
    $b.AddRange([byte[]]@((($Kimlik -shr 8) -band 0xFF), ($Kimlik -band 0xFF), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0))
    foreach ($etiket in $Alan.TrimEnd('.').Split('.')) {
        $e = [Text.Encoding]::ASCII.GetBytes($etiket)
        $b.Add([byte]$e.Length); $b.AddRange($e)
    }
    $b.AddRange([byte[]]@(0, 0, 1, 0, 1))   # kök, QTYPE=A, QCLASS=IN
    return , $b.ToArray()
}

function Read-DnsCevabi([byte[]]$Veri, [int]$Kimlik = -1, [byte[]]$Sorgu) {
    # A kayıtlarının IPv4 adreslerini döndürür. Kimlik verilirse eşleşmeyen cevap reddedilir.
    # [int] dönüşümleri şart: PowerShell'de byte -shl 8 sonucu byte olarak taşar.
    if ($Veri.Length -lt 12) { return @() }
    if ($Kimlik -ge 0 -and ((([int]$Veri[0] -shl 8) -bor $Veri[1]) -ne $Kimlik)) { return @() }
    # QR=1, standart sorgu, kesilmemiş paket ve NOERROR.
    if (($Veri[2] -band 0xFA) -ne 0x80 -or ($Veri[3] -band 0x0F) -ne 0) { return @() }
    $soru = ([int]$Veri[4] -shl 8) -bor $Veri[5]
    $cevap = ([int]$Veri[6] -shl 8) -bor $Veri[7]
    if ($soru -ne 1) { return @() }
    if ($Sorgu) {
        if ($Sorgu.Length -lt 17 -or $Veri.Length -lt $Sorgu.Length) { return @() }
        # Gönderdiğimiz soru tek ve sıkıştırmasızdır. DNS adında harf büyüklüğü önemsizdir.
        $uzunluk = $Sorgu.Length - 12
        $beklenen = [Text.Encoding]::ASCII.GetString($Sorgu, 12, $uzunluk)
        $gelen = [Text.Encoding]::ASCII.GetString($Veri, 12, $uzunluk)
        if (-not [string]::Equals($beklenen, $gelen, [StringComparison]::OrdinalIgnoreCase)) { return @() }
    }
    $i = 12
    $atla = {
        param($p)
        while ($p -lt $Veri.Length) {
            $u = $Veri[$p]
            if ($u -eq 0) { return $p + 1 }
            if (($u -band 0xC0) -eq 0xC0) {
                if ($p + 1 -ge $Veri.Length) { return -1 }
                $isaret = (([int]$u -band 0x3F) -shl 8) -bor $Veri[$p + 1]
                if ($isaret -lt 12 -or $isaret -ge $p) { return -1 }
                return $p + 2
            }
            if ($u -gt 63) { return -1 }
            $p += $u + 1
        }
        return -1
    }
    $i = & $atla $i
    if ($i -lt 0 -or $i + 4 -gt $Veri.Length) { return @() }
    $i += 4
    $ipler = @()
    for ($a = 0; $a -lt $cevap; $a++) {
        $i = & $atla $i
        if ($i -lt 0 -or $i + 10 -gt $Veri.Length) { return @() }
        $tip = ([int]$Veri[$i] -shl 8) -bor $Veri[$i + 1]
        $sinif = ([int]$Veri[$i + 2] -shl 8) -bor $Veri[$i + 3]
        $uzunluk = ([int]$Veri[$i + 8] -shl 8) -bor $Veri[$i + 9]
        $i += 10
        if ($i + $uzunluk -gt $Veri.Length) { return @() }
        if ($tip -eq 1 -and $sinif -eq 1 -and $uzunluk -eq 4) {
            $ipler += '{0}.{1}.{2}.{3}' -f $Veri[$i], $Veri[$i + 1], $Veri[$i + 2], $Veri[$i + 3]
        }
        $i += $uzunluk
    }
    return $ipler
}

function Test-EngelAdresi([string[]]$Ipler) {
    foreach ($ip in $Ipler) {
        if ($ip -eq '0.0.0.0' -or $ip.StartsWith('127.')) { return $true }
        foreach ($blok in $Script:EngelBloklari) { if ($ip.StartsWith($blok)) { return $true } }
    }
    return $false
}

function Resolve-UdpDns([string]$Sunucu, [int]$Port, [string]$Alan, [int]$ZamanAsimiMs = 2500) {
    $adres = [System.Net.IPAddress]::Parse($Sunucu)
    $istemci = New-Object System.Net.Sockets.UdpClient($adres.AddressFamily)
    try {
        $istemci.Client.ReceiveTimeout = $ZamanAsimiMs
        $rastgele = [Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $bayt = New-Object byte[] 2
            $rastgele.GetBytes($bayt)
            $kimlik = [BitConverter]::ToUInt16($bayt, 0)
        } finally {
            $rastgele.Dispose()
        }
        $sorgu = New-DnsSorgusu $Alan ([uint16]$kimlik)
        # Bağlı UDP soketi yalnızca seçilen IP ve porttan gelen paketleri kabul eder.
        $istemci.Connect($adres, $Port)
        [void]$istemci.Send($sorgu, $sorgu.Length)
        $uc = New-Object System.Net.IPEndPoint($adres, 0)
        return Read-DnsCevabi ($istemci.Receive([ref]$uc)) $kimlik $sorgu
    } catch {
        return @()
    } finally {
        $istemci.Close()
    }
}

function Test-GenelIPv6 {
    # Makinenin internete çıkan bir IPv6 adresi var mı (tünel bağdaştırıcıları hariç)?
    $adresler = Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object {
        $_.IPAddress -match '^[23]' -and $_.AddressState -eq 'Preferred' -and
        $_.InterfaceAlias -notmatch 'Teredo|isatap|6to4|Tailscale|WireGuard|Loopback'
    }
    return [bool]$adresler
}

function Test-DnsSunucusu($Aday, [string[]]$Alanlar, [int]$Deneme = 1) {
    # Her hedef için en çok $Deneme kez sorulur; yanıtsız kalan sorgu tekrarlanır (tek bir kayıp UDP
    # paketi sunucuyu "ölü" göstermesin). Engelli adres döndüren sunucu ise hemen elenir.
    foreach ($h in $Alanlar) {
        $tamam = $false
        for ($i = 0; $i -lt [Math]::Max(1, $Deneme) -and -not $tamam; $i++) {
            $ipler = Resolve-UdpDns $Aday.V4 $Aday.Port $h
            if ($ipler) {
                if (Test-EngelAdresi $ipler) { return $false }
                $tamam = $true
            }
        }
        if (-not $tamam) { return $false }
    }
    return $true
}

function Test-AyniAyar($Eski, $Yeni) {
    # Profil araması mevcut ayarla aynı sonucu verdiyse hizmeti yeniden başlatmaya gerek yoktur.
    if ($null -eq $Eski -or $null -eq $Yeni) { return $false }
    if ($Eski.profil -cne $Yeni.profil -or $Eski.arg -cne $Yeni.arg) { return $false }
    if ([bool]$Eski.genel -ne [bool]$Yeni.genel) { return $false }
    $d1 = $Eski.dns
    $d2 = $Yeni.dns
    if ($null -eq $d1 -and $null -eq $d2) { return $true }
    if ($null -eq $d1 -or $null -eq $d2) { return $false }
    return ($d1.V4 -eq $d2.V4) -and ([int]$d1.Port -eq [int]$d2.Port) -and ([bool]$d1.V6Etkin -eq [bool]$d2.V6Etkin)
}

function Measure-DnsAdayi($Aday, [string[]]$Alanlar, [int]$Tekrar = 3) {
    # Sunucuya UDP ile doğrudan sorar; işletim sistemi DNS önbelleği araya girmez.
    # Bir hedefin ilk sorgusu yanıtsız kalırsa aday kullanılamaz sayılır ve ölçüm orada biter
    # (ölü sunucu için zaman aşımı beklemeyi çoğaltmamak için).
    $sureler = New-Object 'System.Collections.Generic.List[double]'
    $denenen = 0
    $basarisiz = 0
    $engelli = $false
    $ilkYanitsiz = $false
    :alanlar foreach ($h in $Alanlar) {
        for ($i = 0; $i -lt $Tekrar; $i++) {
            $denenen++
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $ipler = Resolve-UdpDns $Aday.V4 $Aday.Port $h
            $sw.Stop()
            if (-not $ipler) {
                $basarisiz++
                if ($i -eq 0) { $ilkYanitsiz = $true; break alanlar }
                continue
            }
            if (Test-EngelAdresi $ipler) { $engelli = $true; break alanlar }
            $sureler.Add($sw.Elapsed.TotalMilliseconds)
        }
    }
    $ist = $null
    if ($sureler.Count -gt 0) { $ist = Get-Istatistik $sureler.ToArray() }
    # Sorguların en az yarısı yanıtlanmalı; aralıklı paket kaybı olan sunucu tek başına elenmez.
    $kullanilabilir = (-not $engelli) -and (-not $ilkYanitsiz) -and $null -ne $ist -and ($basarisiz * 2 -le $denenen)
    return [pscustomobject]@{
        Aday = $Aday
        Denenen = $denenen
        Basarisiz = $basarisiz
        Engelli = $engelli
        Kullanilabilir = $kullanilabilir
        Ortanca = $(if ($ist) { $ist.Ortanca } else { $null })
        P90 = $(if ($ist) { $ist.P90 } else { $null })
        Sira = 0
    }
}

function Get-DnsSiralamasi([string[]]$Hedefler, [int]$Tekrar = 3) {
    # Kullanılabilir adaylar ortanca gecikmeye göre sıralanır; eşitlikte aday listesindeki sıra korunur.
    $sira = 0
    $olcumler = @(foreach ($a in $Script:DnsAdaylari) {
        $o = Measure-DnsAdayi $a $Hedefler $Tekrar
        $o.Sira = $sira++
        $o
    })
    return [pscustomobject]@{
        Kullanilabilir = @($olcumler | Where-Object { $_.Kullanilabilir } | Sort-Object Ortanca, Sira)
        Kullanilamaz = @($olcumler | Where-Object { -not $_.Kullanilabilir })
    }
}

function Invoke-DnsSiralamasi {
    param([string[]]$Hedefler)
    Baslik 'DNS sunucusu gecikmesi'
    Yaz '  Adaylara UDP ile doğrudan sorulur; sistem DNS önbelleği devrede değildir. Hiçbir ayar değişmez.' 'DarkGray'
    $sira = Get-DnsSiralamasi $Hedefler
    $n = 0
    foreach ($o in $sira.Kullanilabilir) {
        $n++
        $kayip = if ($o.Basarisiz) { " | $($o.Basarisiz)/$($o.Denenen) sorgu yanıtsız" } else { '' }
        $satir = '{0}. {1} ({2}:{3}): ortanca {4:N0} ms, p90 {5:N0} ms{6}' -f $n, $o.Aday.Ad, $o.Aday.V4, $o.Aday.Port, $o.Ortanca, $o.P90, $kayip
        if ($n -eq 1) { Basari $satir } else { Yaz "  $satir" }
    }
    foreach ($o in $sira.Kullanilamaz) {
        $neden = if ($o.Engelli) { 'engelli adres döndürdü' } else { 'yanıt vermedi' }
        Uyari "$($o.Aday.Ad) ($($o.Aday.V4):$($o.Aday.Port)): $neden"
    }
    if (@($sira.Kullanilabilir).Count -eq 0) { Hata 'Kullanılabilir DNS sunucusu bulunamadı.' }
    return $sira
}

function Select-DnsAdayi($Siralama, $Mevcut) {
    # Histerezis: mevcut sunucu hâlâ kullanılabilir ve en iyiden yeterince yavaş değilse değiştirilmez.
    # Böylece küçük ölçüm farkları yüzünden sürekli sunucu değişmez.
    $iyi = @($Siralama.Kullanilabilir)
    if ($iyi.Count -eq 0) { return $null }
    $en = $iyi[0]
    if ($Mevcut) {
        $m = $iyi | Where-Object { $_.Aday.V4 -eq $Mevcut.V4 -and [int]$_.Aday.Port -eq [int]$Mevcut.Port } | Select-Object -First 1
        if ($m -and $m.Ortanca -le ($en.Ortanca * $Script:DnsHisterezisCarpan + $Script:DnsHisterezisMs)) { return $m }
    }
    return $en
}

function Find-DnsSunucusu([string[]]$Hedefler, $Mevcut = $null) {
    $ipv6 = Test-GenelIPv6
    $sira = Get-DnsSiralamasi $Hedefler
    foreach ($k in $sira.Kullanilamaz) {
        $neden = if ($k.Engelli) { 'engelli adres döndürdü' } else { 'kullanılamıyor' }
        Uyari "$($k.Aday.Ad) ($($k.Aday.V4):$($k.Aday.Port)) $neden"
    }
    $secilen = Select-DnsAdayi $sira $Mevcut
    if (-not $secilen) { return $null }
    if (@($sira.Kullanilabilir).Count -gt 1) {
        $ozet = @($sira.Kullanilabilir | ForEach-Object { '{0} {1:N0} ms' -f $_.Aday.Ad, $_.Ortanca }) -join ', '
        Yaz "  DNS gecikmesi (ortanca): $ozet" 'DarkGray'
    }
    $aday = $secilen.Aday
    $sonuc = @{ Ad = $aday.Ad; V4 = $aday.V4; V6 = $aday.V6; Port = $aday.Port; V6Etkin = $false }
    if ($ipv6) {
        $ip6 = Resolve-UdpDns $aday.V6 $aday.Port $Hedefler[0]
        $sonuc.V6Etkin = [bool]($ip6 -and -not (Test-EngelAdresi $ip6))
        if (-not $sonuc.V6Etkin) { Uyari "IPv6 DNS ($($aday.V6)) yanıt vermedi; IPv6 DNS yönlendirilmeyecek." }
    }
    return $sonuc
}

# --- Bağlantı testi -------------------------------------------------------

function Get-HttpsSonucu([string]$Alan, [string]$HttpKodu, [int]$CikisKodu) {
    $http = 0
    if ($HttpKodu -match '^[1-5]\d\d$') { $http = [int]$HttpKodu }
    $erisim = $CikisKodu -eq 0 -and $http -ge 100
    $durum = 'aktarim'
    $aciklama = "Aktarım tamamlanamadı (curl kodu $CikisKodu)."
    switch ($CikisKodu) {
        0 {
            if ($http -ge 500) {
                $durum = 'sunucu'; $aciklama = "HTTPS yanıtı alındı; sunucu hatası var (HTTP $http)."
            } elseif ($http -ge 400) {
                $durum = 'http'; $aciklama = "HTTPS yanıtı alındı; istek reddedildi (HTTP $http)."
            } elseif ($http -ge 100) {
                $durum = 'erisim'; $aciklama = "HTTPS yanıtı alındı (HTTP $http)."
            } else {
                $durum = 'yanit'; $aciklama = 'Geçerli HTTP yanıtı alınamadı.'
            }
        }
        5 { $durum = 'proxy-dns'; $aciklama = 'Proxy sunucusunun adı çözülemedi.' }
        6 { $durum = 'dns'; $aciklama = 'Hedefin DNS adı çözülemedi.' }
        7 { $durum = 'baglanti'; $aciklama = 'Sunucuya bağlantı kurulamadı.' }
        28 { $durum = 'zaman-asimi'; $aciklama = 'İstek zaman aşımına uğradı.' }
        35 { $durum = 'tls'; $aciklama = 'TLS bağlantısı kurulamadı.' }
        60 { $durum = 'sertifika'; $aciklama = 'Sunucu sertifikası doğrulanamadı.' }
    }
    return [pscustomobject]@{
        Alan = $Alan
        Erisim = $erisim
        HttpKodu = $http
        CikisKodu = $CikisKodu
        Durum = $durum
        Aciklama = $aciklama
    }
}

function Get-TestSunucusu([string]$Alan) {
    # Hedef yalnızca alan adı veya IP olabilir; URL, yol ve curl seçenekleri reddedilir.
    $ip = $null
    if ([Net.IPAddress]::TryParse($Alan, [ref]$ip)) {
        if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) { return "[$($ip.ToString())]" }
        return $ip.ToString()
    }
    if (-not (Test-AlanAdi $Alan)) { throw 'Test hedefi geçerli bir alan adı veya IP adresi olmalı.' }
    return $Alan
}

function Invoke-HttpsOlcum([string]$Alan, [string]$DohUrl, [int]$Sure = 8) {
    # Hedefe HTTPS bağlantısı kurulabiliyor mu? DohUrl verilirse DNS engeli devre dışı kalır,
    # yalnızca DPI ölçülür.
    $sunucu = Get-TestSunucusu $Alan
    $curl = Get-Curl
    if (-not $curl) { throw 'Windows curl.exe bulunamadı (Windows 10 1803+ gerekir).' }
    $arg = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--connect-timeout', '5', '-m', "$Sure", "https://$sunucu/")
    if ($DohUrl) { $arg = @('--doh-url', $DohUrl) + $arg }
    # --disable ilk argüman olmalı; kullanıcı curlrc ayarları ölçümü değiştirmesin.
    $arg = @('--disable') + $arg
    $kod = & $curl @arg 2>$null
    return Get-HttpsSonucu $Alan ([string]$kod) $LASTEXITCODE
}

function Test-Https([string]$Alan, [string]$DohUrl, [int]$Sure = 8) {
    return (Invoke-HttpsOlcum $Alan $DohUrl $Sure).Erisim
}

# --- Hız ölçümü -----------------------------------------------------------
# Bu bölüm hat hızını değil, hedefe bağlantı aşamalarının sürelerini ölçer. Hiçbir ayarı değiştirmez.

function ConvertTo-Milisaniye($Saniye) {
    # curl süreleri ondalık noktalı saniyedir; kültürden bağımsız çözülür. Geçersizse $null.
    $deger = 0.0
    if ($Saniye -isnot [string] -or
        -not [double]::TryParse($Saniye, [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$deger) -or
        [double]::IsNaN($deger) -or [double]::IsInfinity($deger) -or $deger -lt 0) { return $null }
    return [Math]::Round($deger * 1000, 1)
}

function Get-HizOlcumuSonucu([string]$Alan, [string]$Cikti, [int]$CikisKodu) {
    $sonuc = [ordered]@{ DnsMs = $null; TcpMs = $null; TlsMs = $null; SunucuMs = $null; IlkBaytMs = $null
        ToplamMs = $null; VerimBps = $null; Bayt = $null }
    $parcalar = @($Cikti.Trim() -split '\|')
    $temel = Get-HttpsSonucu $Alan $parcalar[0] $CikisKodu
    if ($temel.Erisim -and $parcalar.Count -eq 8) {
        $dns = ConvertTo-Milisaniye $parcalar[1]
        $tcp = ConvertTo-Milisaniye $parcalar[2]
        $tls = ConvertTo-Milisaniye $parcalar[3]
        $ilk = ConvertTo-Milisaniye $parcalar[4]
        $top = ConvertTo-Milisaniye $parcalar[5]
        $hiz = 0.0; $bayt = 0.0
        $hizTamam = [double]::TryParse($parcalar[6], [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$hiz) -and $hiz -ge 0
        $baytTamam = [double]::TryParse($parcalar[7], [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$bayt) -and $bayt -ge 0
        # Süreler başlangıçtan itibaren birikimlidir; aşama süresi iki ölçümün farkıdır.
        # IP hedefinde DNS ve TLS yoksa curl 0 verir. Sayı olmayan değerler veya imkânsız sıralar
        # (ilk bayt bağlantıdan önce, toplam ilk bayttan önce) bütün süreleri geçersiz kılar.
        $tlsVar = $null -ne $tls -and $tls -gt 0
        $gecerli = $null -ne $dns -and $null -ne $tcp -and $null -ne $tls -and $null -ne $ilk -and $null -ne $top -and
            $ilk -ge $tcp -and $top -ge $ilk -and $dns -le $ilk -and (-not $tlsVar -or ($tls -ge $tcp -and $tls -le $ilk))
        if ($gecerli) {
            $sonuc.DnsMs = $dns
            # Windows curl'de çözümleyici bağlantı başladıktan sonra yanıt verebilir (connect < namelookup).
            # O zaman TCP aşaması ayrı hesaplanamaz; diğer süreler geçerli kalır.
            if ($tcp -ge $dns) { $sonuc.TcpMs = [Math]::Round($tcp - $dns, 1) }
            $onceki = $tcp
            if ($tlsVar) {
                $sonuc.TlsMs = [Math]::Round($tls - $tcp, 1)
                $onceki = $tls
            }
            $sonuc.SunucuMs = [Math]::Round($ilk - $onceki, 1)
            $sonuc.IlkBaytMs = $ilk
            $sonuc.ToplamMs = $top
        }
        if ($hizTamam) { $sonuc.VerimBps = [Math]::Round($hiz, 0) }
        if ($baytTamam) { $sonuc.Bayt = [Math]::Round($bayt, 0) }
    }
    $sonuc.Insert(0, 'Alan', $Alan)
    $sonuc.Insert(1, 'Erisim', $temel.Erisim)
    $sonuc.Insert(2, 'Durum', $temel.Durum)
    $sonuc.Insert(3, 'HttpKodu', $temel.HttpKodu)
    $sonuc.Insert(4, 'Aciklama', $temel.Aciklama)
    return [pscustomobject]$sonuc
}

function Invoke-HizOlcumu([string]$Alan, [int]$Sure = 10, [string]$DohUrl) {
    # DohUrl verilirse (profil seçiminde olduğu gibi) DNS engeli devre dışı kalır; yalnızca bağlantı ölçülür.
    $sunucu = Get-TestSunucusu $Alan
    $curl = Get-Curl
    if (-not $curl) { throw 'Windows curl.exe bulunamadı (Windows 10 1803+ gerekir).' }
    # --range en çok 512 KB ister; sunucu yok sayarsa -m süreyi sınırlar.
    $arg = @('-s', '-o', 'NUL', '-w', $Script:HizBicimi, '--connect-timeout', '5', '-m', "$Sure",
        '--range', '0-524287', "https://$sunucu/")
    if ($DohUrl) { $arg = @('--doh-url', $DohUrl) + $arg }
    # --disable ilk argüman olmalı; kullanıcı curlrc ayarları ölçümü değiştirmesin.
    $arg = @('--disable') + $arg
    $cikti = & $curl @arg 2>$null
    return Get-HizOlcumuSonucu $Alan ([string]$cikti) $LASTEXITCODE
}

function Get-Istatistik([double[]]$Degerler) {
    # Ortanca ve p90 (en yakın sıra). Veri yoksa $null.
    $v = @($Degerler | Sort-Object)
    if ($v.Count -eq 0) { return $null }
    $orta = if ($v.Count % 2 -eq 1) { $v[($v.Count - 1) / 2] } else { ($v[$v.Count / 2 - 1] + $v[$v.Count / 2]) / 2 }
    # Sıra = ceil(0.9 * n); kayan nokta hatası olmasın diye tam sayı aritmetiğiyle.
    $p90 = $v[[Math]::Max(0, [int][Math]::Ceiling((9 * $v.Count) / 10.0) - 1)]
    return [pscustomobject]@{
        Say = $v.Count
        Ortanca = [Math]::Round($orta, 1)
        P90 = [Math]::Round($p90, 1)
        En = $v[0]
        Enfazla = $v[$v.Count - 1]
    }
}

function Get-HizOzeti([string]$Alan, $Olcumler) {
    $olcumler = @($Olcumler)
    $basarili = @($olcumler | Where-Object { $_.Erisim })
    $deger = { param($ad) @($basarili | Where-Object { $null -ne $_.$ad } | ForEach-Object { [double]$_.$ad }) }
    $hatalar = @($olcumler | Where-Object { -not $_.Erisim } | Group-Object Durum |
        ForEach-Object { [pscustomobject]@{ Durum = $_.Name; Say = $_.Count } })
    return [pscustomobject]@{
        Alan = $Alan
        Deneme = $olcumler.Count
        Basarili = $basarili.Count
        Hatalar = $hatalar
        Dns = Get-Istatistik (& $deger 'DnsMs')
        Tcp = Get-Istatistik (& $deger 'TcpMs')
        Tls = Get-Istatistik (& $deger 'TlsMs')
        Sunucu = Get-Istatistik (& $deger 'SunucuMs')
        IlkBayt = Get-Istatistik (& $deger 'IlkBaytMs')
        Verim = Get-Istatistik (& $deger 'VerimBps')
        Bayt = Get-Istatistik (& $deger 'Bayt')
    }
}

function Format-HizOzeti($Ozet) {
    $parca = New-Object 'System.Collections.Generic.List[string]'
    foreach ($a in @(@('DNS', 'Dns'), @('TCP', 'Tcp'), @('TLS', 'Tls'), @('sunucu', 'Sunucu'))) {
        $s = $Ozet.($a[1])
        if ($s) { $parca.Add(('{0} {1:N0} ms' -f $a[0], $s.Ortanca)) }
    }
    if ($Ozet.IlkBayt) { $parca.Add(('ilk bayt {0:N0} ms (p90 {1:N0})' -f $Ozet.IlkBayt.Ortanca, $Ozet.IlkBayt.P90)) }
    if ($Ozet.Verim -and $Ozet.Bayt -and $Ozet.Bayt.Ortanca -ge $Script:HizVerimMinBayt) {
        $parca.Add(('örnek verimi {0:N2} MB/s' -f ($Ozet.Verim.Ortanca / 1MB)))
    }
    # Hedef açılıyor ama hiç süre çıkarılamadıysa bunu sessizce atlama; kullanıcı bilsin.
    if ($Ozet.Basarili -gt 0 -and -not $Ozet.IlkBayt) { $parca.Add('süre okunamadı') }
    return ('{0}: {1}/{2} başarılı' -f $Ozet.Alan, $Ozet.Basarili, $Ozet.Deneme) +
        $(if ($parca.Count) { ' | ' + ($parca -join ' | ') } else { '' })
}

function Invoke-Hiz {
    param([string[]]$Hedefler, [int]$Tekrar = 5)
    Baslik 'Bağlantı süresi ölçümü'
    $liste = @($Hedefler + $Script:KontrolSiteleri | Where-Object { $_ } | Select-Object -Unique)
    Yaz "  Her hedef $Tekrar kez ölçülür; ortanca ve p90 gösterilir. Hedefler: $($liste -join ', ')" 'DarkGray'
    Yaz '  Bu bir hat hızı testi değildir: bağlantı aşamalarının sürelerini ölçer. Kontrol siteleri karşılaştırma içindir.' 'DarkGray'
    $ozetler = @()
    foreach ($h in $liste) {
        $olcumler = @()
        for ($i = 0; $i -lt $Tekrar; $i++) {
            if ($i -gt 0) { Start-Sleep -Milliseconds 200 }
            $olcumler += Invoke-HizOlcumu $h
        }
        $ozet = Get-HizOzeti $h $olcumler
        $ozetler += $ozet
        $satir = Format-HizOzeti $ozet
        if ($ozet.Basarili -eq $ozet.Deneme) { Basari $satir }
        elseif ($ozet.Basarili -gt 0) { Uyari $satir } else { Hata $satir }
        foreach ($hata in $ozet.Hatalar) { Yaz "      $($hata.Say) başarısız: $($hata.Durum)" 'DarkGray' }
    }
    return $ozetler
}

function Compare-HizAb($KapaliOzetler, $AcikOzetler) {
    # Aynı hedefler için hizmet kapalı (A) ve hizmet açık (B) ölçümlerini karşılaştırır.
    foreach ($a in @($AcikOzetler)) {
        $k = @($KapaliOzetler | Where-Object { $_.Alan -eq $a.Alan }) | Select-Object -First 1
        if (-not $k) { continue }
        $kMs = Get-OrtancaDegeri $k.IlkBayt
        $aMs = Get-OrtancaDegeri $a.IlkBayt
        $fark = $null
        $yuzde = $null
        $sonuc = 'karsilastirilamadi'
        if ($k.Basarili -eq 0 -and $a.Basarili -gt 0) {
            $sonuc = 'erisim-acildi'
        } elseif ($k.Basarili -gt 0 -and $a.Basarili -eq 0) {
            $sonuc = 'erisim-kayboldu'
        } elseif ($k.Basarili -eq 0 -and $a.Basarili -eq 0) {
            $sonuc = 'ikisi-de-basarisiz'
        } elseif ($null -ne $kMs -and $null -ne $aMs -and [double]$kMs -gt 0) {
            $fark = [Math]::Round([double]$aMs - [double]$kMs, 1)
            $yuzde = [Math]::Round($fark / [double]$kMs * 100, 0)
            if ([Math]::Abs($fark) -ge $Script:OlcumBelirginMs -and [Math]::Abs($yuzde) -ge $Script:OlcumBelirginYuzde) {
                $sonuc = if ($fark -lt 0) { 'daha-hizli' } else { 'daha-yavas' }
            } else {
                $sonuc = 'belirgin-degil'
            }
        }
        [pscustomobject]@{
            Alan         = $a.Alan
            KapaliMs     = $kMs
            AcikMs       = $aMs
            FarkMs       = $fark
            Yuzde        = $yuzde
            Sonuc        = $sonuc
            KapaliBasari = "$($k.Basarili)/$($k.Deneme)"
            AcikBasari   = "$($a.Basarili)/$($a.Deneme)"
        }
    }
}

function Format-HizAbFarki($Fark) {
    $basari = ''
    if ($Fark.KapaliBasari -ne $Fark.AcikBasari) { $basari = " | başarı $($Fark.KapaliBasari) -> $($Fark.AcikBasari)" }
    switch ($Fark.Sonuc) {
        'erisim-acildi' {
            $sure = if ($null -ne $Fark.AcikMs) { (', ilk bayt {0:N0} ms' -f $Fark.AcikMs) } else { '' }
            return "$($Fark.Alan): erişim açıldı (kapalı $($Fark.KapaliBasari) -> açık $($Fark.AcikBasari)$sure)"
        }
        'erisim-kayboldu' {
            return "$($Fark.Alan): erişim kayboldu (kapalı $($Fark.KapaliBasari) -> açık $($Fark.AcikBasari))"
        }
        'ikisi-de-basarisiz' {
            return "$($Fark.Alan): her iki durumda da erişilemedi (kapalı $($Fark.KapaliBasari), açık $($Fark.AcikBasari))"
        }
        'karsilastirilamadi' {
            return "$($Fark.Alan): karşılaştırılamadı (süre eksik)$basari"
        }
        default {
            $metin = '{0}: ilk bayt {1:N0} -> {2:N0} ms ({3:+0;-0;0}%' -f $Fark.Alan, $Fark.KapaliMs, $Fark.AcikMs, $Fark.Yuzde
            switch ($Fark.Sonuc) {
                'daha-hizli' { $metin += ', daha hızlı)' }
                'daha-yavas' { $metin += ', daha yavaş)' }
                default { $metin += ', fark küçük; ölçüm gürültüsü olabilir)' }
            }
            return $metin + $basari
        }
    }
}

function Invoke-HizAb {
    param([string[]]$Hedefler, [int]$Tekrar = 5)
    $hizmet = Get-Hizmet $Script:HizmetAdi
    if (-not $hizmet) { throw 'GoodbyeDPI-TR hizmeti kurulu değil; A/B ölçümü için önce kurun.' }
    $bilgi = Get-GdpiHizmetBilgisi
    if ($bilgi -and $bilgi.StartMode -eq 'Disabled') {
        throw 'Hizmet duraklatılmış; A/B ölçümü için önce devam komutuyla etkinleştirin.'
    }
    $baslangicAcik = ($hizmet.Status -eq 'Running')
    $kapaliOzetler = @()
    $acikOzetler = @()

    Baslik 'A/B bağlantı ölçümü (hizmet kapalı ve açık)'
    Yaz '  Aynı hedefler hizmet kapalıyken ve açıkken ölçülür; işlem sonunda hizmet eski durumuna döndürülür.' 'DarkGray'

    try {
        if ($baslangicAcik) {
            Yaz '  [1/2] Hizmet açıkken ölçülüyor...' 'Cyan'
            $acikOzetler = @(Invoke-Hiz -Hedefler $Hedefler -Tekrar $Tekrar)
            Yaz '  [2/2] Hizmet geçici olarak durdurulup kapalı durumda ölçülüyor...' 'Cyan'
            Stop-Hizmet $Script:HizmetAdi
            Start-Sleep -Seconds 2
            $kapaliOzetler = @(Invoke-Hiz -Hedefler $Hedefler -Tekrar $Tekrar)
        } else {
            Yaz '  [1/2] Hizmet kapalıyken ölçülüyor...' 'Cyan'
            $kapaliOzetler = @(Invoke-Hiz -Hedefler $Hedefler -Tekrar $Tekrar)
            Yaz '  [2/2] Hizmet geçici olarak başlatılıp açık durumda ölçülüyor...' 'Cyan'
            Start-Service $Script:HizmetAdi
            if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Running')) { throw 'Hizmet A/B ölçümü için başlatılamadı.' }
            Start-Sleep -Seconds 2
            $acikOzetler = @(Invoke-Hiz -Hedefler $Hedefler -Tekrar $Tekrar)
        }
    } finally {
        $son = Get-Hizmet $Script:HizmetAdi
        if ($baslangicAcik -and $son -and $son.Status -ne 'Running') {
            Start-Service $Script:HizmetAdi -ErrorAction SilentlyContinue
            Wait-HizmetDurumu $Script:HizmetAdi 'Running' | Out-Null
        } elseif (-not $baslangicAcik -and $son -and $son.Status -eq 'Running') {
            Stop-Hizmet $Script:HizmetAdi
        }
    }

    $farklar = @(Compare-HizAb $kapaliOzetler $acikOzetler)
    Baslik 'A/B karşılaştırma özeti (kapalı -> açık)'
    foreach ($f in $farklar) {
        $satir = Format-HizAbFarki $f
        if ($f.Sonuc -in @('erisim-acildi', 'daha-hizli')) { Basari $satir }
        elseif ($f.Sonuc -in @('erisim-kayboldu', 'daha-yavas', 'ikisi-de-basarisiz')) { Uyari $satir }
        else { Yaz "  $satir" }
    }
    return [pscustomobject]@{
        BaslangicDurumu = if ($baslangicAcik) { 'Running' } else { 'Stopped' }
        Kapali          = $kapaliOzetler
        Acik            = $acikOzetler
        Farklar         = $farklar
    }
}

function Test-IndirmeUrl([string]$Url) {
    if (-not $Url -or $Url.Length -gt 512) { return $false }
    if ($Url.StartsWith('-') -or $Url -match '[\s\p{C}]') { return $false }
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { return $false }
    if ($uri.Scheme -ne 'https') { return $false }
    if (-not (Test-AlanAdi $uri.Host)) { return $false }
    return $true
}

function Get-IndirmeOlcumuSonucu([string]$Url, [string]$Cikti, [int]$CikisKodu) {
    $parcalar = @(([string]$Cikti).Trim() -split '\|')
    $http = if ($parcalar.Count -ge 1) { $parcalar[0] } else { '000' }
    $sureMs = if ($parcalar.Count -eq 8) { ConvertTo-Milisaniye $parcalar[5] } else { $null }
    $hiz = 0.0; $bayt = 0.0
    $hizTamam = $parcalar.Count -eq 8 -and [double]::TryParse($parcalar[6], [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$hiz) -and $hiz -gt 0
    $baytTamam = $parcalar.Count -eq 8 -and [double]::TryParse($parcalar[7], [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$bayt) -and $bayt -ge 0

    $basarili = $false
    $aciklama = 'İndirme başarısız'
    if ($CikisKodu -ne 0) {
        $aciklama = "curl hatası (çıkış $CikisKodu)"
    } elseif ($http -notin @('200', '206')) {
        $aciklama = "Beklenmeyen HTTP kodu: $http"
    } elseif (-not $baytTamam -or $bayt -lt $Script:HizVerimMinBayt) {
        $aciklama = 'İndirilen örnek verim ölçümü için çok küçük'
    } elseif (-not $hizTamam) {
        $aciklama = 'İndirme hızı okunamadı'
    } else {
        $basarili = $true
        $aciklama = 'Tamam'
    }

    return [pscustomobject]@{
        Url       = $Url
        Basarili  = $basarili
        HttpKodu  = $http
        CikisKodu = $CikisKodu
        Bayt      = if ($baytTamam) { [Math]::Round($bayt, 0) } else { $null }
        SureMs    = $sureMs
        VerimBps   = if ($basarili) { [Math]::Round($hiz, 0) } else { $null }
        Mbps       = if ($basarili) { [Math]::Round(($hiz * 8.0) / 1000000.0, 2) } else { $null }
        MegabaytSn = if ($basarili) { [Math]::Round($hiz / 1MB, 2) } else { $null }
        Aciklama   = $aciklama
    }
}

function Invoke-IndirmeOlcumu([string]$Url, [int]$Sure = $Script:IndirmeSureSn, [int]$EnFazlaBayt = $Script:IndirmeEnFazlaBayt) {
    if (-not (Test-IndirmeUrl $Url)) {
        throw "Geçersiz indirme adresi (yalnızca geçerli https:// URL kabul edilir): $Url"
    }
    $curl = Get-Curl
    if (-not $curl) { throw 'Windows curl.exe bulunamadı (Windows 10 1803+ gerekir).' }
    $sonBayt = [Math]::Max(0, $EnFazlaBayt - 1)
    $arg = @('--disable', '-s', '-L', '-o', 'NUL', '-w', $Script:HizBicimi,
        '--connect-timeout', '5', '-m', "$Sure", '--range', "0-$sonBayt", $Url)
    $cikti = & $curl @arg 2>$null
    return Get-IndirmeOlcumuSonucu $Url ([string]$cikti) $LASTEXITCODE
}

function Get-IndirmeOzeti([string]$Url, $Olcumler) {
    $olcumler = @($Olcumler)
    $basarili = @($olcumler | Where-Object { $_.Basarili })
    $deger = { param($ad) @($basarili | Where-Object { $null -ne $_.$ad } | ForEach-Object { [double]$_.$ad }) }
    return [pscustomobject]@{
        Url      = $Url
        Deneme   = $olcumler.Count
        Basarili = $basarili.Count
        Mbps       = Get-Istatistik (& $deger 'Mbps')
        MegabaytSn = Get-Istatistik (& $deger 'MegabaytSn')
        Bayt       = Get-Istatistik (& $deger 'Bayt')
        Hatalar  = @($olcumler | Where-Object { -not $_.Basarili } | Select-Object -ExpandProperty Aciklama -Unique)
    }
}

function Format-IndirmeOzeti($Ozet) {
    $parca = New-Object 'System.Collections.Generic.List[string]'
    if ($Ozet.Mbps -and $Ozet.MegabaytSn) {
        $parca.Add(('ortanca {0:N2} Mbps ({1:N2} MB/s, p90 {2:N2} Mbps)' -f $Ozet.Mbps.Ortanca, $Ozet.MegabaytSn.Ortanca, $Ozet.Mbps.P90))
    }
    if ($Ozet.Bayt) {
        $parca.Add(('{0:N2} MB' -f ($Ozet.Bayt.Ortanca / 1MB)))
    }
    return ('{0}: {1}/{2} başarılı' -f $Ozet.Url, $Ozet.Basarili, $Ozet.Deneme) +
        $(if ($parca.Count) { ' | ' + ($parca -join ' | ') } else { '' })
}

function Invoke-IndirmeHiz {
    param([string[]]$Adresler, [int]$Tekrar = 3)
    $liste = @($Adresler | Where-Object { $_ } | Select-Object -Unique)
    if ($liste.Count -eq 0) { $liste = @($Script:IndirmeHedefleri) }
    foreach ($u in $liste) {
        if (-not (Test-IndirmeUrl $u)) {
            throw "Geçersiz indirme adresi (yalnızca geçerli https:// URL kabul edilir): $u"
        }
    }
    Baslik 'İsteğe bağlı indirme verimi testi'
    $mbSinir = [Math]::Round($Script:IndirmeEnFazlaBayt / 1MB, 1)
    Yaz "  Her adres $Tekrar kez ölçülür (deneme başına en çok $mbSinir MB, diske yazılmaz, hiçbir ayar değişmez)." 'DarkGray'
    Yaz "  Hedef adresler: $($liste -join ', ')" 'DarkGray'
    $ozetler = @()
    foreach ($u in $liste) {
        $olcumler = @()
        for ($i = 0; $i -lt $Tekrar; $i++) {
            if ($i -gt 0) { Start-Sleep -Milliseconds 300 }
            $olcumler += Invoke-IndirmeOlcumu $u
        }
        $ozet = Get-IndirmeOzeti $u $olcumler
        $ozetler += $ozet
        $satir = Format-IndirmeOzeti $ozet
        if ($ozet.Basarili -eq $ozet.Deneme) { Basari $satir }
        elseif ($ozet.Basarili -gt 0) { Uyari $satir } else { Hata $satir }
        foreach ($hata in $ozet.Hatalar) { Yaz "      $hata" 'DarkGray' }
    }
    return $ozetler
}

# --- Ölçüm geçmişi --------------------------------------------------------

function Get-OrtancaDegeri($Istatistik) {
    if ($Istatistik) { return $Istatistik.Ortanca }
    return $null
}

function ConvertTo-OlcumKaydi($Ozetler, [int]$Tekrar) {
    # Yalnızca sayısal özetler ve bağlam saklanır: ham curl çıktısı, IP veya yol yok.
    $hizmet = 'Unknown'
    try {
        $bilgi = Get-GdpiHizmetBilgisi
        $hizmet = if ($bilgi) { [string]$bilgi.State } else { 'NotInstalled' }
    } catch { }
    $profil = $null
    try {
        $ayar = Read-Ayarlar
        if ($ayar -and $ayar.profil -is [string]) { $profil = $ayar.profil }
    } catch { }
    $hedefler = @(foreach ($o in @($Ozetler)) {
        $verim = $null
        if ($o.Verim -and $o.Bayt -and $o.Bayt.Ortanca -ge $Script:HizVerimMinBayt) { $verim = $o.Verim.Ortanca }
        [pscustomobject]@{
            Alan = $o.Alan
            Deneme = $o.Deneme
            Basarili = $o.Basarili
            DnsMs = Get-OrtancaDegeri $o.Dns
            TcpMs = Get-OrtancaDegeri $o.Tcp
            TlsMs = Get-OrtancaDegeri $o.Tls
            SunucuMs = Get-OrtancaDegeri $o.Sunucu
            IlkBaytMs = Get-OrtancaDegeri $o.IlkBayt
            IlkBaytP90Ms = $(if ($o.IlkBayt) { $o.IlkBayt.P90 } else { $null })
            VerimBps = $verim
        }
    })
    return [pscustomobject]@{
        Zaman = (Get-Date).ToUniversalTime().ToString('o')
        Tekrar = $Tekrar
        Hizmet = $hizmet
        Profil = $profil
        Hedefler = $hedefler
    }
}

function Test-OlcumKaydi($Kayit) {
    if ($null -eq $Kayit -or $Kayit -is [string] -or $null -eq (ConvertTo-BekciZamani $Kayit.Zaman)) { return $false }
    if ($null -eq $Kayit.Hedefler) { return $false }
    foreach ($h in @($Kayit.Hedefler)) {
        if ($null -eq $h -or $h.Alan -isnot [string] -or $h.Alan.Length -gt 253) { return $false }
        if ($h.Deneme -isnot [int] -and $h.Deneme -isnot [long]) { return $false }
        if ($h.Basarili -isnot [int] -and $h.Basarili -isnot [long]) { return $false }
    }
    return $true
}

function Read-OlcumGecmisi([System.Collections.Generic.List[string]]$Uyarilar) {
    if (-not $Script:OlcumDosyasi) { throw 'Kullanıcı veri klasörü (LOCALAPPDATA) bulunamadı.' }
    try {
        $dosya = Read-Json $Script:OlcumDosyasi $Uyarilar
    } catch {
        throw "Ölçüm geçmişi okunamadı ($Script:OlcumDosyasi). Dosyayı kontrol edin veya silip yeniden ölçün. Ayrıntı: $($_.Exception.Message)"
    }
    if ($null -eq $dosya) { return @() }
    if ($dosya.SemaSurumu -ne $Script:OlcumSemaSurumu) {
        throw "Ölçüm geçmişi şema sürümü desteklenmiyor: $($dosya.SemaSurumu)"
    }
    $kayitlar = @()
    if ($null -ne $dosya.Kayitlar) { $kayitlar = @($dosya.Kayitlar) }
    $gecerli = @($kayitlar | Where-Object { Test-OlcumKaydi $_ })
    if ($gecerli.Count -lt $kayitlar.Count) {
        $mesaj = "Geçersiz $($kayitlar.Count - $gecerli.Count) ölçüm kaydı atlandı."
        if ($null -ne $Uyarilar) { $Uyarilar.Add($mesaj) } else { Uyari $mesaj }
    }
    return @($gecerli | Sort-Object { ConvertTo-BekciZamani $_.Zaman })
}

function Add-OlcumKaydi($Kayit) {
    $yeni = @(@(Read-OlcumGecmisi) + $Kayit)
    if ($yeni.Count -gt $Script:OlcumEnFazlaKayit) {
        $yeni = @($yeni[($yeni.Count - $Script:OlcumEnFazlaKayit)..($yeni.Count - 1)])
    }
    Save-Json ([pscustomobject]@{ SemaSurumu = $Script:OlcumSemaSurumu; Kayitlar = $yeni }) $Script:OlcumDosyasi
}

function Compare-OlcumKayitlari($Onceki, $Simdi) {
    # Aynı hedefin önceki ve şimdiki ortanca ilk bayt süresini karşılaştırır. Küçük farklar gürültü sayılır.
    foreach ($h in @($Simdi.Hedefler)) {
        $e = @($Onceki.Hedefler | Where-Object { $_.Alan -eq $h.Alan }) | Select-Object -First 1
        if (-not $e) { continue }
        $sonuc = 'karsilastirilamadi'
        $fark = $null
        $yuzde = $null
        if ($null -ne $e.IlkBaytMs -and $null -ne $h.IlkBaytMs -and [double]$e.IlkBaytMs -gt 0) {
            $fark = [Math]::Round([double]$h.IlkBaytMs - [double]$e.IlkBaytMs, 1)
            $yuzde = [Math]::Round($fark / [double]$e.IlkBaytMs * 100, 0)
            if ([Math]::Abs($fark) -ge $Script:OlcumBelirginMs -and [Math]::Abs($yuzde) -ge $Script:OlcumBelirginYuzde) {
                $sonuc = if ($fark -lt 0) { 'daha-hizli' } else { 'daha-yavas' }
            } else {
                $sonuc = 'belirgin-degil'
            }
        }
        [pscustomobject]@{
            Alan = $h.Alan
            OncekiMs = $e.IlkBaytMs
            SimdiMs = $h.IlkBaytMs
            FarkMs = $fark
            Yuzde = $yuzde
            Sonuc = $sonuc
            OncekiBasari = "$($e.Basarili)/$($e.Deneme)"
            SimdiBasari = "$($h.Basarili)/$($h.Deneme)"
        }
    }
}

function Format-OlcumFarki($Fark) {
    $basari = ''
    if ($Fark.OncekiBasari -ne $Fark.SimdiBasari) { $basari = " | başarı $($Fark.OncekiBasari) -> $($Fark.SimdiBasari)" }
    switch ($Fark.Sonuc) {
        'karsilastirilamadi' { return "$($Fark.Alan): karşılaştırılamadı (süre eksik)$basari" }
        default {
            $metin = '{0}: ilk bayt {1:N0} -> {2:N0} ms ({3:+0;-0;0}%' -f $Fark.Alan, $Fark.OncekiMs, $Fark.SimdiMs, $Fark.Yuzde
            switch ($Fark.Sonuc) {
                'daha-hizli' { $metin += ', daha hızlı)' }
                'daha-yavas' { $metin += ', daha yavaş)' }
                default { $metin += ', fark küçük; ölçüm gürültüsü olabilir)' }
            }
            return $metin + $basari
        }
    }
}

function Save-HizOlcumu($Ozetler, [int]$Tekrar) {
    $kayit = ConvertTo-OlcumKaydi $Ozetler $Tekrar
    if (@($kayit.Hedefler | Where-Object { $_.Basarili -gt 0 }).Count -eq 0) {
        Uyari 'Hiçbir hedef ölçülemedi; kayıt eklenmedi.'
        return $false
    }
    $onceki = @(Read-OlcumGecmisi) | Select-Object -Last 1
    if ($onceki) {
        $zaman = (ConvertTo-BekciZamani $onceki.Zaman).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
        Baslik "Önceki ölçümle karşılaştırma ($zaman)"
        if ($onceki.Hizmet -ne $kayit.Hizmet -or $onceki.Profil -ne $kayit.Profil) {
            Yaz "  Bağlam değişti: hizmet $($onceki.Hizmet) -> $($kayit.Hizmet), profil $($onceki.Profil) -> $($kayit.Profil)" 'Cyan'
        }
        foreach ($f in @(Compare-OlcumKayitlari $onceki $kayit)) {
            $satir = Format-OlcumFarki $f
            if ($f.Sonuc -eq 'daha-hizli') { Basari $satir } elseif ($f.Sonuc -eq 'daha-yavas') { Uyari $satir } else { Yaz "  $satir" }
        }
    }
    Add-OlcumKaydi $kayit
    Basari "Ölçüm kaydedildi: $Script:OlcumDosyasi"
    return $true
}

function Invoke-OlcumGecmisi {
    Baslik 'Ölçüm geçmişi'
    $kayitlar = @(Read-OlcumGecmisi)
    if ($kayitlar.Count -eq 0) { Yaz '  Kayıtlı ölçüm yok. "hiz -Kaydet" ile ekleyebilirsiniz.'; return }
    foreach ($k in @($kayitlar | Select-Object -Last 10)) {
        $zaman = (ConvertTo-BekciZamani $k.Zaman).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
        Yaz ("  {0} | hizmet {1} | profil {2} | tekrar {3}" -f $zaman, $k.Hizmet, $(if ($k.Profil) { $k.Profil } else { '-' }), $k.Tekrar) 'Cyan'
        foreach ($h in @($k.Hedefler)) {
            $ms = if ($null -ne $h.IlkBaytMs) { '{0:N0} ms' -f $h.IlkBaytMs } else { '-' }
            Yaz "      $($h.Alan): ilk bayt $ms ($($h.Basarili)/$($h.Deneme) başarılı)"
        }
    }
}

function Test-Internet {
    foreach ($k in $Script:KontrolSiteleri) { if (Test-Https $k) { return $true } }
    return $false
}

function Test-AgVar {
    # DNS'ten bağımsız temel bağlantı: IP adresiyle HTTPS. Modem bağlantısı koparken yapılan
    # DNS denetimi bütün sunucuları "ölü" gösterip hizmeti boşuna durduruyordu.
    foreach ($ip in @('1.1.1.1', '8.8.8.8')) { if (Test-Https $ip -Sure 5) { return $true } }
    return $false
}

function Find-Doh {
    foreach ($u in $Script:DohAdaylari) {
        if (Test-Https $Script:KontrolSiteleri[0] -DohUrl $u) { return $u }
    }
    return $null
}

function Test-Hedefler([string[]]$Hedefler, [string]$DohUrl) {
    $sonuc = [ordered]@{}
    foreach ($h in $Hedefler) { $sonuc[$h] = Test-Https $h -DohUrl $DohUrl }
    return $sonuc
}

# --- İkili dosyalar -------------------------------------------------------

function Test-IkiliHashleri([string]$Dizin, [string]$Mimari) {
    foreach ($ad in $Script:Paket.Dosyalar[$Mimari].Keys) {
        $yol = Join-Path $Dizin $ad
        if (-not (Test-Path $yol)) { return $false }
        if ((Get-FileHash $yol -Algorithm SHA256).Hash -ne $Script:Paket.Dosyalar[$Mimari][$ad]) { return $false }
    }
    return $true
}

function Get-Ikililer {
    # Resmi zip'i indirir, zip'in ve içindeki dosyaların hash'ini doğrular, mimariye uygun klasörü döndürür.
    $mimari = Get-Mimari
    if (-not $mimari) { throw 'Bu işlemci mimarisi desteklenmiyor. WinDivert sürücüsünün ARM64 sürümü yok.' }
    $onbellek = Join-Path $Script:VeriDizini 'onbellek'
    $zip = Join-Path $onbellek 'goodbyedpi.zip'
    $acik = Join-Path $onbellek $Script:Paket.Klasor
    $bin = Join-Path $acik $mimari
    New-Item -ItemType Directory -Force -Path $onbellek | Out-Null

    if (Test-IkiliHashleri $bin $mimari) { return $bin }

    $gecerli = (Test-Path $zip) -and ((Get-FileHash $zip -Algorithm SHA256).Hash -eq $Script:Paket.Sha256)
    if (-not $gecerli) {
        Yaz '  GoodbyeDPI resmi sürümü indiriliyor...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Script:Paket.Url -OutFile $zip -UseBasicParsing
        $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
        if ($hash -ne $Script:Paket.Sha256) {
            Remove-Item $zip -Force
            throw "İndirilen dosyanın hash'i tutmuyor ($hash). Dosya değiştirilmiş olabilir, işlem durduruldu."
        }
    }
    if (Test-Path $acik) { Remove-Item $acik -Recurse -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $onbellek)
    if (-not (Test-IkiliHashleri $bin $mimari)) { throw "Açılan dosyaların hash'i tutmuyor: $bin" }
    return $bin
}

# --- Süreç ve hizmet ------------------------------------------------------

function Start-GdpiGecici([string]$Exe, [string]$Argumanlar) {
    $p = Start-Process -FilePath $Exe -ArgumentList $Argumanlar -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 1500
    if ($p.HasExited) { throw "goodbyedpi.exe hemen kapandı (çıkış kodu $($p.ExitCode)). Argümanlar: $Argumanlar" }
    return $p
}

function Stop-GdpiGecici($Surec) {
    if ($Surec -and -not $Surec.HasExited) {
        Stop-Process -Id $Surec.Id -Force -ErrorAction SilentlyContinue
        $Surec.WaitForExit(5000) | Out-Null
    }
}

function Get-Hizmet([string]$Ad) {
    return Get-Service -Name $Ad -ErrorAction SilentlyContinue
}

function Get-GdpiHizmetBilgisi {
    return Get-CimInstance Win32_Service -Filter "Name='$Script:HizmetAdi'"
}

function Invoke-Duraklat {
    if (-not (Get-Hizmet $Script:HizmetAdi)) { throw 'GoodbyeDPI-TR kurulu değil.' }
    Set-Service -Name $Script:HizmetAdi -StartupType Disabled
    Stop-Hizmet $Script:HizmetAdi
    if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Stopped' 2)) {
        throw 'Otomatik başlatma kapatıldı ancak hizmet durdurulamadı. Durumu denetleyin.'
    }
    Basari 'Hizmet duraklatıldı. Yeniden açmak için devam komutunu kullanın.'
}

function Invoke-Devam {
    $hizmet = Get-GdpiHizmetBilgisi
    if (-not $hizmet) { throw 'GoodbyeDPI-TR kurulu değil.' }
    $duraklatilmis = $hizmet.StartMode -eq 'Disabled'
    if ($duraklatilmis) { Set-Service -Name $Script:HizmetAdi -StartupType Automatic }
    try {
        if ($hizmet.State -ne 'Running') {
            Start-Service $Script:HizmetAdi
            if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Running')) { throw 'Hizmet başlatılamadı.' }
        }
    } catch {
        $baslatmaHatasi = $_
        if ($duraklatilmis) {
            try {
                Set-Service -Name $Script:HizmetAdi -StartupType Disabled
                Stop-Hizmet $Script:HizmetAdi
                if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Stopped' 2)) { throw 'Hizmet durdurulamadı.' }
            } catch {
                throw "Başlatma başarısız: $($baslatmaHatasi.Exception.Message) Duraklatma geri yüklenemedi: $($_.Exception.Message)"
            }
        }
        throw $baslatmaHatasi
    }
    Basari 'Hizmet çalışıyor.'
}

function Wait-HizmetDurumu([string]$Ad, [string]$Durum, [int]$Saniye = 15) {
    for ($i = 0; $i -lt $Saniye * 2; $i++) {
        $h = Get-Hizmet $Ad
        if ($Durum -eq 'Yok') { if (-not $h) { return $true } }
        elseif ($h -and $h.Status -eq $Durum) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Stop-Hizmet([string]$Ad) {
    $h = Get-Hizmet $Ad
    if (-not $h -or $h.Status -eq 'Stopped') { return }
    & $Script:ScExe stop $Ad | Out-Null
    $kod = $LASTEXITCODE
    if (-not (Wait-HizmetDurumu $Ad 'Stopped')) {
        throw "$Ad hizmeti durdurulamadı (Windows kodu: $kod)."
    }
}

function Remove-Hizmet([string]$Ad) {
    if (-not (Get-Hizmet $Ad)) { return $false }
    Stop-Hizmet $Ad
    & $Script:ScExe delete $Ad | Out-Null
    $kod = $LASTEXITCODE
    if ($kod -notin 0, 1072) { throw "$Ad hizmeti silinemedi (Windows kodu: $kod)." }
    if (-not (Wait-HizmetDurumu $Ad 'Yok')) {
        throw "$Ad hizmetinin silinmesi bekleniyor. Hizmetler penceresini kapatıp tekrar deneyin veya Windows'u yeniden başlatın."
    }
    return $true
}

function Get-YabanciGdpiSurecleri {
    # Bizim hizmetimize ait olmayan goodbyedpi.exe süreçleri (eski fork'un .cmd pencereleri vb.).
    $bizim = (Get-CimInstance Win32_Service -Filter "Name='$Script:HizmetAdi'" -ErrorAction SilentlyContinue).ProcessId
    return @(Get-Process -Name goodbyedpi -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $bizim })
}

function Test-WinDivertKaydi {
    return [bool](Get-CimInstance Win32_SystemDriver -Filter "Name LIKE 'WinDivert%'")
}

function Get-HizmetDnsAyari($Dns) {
    if ($null -eq $Dns) { return }
    $port = 0
    if (($Dns.Port -isnot [int] -and $Dns.Port -isnot [long]) -or
        -not [int]::TryParse([string]$Dns.Port, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        throw 'Hizmet ayarındaki DNS portu geçersiz.'
    }
    $v4 = $null
    if ($Dns.V4 -isnot [string] -or -not [Net.IPAddress]::TryParse($Dns.V4, [ref]$v4) -or
        $v4.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'Hizmet ayarındaki IPv4 DNS adresi geçersiz.'
    }
    if ($null -ne $Dns.V6Etkin -and $Dns.V6Etkin -isnot [bool]) {
        throw 'Hizmet ayarındaki IPv6 seçeneği geçersiz.'
    }
    $sonuc = @{ V4 = $v4.ToString(); Port = $port; V6Etkin = $false }
    if ($Dns.V6Etkin) {
        $v6 = $null
        if ($Dns.V6 -isnot [string] -or -not [Net.IPAddress]::TryParse($Dns.V6, [ref]$v6) -or
            $v6.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetworkV6) {
            throw 'Hizmet ayarındaki IPv6 DNS adresi geçersiz.'
        }
        $sonuc.V6 = $v6.ToString()
        $sonuc.V6Etkin = $true
    }
    return $sonuc
}
# WinDivert paylaşılan bir sistem sürücüsüdür; sahibini doğrulamadan silinmez.
# GoodbyeDPI-TR kaldırması yalnız kendi hizmetini ve dosyalarını temizler.

function Get-HizmetKomutu($Ayar) {
    $profil = $null
    if ($Ayar.profil -is [string]) {
        $profil = $Script:Profiller | Where-Object { $_.Ad -ceq $Ayar.profil } | Select-Object -First 1
    } elseif ($null -eq $Ayar.profil -and $Ayar.arg -is [string]) {
        # Profil adı olmadan kaydedilen ayarlarda yalnızca bilinen argüman dizisini kabul et.
        $profil = $Script:Profiller | Where-Object { $_.Arg -ceq $Ayar.arg } | Select-Object -First 1
    }
    if (-not $profil -or ($null -ne $Ayar.arg -and ($Ayar.arg -isnot [string] -or $Ayar.arg -cne $profil.Arg))) {
        throw 'Hizmet ayarındaki profil geçersiz. Ayarı yeniden oluşturun.'
    }
    if ($null -ne $Ayar.genel -and $Ayar.genel -isnot [bool]) {
        throw 'Hizmet ayarındaki kapsam seçeneği geçersiz.'
    }
    $exe = Join-Path $Script:KurulumDizini 'bin\goodbyedpi.exe'
    $liste = Join-Path $Script:KurulumDizini 'liste.txt'
    $dns = Get-HizmetDnsAyari $Ayar.dns
    $arg = Get-GdpiArgumanlari -Profil $profil.Arg -Dns $dns -ListeDosyalari $liste -Genel:([bool]$Ayar.genel)
    return "`"$exe`" $arg"
}

function Set-HizmetYolu($Hizmet, [string]$Yol) {
    $sonuc = Invoke-CimMethod -InputObject $Hizmet -MethodName Change -Arguments @{ PathName = $Yol }
    if ($null -eq $sonuc.ReturnValue -or $sonuc.ReturnValue -ne 0) {
        throw "Hizmet komutu uygulanamadı (Windows kodu: $($sonuc.ReturnValue))."
    }
}

function Update-HizmetKomutu($Ayar) {
    $komut = Get-HizmetKomutu $Ayar
    $hizmet = Get-GdpiHizmetBilgisi
    if (-not $hizmet -or $hizmet.StartMode -eq 'Disabled' -or $hizmet.State -notin 'Running', 'Stopped') {
        throw 'Hizmet yeni ayarı almaya hazır değil.'
    }
    $calisiyordu = $hizmet.State -eq 'Running'
    $eskiYol = $hizmet.PathName
    $yolDegisikligiDenendi = $false
    try {
        if ($calisiyordu) { Stop-Hizmet $Script:HizmetAdi }
        $yolDegisikligiDenendi = $true
        Set-HizmetYolu $hizmet $komut
        Start-Service $Script:HizmetAdi
        if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Running')) { throw 'Hizmet yeni ayarla başlatılamadı.' }
        Start-Sleep -Seconds 3
        if (-not (Test-Internet)) { throw 'Yeni ayarla bağlantı denetimi başarısız.' }
        Save-Ayarlar $Ayar
    } catch {
        $ilkHata = $_
        try {
            if ($yolDegisikligiDenendi) {
                Stop-Hizmet $Script:HizmetAdi
                Set-HizmetYolu $hizmet $eskiYol
            }
            if ($calisiyordu -and (Get-Hizmet $Script:HizmetAdi).Status -ne 'Running') {
                Start-Service $Script:HizmetAdi
                if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Running')) { throw 'Hizmet önceki ayarla başlatılamadı.' }
            }
        } catch {
            throw "Ayar uygulanamadı: $($ilkHata.Exception.Message) Geri alma başarısız: $($_.Exception.Message)"
        }
        throw $ilkHata
    }
}

# --- Bekçi durumu ---------------------------------------------------------

function Read-BekciDurumu {
    $d = Read-Json $Script:BekciDosyasi
    if (-not $d) { $d = [pscustomobject]@{} }
    # Eski sürümün dosyasında olmayan alanlar da eklenir (PSCustomObject'e olmayan alan atanamaz).
    foreach ($alan in 'ardisikHata', 'sonYenidenBul', 'durduruldu', 'durdurmaNedeni', 'sonListe', 'sonListeDeneme') {
        if (-not ($d.PSObject.Properties.Name -contains $alan)) {
            $d | Add-Member -NotePropertyName $alan -NotePropertyValue $(if ($alan -eq 'ardisikHata') { 0 } else { $null })
        }
    }
    $sayi = 0
    if (($d.ardisikHata -isnot [int] -and $d.ardisikHata -isnot [long]) -or
        -not [int]::TryParse([string]$d.ardisikHata, [ref]$sayi) -or $sayi -lt 0) {
        Uyari 'Bekçi hata sayacı geçersiz; sıfırlandı.'
        $sayi = 0
    }
    $d.ardisikHata = [Math]::Min($sayi, 1000)
    foreach ($alan in 'sonYenidenBul', 'durduruldu', 'sonListe') {
        if ($null -eq $d.$alan) { continue }
        if ($null -eq (ConvertTo-BekciZamani $d.$alan)) {
            Uyari "Bekçi tarih alanı geçersiz; sıfırlandı: $alan"
            $d.$alan = $null
        }
    }
    if ($null -ne $d.durdurmaNedeni -and $d.durdurmaNedeni -notin 'dns', 'internet') {
        Uyari 'Bekçi durdurma nedeni geçersiz; otomatik başlatma kaydı sıfırlandı.'
        $d.durduruldu = $null
        $d.durdurmaNedeni = $null
    }
    if (-not $d.durduruldu) { $d.durdurmaNedeni = $null }
    return $d
}

function ConvertTo-BekciZamani($Zaman) {
    if ($Zaman -is [datetime]) { return $Zaman }
    if ($Zaman -isnot [string]) { return $null }
    $tarih = [datetime]::MinValue
    if ([datetime]::TryParseExact($Zaman, [string[]]@('s', 'o'),
        [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$tarih)) {
        return $tarih
    }
    return $null
}

function Test-SureGecti($Zaman, [TimeSpan]$Aralik) {
    $tarih = ConvertTo-BekciZamani $Zaman
    if ($null -eq $tarih) { return $true }
    $simdi = Get-Date
    # Sistem saati geri alındığında gelecekte kalan kayıt sonsuz beklemeye yol açmasın.
    if ($tarih -gt $simdi) { return $true }
    return ($simdi - $tarih) -ge $Aralik
}

# --- Komutlar -------------------------------------------------------------

# --- Sistem önerileri (salt okunur) ---------------------------------------
# Hiçbir sistem ayarı değiştirilmez; yalnızca hızı sınırlayabilecek olası nedenler listelenir.
# Bir şey bulunmaması her şeyin yolunda olduğu anlamına gelmez.

$Script:GucTasarrufuPlani = 'a1841308-3541-4fab-bc81-f71556f20b4a'
$Script:TunelBagdastiriciDeseni = 'TAP-Windows|WireGuard|Wintun|OpenVPN|NordLynx|Tailscale|AnyConnect|ZeroTier|Hamachi|WARP|Fortinet|GlobalProtect'

function Get-SistemDurumu {
    # Toplanamayan her bilgi $null kalır; öneri üretilirken atlanır.
    $d = [ordered]@{ FizikselAgBagdastiricilari = $null; TumAgBagdastiricilari = $null; GucPlaniGuid = $null; ProxyAcik = $null }
    try { $d.FizikselAgBagdastiricilari = @(Get-NetAdapter -Physical -ErrorAction Stop) } catch { }
    try { $d.TumAgBagdastiricilari = @(Get-NetAdapter -ErrorAction Stop) } catch { }
    try {
        $cikti = [string](& (Join-Path $Script:SistemDizini 'powercfg.exe') /getactivescheme 2>$null)
        $m = [regex]::Match($cikti, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
        if ($m.Success) { $d.GucPlaniGuid = $m.Value.ToLowerInvariant() }
    } catch { }
    try {
        $ayar = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $d.ProxyAcik = [bool]($ayar.ProxyEnable -eq 1)
    } catch { }
    return [pscustomobject]$d
}

function Get-SistemOnerileri($Durum) {
    $oneriler = New-Object 'System.Collections.Generic.List[object]'
    $ekle = { param($Seviye, $Baslik, $Aciklama) $oneriler.Add([pscustomobject]@{ Seviye = $Seviye; Baslik = $Baslik; Aciklama = $Aciklama }) }
    $acik = @($Durum.FizikselAgBagdastiricilari | Where-Object { $_ -and $_.Status -eq 'Up' })
    foreach ($a in $acik) {
        $mbps = $null
        if ($a.Speed -is [ValueType] -and [double]$a.Speed -gt 0) { $mbps = [Math]::Round([double]$a.Speed / 1e6, 0) }
        $kablolu = $a.MediaType -eq '802.3'
        $kablosuz = $a.MediaType -match '802\.11'
        if ($kablolu -and $null -ne $mbps -and $mbps -le 100) {
            & $ekle 'oneri' "Ethernet $mbps Mbps'te bağlı ($($a.Name))" 'Hat hızınız bunun üzerindeyse bu bağlantı sınırlar. Kablo, priz, modem portu veya anahtar gigabit desteklemiyor ya da arızalı olabilir; başka kablo/port deneyin.'
        }
        if ($kablolu -and $a.FullDuplex -eq $false) {
            & $ekle 'oneri' "Ethernet yarım dupleks çalışıyor ($($a.Name))" 'Genellikle kablo veya karşı cihazla otomatik uyumlama (auto-negotiation) sorunu göstergesidir.'
        }
        if ($kablosuz -and $null -ne $mbps -and $mbps -lt 100) {
            & $ekle 'oneri' "Wi-Fi bağlantı hızı düşük: $mbps Mbps ($($a.Name))" 'Modeme yaklaşmak veya 5 GHz bandına geçmek, ayrıca kablo kullanmak bağlantı hızını artırabilir.'
        }
    }
    if ($acik.Count -gt 1) {
        $adlar = ($acik | ForEach-Object { $_.Name }) -join ', '
        & $ekle 'bilgi' "Birden fazla fiziksel ağ bağdaştırıcısı açık: $adlar" 'Windows trafiği metriğe göre birine yönlendirir. Hız karşılaştırırken hangisinin kullanıldığını bilin.'
    }
    foreach ($t in @($Durum.TumAgBagdastiricilari | Where-Object { $_ -and $_.Status -eq 'Up' -and ($_.InterfaceDescription -match $Script:TunelBagdastiriciDeseni) })) {
        & $ekle 'bilgi' "VPN/tünel bağdaştırıcısı etkin: $($t.InterfaceDescription)" 'Trafik başka bir yoldan geçiyorsa hız ve gecikme değişir; ölçümler bu yolu yansıtır.'
    }
    if ($Durum.GucPlaniGuid -eq $Script:GucTasarrufuPlani) {
        & $ekle 'oneri' 'Güç planı "Güç tasarrufu"' 'Ağ bağdaştırıcısı ve işlemci performansını kısıtlayabilir; Dengeli veya Yüksek performans planı denenebilir.'
    }
    if ($Durum.ProxyAcik -eq $true) {
        & $ekle 'bilgi' 'Sistem proxy ayarı açık' 'Tarayıcı ve birçok uygulama trafiği proxy üzerinden geçirir; curl tabanlı ölçümler proxy kullanmaz.'
    }
    # PowerShell 5.1'de @() ile List[object] dönüştürmek "Bağımsız değişken türleri eşleşmiyor" hatası verir.
    return $oneriler.ToArray()
}

function Invoke-Oneriler {
    Baslik 'Sistem önerileri (salt okunur)'
    Yaz '  Hiçbir ayar değişmez. Bu liste olası nedenleri gösterir; kesin tanı değildir.' 'DarkGray'
    $durum = Get-SistemDurumu
    $oneriler = @(Get-SistemOnerileri $durum)
    if ($null -eq $durum.FizikselAgBagdastiricilari) { Uyari 'Ağ bağdaştırıcıları okunamadı; bu kontroller atlandı.' }
    foreach ($o in $oneriler) {
        $satir = "$($o.Baslik): $($o.Aciklama)"
        if ($o.Seviye -eq 'oneri') { Uyari $satir } else { Yaz "  [i] $satir" }
    }
    if ($oneriler.Count -eq 0) { Basari 'Hızı sınırlayabilecek belirgin bir sistem ayarı bulunamadı (bu her şeyin yolunda olduğunu garanti etmez).' }
    return $oneriler
}

# --- Profil seçimi (ölçüme dayalı) ----------------------------------------

# İlk çalışan profil bulunduktan sonra en çok bu kadar ek profil karşılaştırılır (süreyi sınırlamak için).
$Script:ProfilKarsilastirmaSayisi = 2

function Test-BelirginFark([double]$Eski, [double]$Yeni) {
    # $Yeni, $Eski'den hem OlcumBelirginMs hem OlcumBelirginYuzde kadar daha hızlı mı?
    if ($Eski -le 0) { return $false }
    $fark = $Eski - $Yeni
    return ($fark -ge $Script:OlcumBelirginMs) -and (($fark / $Eski * 100) -ge $Script:OlcumBelirginYuzde)
}

function Measure-ProfilHizi([string[]]$Hedefler, [string]$DohUrl, [int]$Tekrar = 3) {
    # Çalışan geçici GoodbyeDPI altında, DNS hariç bağlantı kurulumundan ilk bayta kadar geçen süreyi ölçer.
    # Örneklerin yarısından azı okunabildiyse sonuç güvenilmez sayılır ($null).
    $sureler = New-Object 'System.Collections.Generic.List[double]'
    $denenen = 0
    foreach ($h in $Hedefler) {
        for ($i = 0; $i -lt $Tekrar; $i++) {
            $denenen++
            try { $o = Invoke-HizOlcumu $h 8 $DohUrl } catch { continue }
            if ($o.Erisim -and $null -ne $o.IlkBaytMs -and $null -ne $o.DnsMs) {
                $sureler.Add([double]$o.IlkBaytMs - [double]$o.DnsMs)
            }
        }
    }
    $ortanca = $null
    if ($sureler.Count -gt 0 -and $sureler.Count * 2 -ge $denenen) { $ortanca = (Get-Istatistik $sureler.ToArray()).Ortanca }
    return [pscustomobject]@{ Ortanca = $ortanca; Denenen = $denenen; Olculen = $sureler.Count }
}

function Select-ProfilAdayi($Calisanlar, [string]$MevcutAd) {
    # $Calisanlar güvenliden riskliye sıralı çalışan profillerdir (Profil, Ortanca). Güvenli olan, ancak
    # başka biri belirgin hızlıysa bırakılır. Kayıtlı profil de belirgin yavaş değilse korunur (kararlılık).
    $c = @($Calisanlar)
    if ($c.Count -eq 0) { return $null }
    $secilen = $c[0]
    if ($null -ne $secilen.Ortanca) {
        $en = $null
        foreach ($a in $c) { if ($null -ne $a.Ortanca -and ($null -eq $en -or $a.Ortanca -lt $en.Ortanca)) { $en = $a } }
        if ($en -and (Test-BelirginFark $secilen.Ortanca $en.Ortanca)) { $secilen = $en }
    }
    if ($MevcutAd) {
        $m = $c | Where-Object { $_.Profil.Ad -eq $MevcutAd } | Select-Object -First 1
        if ($m -and ($null -eq $m.Ortanca -or $null -eq $secilen.Ortanca -or -not (Test-BelirginFark $m.Ortanca $secilen.Ortanca))) {
            $secilen = $m
        }
    }
    return $secilen
}

function Invoke-Bul {
    param([string[]]$Hedefler, [switch]$Genel, [switch]$Kaydetme)
    Baslik 'Çalışan ayar aranıyor'
    if ((Get-GdpiHizmetBilgisi).StartMode -eq 'Disabled') {
        throw 'Hizmet duraklatıldı. Profil aramadan önce devam komutunu çalıştırın.'
    }

    $eski = Get-Hizmet 'GoodbyeDPI'
    if (($eski -and $eski.Status -ne 'Stopped') -or (Get-YabanciGdpiSurecleri)) {
        throw 'Başka bir GoodbyeDPI çalışıyor. Ölçümden önce o kurulumun kendi aracından durdurun.'
    }
    # Çalışan bir GoodbyeDPI ölçümü bozar: hizmet açıkken engel "yok" görünür.
    $hizmetCalisiyordu = $false
    $h = Get-Hizmet $Script:HizmetAdi

    try {
        if ($h -and $h.Status -eq 'Running') {
            $hizmetCalisiyordu = $true
            Yaz '  Ölçüm için GoodbyeDPI-TR hizmeti geçici olarak durduruluyor...'
            Stop-Hizmet $Script:HizmetAdi
        }
        if (-not (Test-Internet)) { throw 'İnternet bağlantısı yok (kontrol sitelerine ulaşılamadı). Önce bağlantınızı kontrol edin.' }

        $doh = Find-Doh
        if (-not $doh) { throw 'Hiçbir DoH sunucusuna ulaşılamadı; DPI ölçümü yapılamıyor.' }

        $bin = Get-Ikililer
        $exe = Join-Path $bin 'goodbyedpi.exe'
        $liste = Write-Liste (Get-ListeDosyalari $Script:KaynakDizini) $Hedefler (Join-Path $Script:VeriDizini 'deneme-liste.txt')

        $iss = Get-Iss
        if ($iss) { Yaz "  İSS: $($iss.Ad) (AS$($iss.Asn))" }

        # 1) DNS: İSS DNS'i engelli adresi mi veriyor?
        Yaz '  DNS sunucusu seçiliyor...'
        # Kayıtlı DNS varsa histerezis için mevcut olarak geç: küçük farklar yüzünden sunucu değişmesin.
        $mevcutDns = $null
        $mevcutProfil = $null
        try {
            $kayitli = Read-Ayarlar
            if ($kayitli -and $kayitli.dns) { $mevcutDns = $kayitli.dns }
            if ($kayitli -and $kayitli.profil -is [string]) { $mevcutProfil = $kayitli.profil }
        } catch { }
        $dns = Find-DnsSunucusu $Hedefler $mevcutDns
        if ($dns) { Basari "DNS: $($dns.Ad) ($($dns.V4):$($dns.Port))" }
        else { Uyari 'Standart dışı porttaki DNS sunucularına ulaşılamadı, DNS yönlendirmesi kapalı kalacak.' }

        # 2) DPI: DoH ile DNS'ten bağımsız ölç.
        $once = Test-Hedefler $Hedefler $doh
        $engelli = @($once.Keys | Where-Object { -not $once[$_] })
        if (-not $engelli) {
            Basari 'Hedefler GoodbyeDPI olmadan da açılıyor. DPI engeli yok, yalnızca DNS yönlendirmesi kullanılacak.'
            $secilen = $Script:Profiller[0]
        } else {
            Yaz "  DPI engeli olan hedefler: $($engelli -join ', ')"
            $secilen = $null
            $asn = $null; if ($iss) { $asn = $iss.Asn }
            # Güvenliden riskliye sıralı profiller denenir. İlk çalışan bulunduktan sonra yalnızca birkaç güvenli
            # aday daha karşılaştırılır; --set-ttl içeren riskli profiller hız için denenmez.
            $calisanlar = @()
            $ekDenenen = 0
            foreach ($p in Get-SiraliProfiller $asn) {
                if ($calisanlar.Count -gt 0) {
                    if ($ekDenenen -ge $Script:ProfilKarsilastirmaSayisi -or $p.Arg -match 'set-ttl') { break }
                    $ekDenenen++
                }
                $arg = Get-GdpiArgumanlari -Profil $p.Arg -ListeDosyalari $liste -Genel:$Genel
                Yaz "  Deneniyor: $($p.Ad)  ($($p.Arg))" 'DarkGray'
                $surec = $null
                $hiz = $null
                try {
                    $surec = Start-GdpiGecici $exe $arg
                    $sonuc = Test-Hedefler $engelli $doh
                    $tumu = -not ($sonuc.Values -contains $false)
                    $kontrol = Test-Https $Script:KontrolSiteleri[0]
                    # Hız, geçici süreç hâlâ çalışırken ölçülür.
                    if ($tumu -and $kontrol) { $hiz = Measure-ProfilHizi $engelli $doh }
                } catch {
                    Uyari $_.Exception.Message
                    $tumu = $false; $kontrol = $false
                } finally {
                    Stop-GdpiGecici $surec
                }
                if ($tumu -and $kontrol) {
                    $calisanlar += [pscustomobject]@{ Profil = $p; Ortanca = $(if ($hiz) { $hiz.Ortanca } else { $null }) }
                }
            }
            if ($calisanlar.Count -eq 0) {
                Hata 'Hiçbir profil engeli aşamadı. İSS IP tabanlı engel uyguluyor olabilir; bu durumda VPN gerekir.'
                return $null
            }
            if ($calisanlar.Count -gt 1) {
                $ozet = @($calisanlar | ForEach-Object { '{0} {1}' -f $_.Profil.Ad, $(if ($null -ne $_.Ortanca) { '{0:N0} ms' -f $_.Ortanca } else { 'ölçülemedi' }) }) -join ', '
                Yaz "  Çalışan profiller (bağlantı sonrası ilk bayt, ortanca): $ozet" 'DarkGray'
            }
            $secilen = (Select-ProfilAdayi $calisanlar $mevcutProfil).Profil
            Basari "Çalışan profil: $($secilen.Ad)"
        }

        $issAd = $null; $issAsn = $null
        if ($iss) { $issAd = $iss.Ad; $issAsn = $iss.Asn }
        $ayar = [pscustomobject][ordered]@{
            surum    = $Script:Surum
            profil   = $secilen.Ad
            arg      = $secilen.Arg
            dns      = $dns
            genel    = [bool]$Genel
            hedefler = $Hedefler
            iss      = $issAd
            asn      = $issAsn
            tarih    = (Get-Date).ToString('s')
        }
        if (-not $Kaydetme) {
            Save-Ayarlar $ayar
            Basari "Ayarlar kaydedildi: $Script:AyarDosyasi"
        }
        return $ayar
    } finally {
        if ($hizmetCalisiyordu -and (Get-Hizmet $Script:HizmetAdi)) { Start-Service $Script:HizmetAdi -ErrorAction SilentlyContinue }
    }
}

function Get-KaldirmaDegerleri {
    $cmd = Join-Path $Script:KurulumDizini 'GoodbyeDPI-TR.cmd'
    return @{
        DisplayName     = 'GoodbyeDPI-TR'
        DisplayVersion  = $Script:Surum
        Publisher       = 'GoodbyeDPI-TR'
        InstallLocation = $Script:KurulumDizini
        URLInfoAbout    = $Script:ProjeUrl
        UninstallString = "`"$cmd`" kaldir"
        NoModify        = 1
        NoRepair        = 1
    }
}

function Install-Kisayollar {
    $cmd = Join-Path $Script:KurulumDizini 'GoodbyeDPI-TR.cmd'
    $kabuk = New-Object -ComObject WScript.Shell
    $k = $kabuk.CreateShortcut($Script:Kisayol)
    $k.TargetPath = $cmd
    $k.WorkingDirectory = $Script:KurulumDizini
    $k.Description = 'GoodbyeDPI-TR menüsü'
    $k.Save()

    if (-not (Test-Path -LiteralPath $Script:KaldirmaAnahtari)) {
        New-Item -Path $Script:KaldirmaAnahtari | Out-Null
    }
    $degerler = Get-KaldirmaDegerleri
    foreach ($ad in $degerler.Keys) {
        $tur = if ($degerler[$ad] -is [int]) { 'DWord' } else { 'String' }
        New-ItemProperty -LiteralPath $Script:KaldirmaAnahtari -Name $ad -Value $degerler[$ad] -PropertyType $tur -Force | Out-Null
    }
}

function Get-BekciGorevi {
    Get-ScheduledTask | Where-Object { $_.TaskName -eq $Script:GorevAdi -and $_.TaskPath -eq '\' }
}

function Get-KurulumKayitYedegi {
    $yedek = @{ GorevXml = $null; Kisayol = $null; AnahtarVardi = $false; Degerler = @{} }
    if (Get-BekciGorevi) {
        $yedek.GorevXml = Export-ScheduledTask -TaskName $Script:GorevAdi -TaskPath '\'
        if (-not $yedek.GorevXml) { throw 'Mevcut bekçi görevi yedeklenemedi.' }
    }
    if ([IO.File]::Exists($Script:Kisayol)) { $yedek.Kisayol = [IO.File]::ReadAllBytes($Script:Kisayol) }
    if (Test-Path -LiteralPath $Script:KaldirmaAnahtari) {
        $yedek.AnahtarVardi = $true
        $anahtar = Get-Item -LiteralPath $Script:KaldirmaAnahtari
        try {
            foreach ($ad in (Get-KaldirmaDegerleri).Keys) {
                if ($ad -in $anahtar.GetValueNames()) {
                    $yedek.Degerler[$ad] = @{
                        Deger = $anahtar.GetValue($ad, $null, 'DoNotExpandEnvironmentNames')
                        Tur = $anahtar.GetValueKind($ad)
                    }
                }
            }
        } finally {
            $anahtar.Dispose()
        }
    }
    return $yedek
}

function Restore-KurulumKayitlari($Yedek, [bool]$KisayolaDokunuldu) {
    $hatalar = @()
    try {
        if ($Yedek.GorevXml) {
            Register-ScheduledTask -TaskName $Script:GorevAdi -TaskPath '\' -Xml $Yedek.GorevXml -Force | Out-Null
        } elseif (Get-BekciGorevi) {
            Unregister-ScheduledTask -TaskName $Script:GorevAdi -TaskPath '\' -Confirm:$false
        }
    } catch { $hatalar += "Bekçi: $($_.Exception.Message)" }

    if ($KisayolaDokunuldu) {
        try {
            if ($null -ne $Yedek.Kisayol) {
                [IO.File]::WriteAllBytes($Script:Kisayol, $Yedek.Kisayol)
            } elseif ([IO.File]::Exists($Script:Kisayol)) {
                [IO.File]::Delete($Script:Kisayol)
            }
        } catch { $hatalar += "Kısayol: $($_.Exception.Message)" }
        try {
            if ($Yedek.AnahtarVardi) {
                $altYol = $Script:KaldirmaAnahtari.Substring('HKLM:\'.Length)
                $anahtar = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($altYol, $true)
                if (-not $anahtar) { throw 'Önceki kaldırma kaydı açılamadı.' }
                try {
                    foreach ($ad in (Get-KaldirmaDegerleri).Keys) {
                        if ($Yedek.Degerler.ContainsKey($ad)) {
                            $onceki = $Yedek.Degerler[$ad]
                            $anahtar.SetValue($ad, $onceki.Deger, $onceki.Tur)
                        } else {
                            $anahtar.DeleteValue($ad, $false)
                        }
                    }
                } finally {
                    $anahtar.Dispose()
                }
            } elseif (Test-Path -LiteralPath $Script:KaldirmaAnahtari) {
                if (Get-ChildItem -LiteralPath $Script:KaldirmaAnahtari) {
                    throw 'Kaldırma kaydında beklenmeyen alt anahtar var.'
                }
                Remove-Item -LiteralPath $Script:KaldirmaAnahtari -Confirm:$false
            }
        } catch { $hatalar += "Kaldırma kaydı: $($_.Exception.Message)" }
    }
    if ($hatalar) { throw ($hatalar -join ' | ') }
}

function Install-BekciGorevi {
    $ps1 = Join-Path $Script:KurulumDizini 'gdpi-tr.ps1'
    $powershell = Join-Path $Script:SistemDizini 'WindowsPowerShell\v1.0\powershell.exe'
    $eylem = New-ScheduledTaskAction -Execute $powershell `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`" bekci"

    $acilis = New-ScheduledTaskTrigger -AtStartup
    $acilis.Delay = 'PT1M'
    $periyodik = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(15) -RepetitionInterval (New-TimeSpan -Minutes 15)
    # Ağ değişince (Wi-Fi/mobil veri/başka modem) hemen denetle.
    $sinif = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $ag = New-CimInstance -CimClass $sinif -ClientOnly
    $ag.Enabled = $true
    $ag.Delay = 'PT30S'
    $ag.Subscription = '<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[(EventID=10000)]]</Select></Query></QueryList>'

    $ayar = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    $kim = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $Script:GorevAdi -Action $eylem -Trigger @($acilis, $periyodik, $ag) `
        -Settings $ayar -Principal $kim -Description 'GoodbyeDPI-TR: DNS ve bağlantı denetimi' -Force | Out-Null
}

function Invoke-Kur {
    param([switch]$Genel, [string[]]$Hedefler, [switch]$YenidenBul)
    if ((Get-Hizmet 'GoodbyeDPI') -or (Get-YabanciGdpiSurecleri)) {
        throw 'Başka bir GoodbyeDPI kurulumu bulundu. Devam etmeden önce eski kurulumu kendi kaldırma aracından kaldırın.'
    }
    $ayar = Read-Ayarlar
    if (-not $ayar -or $YenidenBul) {
        $ayar = Invoke-Bul -Hedefler $Hedefler -Genel:$Genel -Kaydetme
        if (-not $ayar) { return }
    }
    Baslik 'Kurulum'

    $komut = Get-HizmetKomutu $ayar
    $bin = Get-Ikililer
    $hedefBin = Join-Path $Script:KurulumDizini 'bin'
    $hedefListe = Join-Path $Script:KurulumDizini 'listeler'
    $mimari = Get-Mimari
    $dosyalar = [ordered]@{}
    foreach ($ad in $Script:Paket.Dosyalar[$mimari].Keys) {
        $dosyalar[(Join-Path $hedefBin $ad)] = Join-Path $bin $ad
    }
    if ($Script:KaynakDizini -ne $Script:KurulumDizini) {
        foreach ($dosya in Get-KurulumListeKopyalari $Script:KaynakDizini $hedefListe) {
            $dosyalar[$dosya.Hedef] = $dosya.Kaynak
        }
        $dosyalar[(Join-Path $Script:KurulumDizini 'gdpi-tr.ps1')] = $PSCommandPath
        $cmd = Join-Path $Script:KaynakDizini 'GoodbyeDPI-TR.cmd'
        if (Test-Path -LiteralPath $cmd) {
            $dosyalar[(Join-Path $Script:KurulumDizini 'GoodbyeDPI-TR.cmd')] = $cmd
        }
    }
    $liste = Join-Path $Script:KurulumDizini 'liste.txt'
    $hizmet = Get-GdpiHizmetBilgisi
    if ($hizmet -and $hizmet.State -notin 'Running', 'Stopped') {
        throw "Kurulum başlamadı. Hizmet kararlı durumda değil ($($hizmet.State))."
    }
    $eskiYol = $hizmet.PathName
    $calisiyordu = $hizmet.State -eq 'Running'
    $duraklatilmis = $hizmet.StartMode -eq 'Disabled'
    $kayitYedegi = Get-KurulumKayitYedegi
    $yedek = @{}
    foreach ($yol in @($dosyalar.Keys) + $liste) {
        $yedek[$yol] = if ([IO.File]::Exists($yol)) { ,([IO.File]::ReadAllBytes($yol)) } else { $null }
    }
    $yeniHizmet = $false
    $dosyalarDegisti = $false
    $goreveDokunuldu = $false
    $kisayolaDokunuldu = $false
    try {
        if ($calisiyordu) {
            Stop-Hizmet $Script:HizmetAdi
            if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Stopped' 2)) { throw 'Hizmet durdurulamadı.' }
        }
        $dosyalarDegisti = $true
        New-Item -ItemType Directory -Force -Path $hedefBin, $hedefListe | Out-Null
        foreach ($yol in $dosyalar.Keys) {
            Copy-Item -LiteralPath $dosyalar[$yol] -Destination $yol -Force
        }
        if (-not (Test-IkiliHashleri $hedefBin $mimari)) { throw 'Kopyalanan dosyaların hash doğrulaması başarısız.' }
        Write-Liste (Get-ListeDosyalari $Script:KurulumDizini) @($ayar.hedefler) $liste | Out-Null
        if ($hizmet) {
            Set-HizmetYolu $hizmet $komut
        } else {
            New-Service -Name $Script:HizmetAdi -BinaryPathName $komut -DisplayName 'GoodbyeDPI-TR' `
                -StartupType Automatic -Description 'GoodbyeDPI-TR bağlantı hizmeti.' | Out-Null
            $yeniHizmet = $true
            & $Script:ScExe failure $Script:HizmetAdi reset= 86400 actions= restart/5000/restart/30000// | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Hizmet kurtarma ayarı uygulanamadı ($LASTEXITCODE)." }
        }
        if (-not $duraklatilmis) {
            Start-Service $Script:HizmetAdi
            if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Running')) { throw 'Hizmet başlatılamadı.' }
            Start-Sleep -Seconds 3
            if (-not (Test-Internet)) { throw 'Kurulumdan sonra internet denetimi başarısız.' }
        }
        $goreveDokunuldu = $true
        Install-BekciGorevi
        $kisayolaDokunuldu = $true
        Install-Kisayollar
        Save-Ayarlar $ayar
    } catch {
        $ilkHata = $_
        $geriAlmaHatalari = @()
        try {
            if ($yeniHizmet) {
                Remove-Hizmet $Script:HizmetAdi | Out-Null
                if (Get-Hizmet $Script:HizmetAdi) { throw 'Yeni hizmet kaldırılamadı.' }
            } elseif ($hizmet -and $dosyalarDegisti) {
                Stop-Hizmet $Script:HizmetAdi
                if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Stopped' 2)) { throw 'Hizmet durdurulamadı.' }
                Set-HizmetYolu $hizmet $eskiYol
            }
            if ($dosyalarDegisti) {
                foreach ($yol in $yedek.Keys) {
                    if ($null -eq $yedek[$yol]) {
                        if ([IO.File]::Exists($yol)) { [IO.File]::Delete($yol) }
                    } else {
                        [IO.File]::WriteAllBytes($yol, $yedek[$yol])
                    }
                }
            }
            if ($calisiyordu -and (Get-Hizmet $Script:HizmetAdi).Status -ne 'Running') {
                Start-Service $Script:HizmetAdi
                if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Running')) { throw 'Önceki hizmet başlatılamadı.' }
            }
        } catch {
            $geriAlmaHatalari += $_.Exception.Message
        }
        if ($goreveDokunuldu) {
            try {
                Restore-KurulumKayitlari $kayitYedegi $kisayolaDokunuldu
            } catch {
                $geriAlmaHatalari += $_.Exception.Message
            }
        }
        if ($geriAlmaHatalari) {
            throw "Kurulum başarısız: $($ilkHata.Exception.Message) Geri alma da başarısız: $($geriAlmaHatalari -join ' | ')"
        }
        throw $ilkHata
    }

    if ($duraklatilmis) {
        Basari 'Kurulum güncellendi. Hizmet duraklatılmış durumda.'
        return
    }
    Basari "Hizmet kuruldu ve çalışıyor ($($ayar.profil)). Bekçi görevi her 15 dakikada ve ağ değişiminde denetleyecek."
    $sonuc = Invoke-Test -Hedefler @($ayar.hedefler)
    if ($sonuc -contains $false) {
        Uyari 'Bazı hedefler açılmıyor. Menüden "Çalışan ayarı bul ve kur" seçeneğini tekrar deneyin.'
    }
}

function Assert-KurulumSilmeYolu {
    $programlar = [Environment]::GetFolderPath('ProgramFiles')
    if (-not $programlar) { throw 'Windows Program Files dizini bulunamadı.' }
    $beklenen = Join-Path $programlar 'GoodbyeDPI-TR'
    if ([IO.Path]::GetFullPath($Script:KurulumDizini) -ine $beklenen) {
        throw 'Kurulum dizini doğrulanamadı; dosyalar silinmedi.'
    }
    if (-not (Test-Path -LiteralPath $beklenen)) { return }
    $kok = Get-Item -LiteralPath $beklenen -Force
    $ust = Get-Item -LiteralPath $programlar -Force
    if (-not $kok.PSIsContainer -or
        ($kok.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        ($ust.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Kurulum yolu bir bağlantı veya beklenmeyen bir dosya içeriyor.'
    }
    $dizinler = New-Object 'System.Collections.Generic.Stack[string]'
    $dizinler.Push($kok.FullName)
    while ($dizinler.Count -gt 0) {
        foreach ($oge in Get-ChildItem -LiteralPath ($dizinler.Pop()) -Force) {
            if ($oge.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Kurulum dizininde bağlantı bulundu: $($oge.FullName)"
            }
            if ($oge.PSIsContainer) { $dizinler.Push($oge.FullName) }
        }
    }
}

function Invoke-Kaldir {
    param([switch]$Eski)
    Baslik 'Kaldırma'
    Assert-KurulumSilmeYolu
    $surucuVardi = Test-WinDivertKaydi
    if (Remove-Hizmet $Script:HizmetAdi) { Basari "$Script:HizmetAdi hizmeti kaldırıldı" } else { Yaz '  GoodbyeDPI-TR hizmeti yok.' }
    if (Get-BekciGorevi) {
        Unregister-ScheduledTask -TaskName $Script:GorevAdi -TaskPath '\' -Confirm:$false
        Basari 'Bekçi görevi kaldırıldı'
    }
    if ($Eski) {
        if (Remove-Hizmet 'GoodbyeDPI') { Basari 'Eski GoodbyeDPI hizmeti kaldırıldı' }
    }
    foreach ($y in @($Script:Kisayol, $Script:KaldirmaAnahtari)) {
        if (-not (Test-Path -LiteralPath $y)) { continue }
        if ($y -eq $Script:KaldirmaAnahtari -and (Get-ChildItem -LiteralPath $y)) {
            throw 'Kaldırma kaydında beklenmeyen alt anahtar var.'
        }
        Remove-Item -LiteralPath $y -Force -Confirm:$false
    }
    if (Test-Path -LiteralPath $Script:KurulumDizini) {
        Assert-KurulumSilmeYolu
        $binKalsin = ($surucuVardi -or (Test-WinDivertKaydi)) -and
            (Test-Path -LiteralPath (Join-Path $Script:KurulumDizini 'bin') -PathType Container)
        if ($binKalsin) {
            Get-ChildItem -LiteralPath $Script:KurulumDizini -Force |
                Where-Object { $_.Name -ne 'bin' } |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
            Uyari 'Paylaşılan WinDivert kaydı bulundu; sürücü ve bin klasörü korundu.'
        } else {
            Remove-Item -LiteralPath $Script:KurulumDizini -Recurse -Force
            Basari "Silindi: $Script:KurulumDizini"
        }
    }
    if (Test-Path -LiteralPath $Script:EskiVeriDizini) {
        Uyari "Eski sürümün veri klasörü korundu: $Script:EskiVeriDizini"
    }
    Yaz '  DNS ayarlarınıza dokunulmadı; bu araç sistem DNS ayarını değiştirmez.'
}

function Invoke-Test {
    param([string[]]$Hedefler)
    Baslik 'Erişim testi (sistem DNS ile)'
    $sonuc = [ordered]@{}
    foreach ($h in @($Hedefler | Select-Object -Unique)) {
        $olcum = Invoke-HttpsOlcum $h
        $sonuc[$h] = $olcum.Erisim
        Write-HttpsSonucu $olcum
    }
    foreach ($k in $Script:KontrolSiteleri) {
        Write-HttpsSonucu (Invoke-HttpsOlcum $k)
    }
    return @($sonuc.Values)
}

function Write-HttpsSonucu($Olcum) {
    $mesaj = "$($Olcum.Alan): $($Olcum.Aciklama)"
    if (-not $Olcum.Erisim) {
        Hata $mesaj
    } elseif ($Olcum.HttpKodu -ge 400) {
        Uyari $mesaj
    } else {
        Basari $mesaj
    }
}

function Get-DurumOzeti {
    $sonuc = [ordered]@{
        SemaSurumu = 1
        Surum = $Script:Surum
        OkumaZamani = (Get-Date).ToUniversalTime().ToString('o')
        Hizmet = 'Unknown'
        Baslangic = $null
        Duraklatildi = $null
        Profil = $null
        Genel = $null
        AyarOkundu = $false
        SonOlcum = $null
        Uyarilar = @()
        Hatalar = @()
    }
    try {
        $hizmet = Get-GdpiHizmetBilgisi
        if ($hizmet) {
            $sonuc.Hizmet = [string]$hizmet.State
            $sonuc.Baslangic = [string]$hizmet.StartMode
            $sonuc.Duraklatildi = $hizmet.StartMode -eq 'Disabled'
        } else {
            $sonuc.Hizmet = 'NotInstalled'
            $sonuc.Duraklatildi = $false
        }
    } catch {
        $sonuc.Hatalar += 'Hizmet bilgisi okunamadı.'
    }
    $uyarilar = New-Object 'System.Collections.Generic.List[string]'
    try {
        $ayar = Read-Ayarlar $uyarilar
        if ($ayar) {
            Get-HizmetKomutu $ayar | Out-Null
            $sonuc.Profil = [string]$ayar.profil
            $sonuc.Genel = [bool]$ayar.genel
            $sonuc.AyarOkundu = $true
        }
    } catch {
        $sonuc.Hatalar += 'Kaydedilmiş ayarlar okunamadı veya doğrulanamadı.'
    }
    try {
        $olcumler = @(Read-OlcumGecmisi $uyarilar)
        if ($olcumler.Count -gt 0) { $sonuc.SonOlcum = $olcumler[$olcumler.Count - 1] }
    } catch {
        $sonuc.Hatalar += 'Ölçüm geçmişi okunamadı.'
    }
    $sonuc.Uyarilar = @($uyarilar.ToArray())
    return [pscustomobject]$sonuc
}

function Invoke-Durum {
    Baslik 'Durum'
    $h = Get-Hizmet $Script:HizmetAdi
    $duraklatilmis = $h -and (Get-GdpiHizmetBilgisi).StartMode -eq 'Disabled'
    if ($h) { Yaz "  Hizmet: $($h.Status)" } else { Yaz '  Hizmet: kurulu değil' }
    if ($duraklatilmis) { Yaz '  Otomatik başlatma: duraklatıldı' }
    $g = Get-ScheduledTask -TaskName $Script:GorevAdi -ErrorAction SilentlyContinue
    if ($g) {
        $bilgi = $g | Get-ScheduledTaskInfo
        Yaz "  Bekçi: $($g.State), son çalışma $($bilgi.LastRunTime)"
    } else { Yaz '  Bekçi: kurulu değil' }
    $ayar = Read-Ayarlar
    if ($ayar) {
        Yaz "  Profil: $($ayar.profil)  ($($ayar.arg))"
        if ($ayar.iss) { Yaz "  İSS:    $($ayar.iss) (AS$($ayar.asn))" }
        if ($ayar.dns) {
            $v6 = if ($ayar.dns.V6Etkin) { ', IPv6 dahil' } else { '' }
            Yaz "  DNS:    $($ayar.dns.Ad) $($ayar.dns.V4):$($ayar.dns.Port)$v6"
        } else { Yaz '  DNS:    yönlendirme yok' }
        if ($ayar.genel) { Yaz '  Kapsam: tüm trafik' } else { Yaz '  Kapsam: yalnızca listedeki alan adları' }
        if (Test-Path $Script:GunlukDosyasi) {
            Yaz '  Bekçi günlüğü (son 5):'
            Get-Content $Script:GunlukDosyasi -Tail 5 -Encoding UTF8 | ForEach-Object { Yaz "    $_" 'DarkGray' }
        }
        if (-not $duraklatilmis) { Invoke-Test -Hedefler @($ayar.hedefler) | Out-Null }
    }
}

# Yerel ve gizlilik korumalı teşhis: ağ istekleri, servis değişikliği veya log dökümü yok.
# Rapor; IP, DNS sunucu adresi, hedef alan adları, kullanıcı adı ve mutlak yol içermez.
function Get-TaniRapor {
    $ayar = $null
    $ayarGecerli = $true
    try { $ayar = Read-Ayarlar } catch { $ayarGecerli = $false }

    $hizmet = Get-Hizmet $Script:HizmetAdi
    $gorev = Get-ScheduledTask -TaskName $Script:GorevAdi -ErrorAction SilentlyContinue
    $listeYolu = Join-Path $Script:KurulumDizini 'liste.txt'
    $listeSayisi = $null
    if (Test-Path $listeYolu) {
        $listeSayisi = @(Get-Content $listeYolu -Encoding ASCII | Where-Object { $_.Trim() }).Count
    }
    $gunlukVar = Test-Path $Script:GunlukDosyasi

    $hizmetDurumu = 'NotInstalled'
    if ($hizmet) { $hizmetDurumu = [string]$hizmet.Status }
    $gorevDurumu = 'NotInstalled'
    if ($gorev) { $gorevDurumu = [string]$gorev.State }

    $profil = $null
    $dnsSaglayici = $null
    $kapsam = $null
    if ($ayar) {
        $profil = [string]$ayar.profil
        if ($ayar.dns) { $dnsSaglayici = [string]$ayar.dns.Ad }
        $kapsam = if ($ayar.genel) { 'all-traffic' } else { 'domain-list' }
    }

    return [pscustomobject][ordered]@{
        reportSchemaVersion = 1
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        applicationVersion = $Script:Surum
        architecture = Get-Mimari
        installationPresent = (Test-Path $Script:KurulumDizini)
        serviceStatus = $hizmetDurumu
        watchdogStatus = $gorevDurumu
        configurationReadable = [bool]$ayarGecerli
        configurationPresent = [bool]$ayar
        selectedProfile = $profil
        scope = $kapsam
        dnsProviderName = $dnsSaglayici
        activeDomainCount = $listeSayisi
        watchdogLogPresent = [bool]$gunlukVar
    }
}

function Invoke-Rapor {
    # Kullanıcının geçici klasörüne yazar; SYSTEM veya yönetici yetkisi gerektirmez.
    $ad = 'GoodbyeDPI-TR-rapor-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $hedef = Join-Path ([IO.Path]::GetTempPath()) $ad
    Get-TaniRapor | ConvertTo-Json -Depth 4 | Set-Content -Path $hedef -Encoding UTF8
    Basari "Teşhis raporu oluşturuldu: $hedef"
    Uyari 'Raporun içinde IP adresleri, hedef siteler veya ham günlükler bulunmaz.'
}

function Invoke-Doktor {
    Baslik 'Doktor'
    if (Test-Yonetici) { Basari 'Yönetici yetkisi var' } else { Hata 'Yönetici yetkisi yok' }

    $mimari = Get-Mimari
    if ($mimari) { Basari "Mimari: $mimari" } else { Hata "Mimari desteklenmiyor: $env:PROCESSOR_ARCHITECTURE (WinDivert ARM64'te çalışmaz)" }

    if (Get-Curl) { Basari 'Windows curl.exe mevcut' } else { Hata 'Windows curl.exe yok (Windows 10 1803+ gerekir)' }

    $catisanlar = @(
        @{ Ad = 'Kaspersky';        Surec = @('avp', 'avpui');            Hizmet = @('AVP*', 'klif') }
        @{ Ad = 'Avast/AVG';        Surec = @('AvastSvc', 'AVGSvc');      Hizmet = @('aswSP', 'avgSP') }
        @{ Ad = 'zapret';           Surec = @('winws');                   Hizmet = @('winws1', 'zapret') }
        @{ Ad = 'ByeDPI';           Surec = @('ciadpi');                  Hizmet = @('ByeDPI') }
        @{ Ad = 'WireSock';         Surec = @('wiresock-client');         Hizmet = @('wiresock-client-service') }
        @{ Ad = 'ProxiFyre';        Surec = @('ProxiFyre');               Hizmet = @('ProxiFyre') }
        @{ Ad = 'Eski GoodbyeDPI';  Surec = @();                          Hizmet = @('GoodbyeDPI') }
    )
    $bulundu = $false
    foreach ($c in $catisanlar) {
        $var = @($c.Surec | ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue }) +
               @($c.Hizmet | ForEach-Object { Get-Service -Name $_ -ErrorAction SilentlyContinue })
        if ($var | Where-Object { $_ }) { Uyari "$($c.Ad) bulundu: GoodbyeDPI ile çakışabilir"; $bulundu = $true }
    }
    foreach ($s in Get-YabanciGdpiSurecleri) { Uyari "Hizmet dışı goodbyedpi.exe çalışıyor (PID $($s.Id), $($s.Path))"; $bulundu = $true }
    if (-not $bulundu) { Basari 'Çakışan yazılım bulunmadı' }

    $wd = Get-Hizmet 'WinDivert'
    if ($wd) { Yaz "  WinDivert sürücüsü: $($wd.Status)" }

    $vpn = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'TAP|WireGuard|Wintun|VPN|TUN' }
    foreach ($v in $vpn) { Uyari "Etkin VPN bağdaştırıcısı: $($v.Name) ($($v.InterfaceDescription))" }

    if (Test-GenelIPv6) { Yaz '  IPv6: genel adres var' } else { Yaz '  IPv6: genel adres yok' }
    $dnsler = Get-DnsClientServerAddress -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses }
    foreach ($d in $dnsler) { Yaz "  DNS [$($d.InterfaceAlias)]: $($d.ServerAddresses -join ', ')" }

    $doh = Find-Doh
    if ($doh) { Basari "DoH erişilebilir: $doh" } else { Hata 'Hiçbir DoH sunucusuna ulaşılamıyor' }
    foreach ($k in $Script:KontrolSiteleri) { if (Test-Https $k) { Basari "$k açılıyor" } else { Hata "$k açılmıyor" } }
}

function Update-Liste {
    # Önce kaynağı ve birleşik listeyi ayrı dosyalarda doğrula. Bir hata varsa etkin
    # listeye dokunma; hizmet başlangıcı başarısızsa eski dosyaları geri yükle.
    $hedef = Join-Path $Script:KurulumDizini 'listeler\turkiye.txt'
    if (-not (Test-Path (Split-Path $hedef))) { throw 'GoodbyeDPI-TR kurulu değil.' }
    $oncekiTls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $icerik = (Invoke-WebRequest -Uri $Script:ListeUrl -UseBasicParsing -TimeoutSec 15).Content
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $oncekiTls
    }
    $alanlar = @($icerik -split "`r?`n" | ForEach-Object { ($_ -replace '#.*$', '').Trim().ToLowerInvariant() } | Where-Object { $_ })
    $gecersiz = @($alanlar | Where-Object { -not (Test-AlanAdi $_) })
    if ($gecersiz.Count -gt 0 -or $alanlar.Count -lt 3 -or $alanlar.Count -gt 5000) {
        throw "İndirilen liste geçersiz ($($alanlar.Count) satır, $($gecersiz.Count) hatalı); güncellenmedi."
    }
    $eski = ''
    if (Test-Path -LiteralPath $hedef) { $eski = (Get-Content -LiteralPath $hedef -Raw -Encoding UTF8) -replace "`r", '' }
    if ($eski.Trim() -eq ($icerik -replace "`r", '').Trim()) { return $false }

    $ayar = Read-Ayarlar
    $ekler = @(); if ($ayar) { $ekler = @($ayar.hedefler) }
    $hizmet = Get-Hizmet $Script:HizmetAdi
    if ($hizmet -and $hizmet.Status -notin 'Running', 'Stopped') {
        throw "Hizmet kararlı bir durumda değil ($($hizmet.Status)); liste güncellenmedi."
    }
    $calisiyordu = $hizmet -and $hizmet.Status -eq 'Running'
    $yenidenBaslat = $calisiyordu -and (Get-GdpiHizmetBilgisi).StartMode -ne 'Disabled'
    if ($calisiyordu -and -not $yenidenBaslat) {
        throw 'Duraklatılan hizmet hâlâ çalışıyor; liste güncellenmedi.'
    }

    $kimlik = [Guid]::NewGuid().ToString('N')
    $birlesik = Join-Path $Script:KurulumDizini 'liste.txt'
    $dosyalar = foreach ($yol in $hedef, $birlesik) {
        [pscustomobject]@{
            Hedef = $yol
            Gecici = "$yol.$kimlik.tmp"
            Yedek = "$yol.$kimlik.bak"
            Degisti = $false
        }
    }
    $durdurmaDenendi = $false
    $yedekleriTut = $false
    try {
        [IO.File]::WriteAllText($dosyalar[0].Gecici, $icerik.TrimEnd(), [Text.Encoding]::UTF8)
        $kaynaklar = @(Get-ListeDosyalari $Script:KurulumDizini | Where-Object { $_ -ne $hedef })
        $kaynaklar += $dosyalar[0].Gecici
        Write-Liste $kaynaklar $ekler $dosyalar[1].Gecici | Out-Null
        if ($yenidenBaslat) {
            $durdurmaDenendi = $true
            Stop-Hizmet $Script:HizmetAdi
            if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Stopped' 2)) { throw 'Hizmet durdurulamadı.' }
        }
        foreach ($dosya in $dosyalar) {
            if ([IO.Directory]::Exists($dosya.Hedef)) {
                throw "Liste dosyası yerine klasör var: $($dosya.Hedef)"
            }
            if ([IO.File]::Exists($dosya.Hedef)) {
                [IO.File]::Replace($dosya.Gecici, $dosya.Hedef, $dosya.Yedek)
            } else {
                [IO.File]::Move($dosya.Gecici, $dosya.Hedef)
            }
            $dosya.Degisti = $true
        }
        if ($yenidenBaslat) {
            Start-Service $Script:HizmetAdi
            if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Running')) { throw 'Yeni listeyle hizmet başlatılamadı.' }
        }
    } catch {
        $ilkHata = $_
        try {
            $degisenler = @($dosyalar | Where-Object { $_.Degisti -or [IO.File]::Exists($_.Yedek) })
            if ($durdurmaDenendi -and $degisenler) {
                Stop-Hizmet $Script:HizmetAdi
                if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Stopped' 2)) { throw 'Geri alma için hizmet durdurulamadı.' }
            }
            foreach ($dosya in $degisenler) {
                if ([IO.File]::Exists($dosya.Yedek)) {
                    if ([IO.File]::Exists($dosya.Hedef)) {
                        [IO.File]::Replace($dosya.Yedek, $dosya.Hedef, [NullString]::Value)
                    } else {
                        [IO.File]::Move($dosya.Yedek, $dosya.Hedef)
                    }
                } else {
                    [IO.File]::Delete($dosya.Hedef)
                }
            }
            if ($durdurmaDenendi -and (Get-Hizmet $Script:HizmetAdi).Status -ne 'Running') {
                Start-Service $Script:HizmetAdi
                if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Running')) { throw 'Hizmet önceki listeyle başlatılamadı.' }
            }
        } catch {
            $yedekleriTut = $true
            throw "Liste güncellenemedi: $($ilkHata.Exception.Message) Geri alma başarısız: $($_.Exception.Message)"
        }
        throw $ilkHata
    } finally {
        foreach ($dosya in $dosyalar) {
            $temizlenecek = @($dosya.Gecici)
            if (-not $yedekleriTut) { $temizlenecek += $dosya.Yedek }
            foreach ($yol in $temizlenecek) {
                if ([IO.File]::Exists($yol)) {
                    try { [IO.File]::Delete($yol) } catch { Uyari "Geçici dosya silinemedi: $yol" }
                }
            }
        }
    }
    return $true
}

function Invoke-ListeGuncelle {
    Baslik 'Liste güncelleme'
    if (Update-Liste) { Basari 'Liste güncellendi. Hizmet çalışıyorsa yeniden başlatıldı.' } else { Basari 'Liste zaten güncel.' }
}

function Invoke-Bekci {
    # Bekçi görevi tarafından çalıştırılır. Sessizdir, bekci.log'a yazar.
    $Script:Sessiz = $true
    $hizmet = Get-Hizmet $Script:HizmetAdi
    if (-not $hizmet -or (Get-GdpiHizmetBilgisi).StartMode -eq 'Disabled') { return }
    $ayar = Read-Ayarlar
    if (-not $ayar) { return }
    $durum = Read-BekciDurumu
    # Yalnızca bekçinin kendisinin durdurduğu hizmeti otomatik kurtar.
    if ($hizmet.Status -eq 'Stopped' -and -not $durum.durduruldu) { return }
    if ($hizmet.Status -ne 'Running' -and $durum.durduruldu -and $durum.durdurmaNedeni -eq 'internet' -and
        -not (Test-SureGecti $durum.durduruldu $Script:YenidenBulAraligi)) { return }
    $kaydet = { Save-Json $durum $Script:BekciDosyasi }
    $kontrolAlani = $Script:KontrolSiteleri[0]

    # 0) Ağ hiç yoksa (modem kopuyor, Wi-Fi değişiyor) hiçbir şeye dokunma; sonraki denetimi bekle.
    if (-not (Test-AgVar)) {
        Yaz 'Ağ bağlantısı yok; değişiklik yapılmadı.'
        return
    }

    # 1) Yönlendirilen DNS sunucusu hâlâ yanıt veriyor mu? Vermiyorsa tüm DNS çöker.
    #    Tek bir kayıp paket yüzünden sunucu değiştirilmesin diye üç kez denenir.
    if ($ayar.dns -and -not (Test-DnsSunucusu $ayar.dns @($kontrolAlani) 3)) {
        Yaz "DNS sunucusu yanıt vermiyor: $($ayar.dns.Ad)"
        $yeni = Find-DnsSunucusu @($kontrolAlani)
        if ($yeni) {
            $ayar.dns = $yeni
            Update-HizmetKomutu $ayar
            $durum.durduruldu = $null
            $durum.durdurmaNedeni = $null
            Yaz "DNS değiştirildi: $($yeni.Ad)"
        } else {
            Stop-Hizmet $Script:HizmetAdi
            $durum.durduruldu = (Get-Date).ToString('s'); $durum.durdurmaNedeni = 'dns'; & $kaydet
            Yaz 'Hiçbir DNS sunucusuna ulaşılamıyor; internet kesilmesin diye hizmet durduruldu.'
            return
        }
    }

    # 2) Durdurulmuş hizmeti yeniden aç. DNS yüzünden durdurulduysa DNS şu an çalıştığı için
    #    hemen; hizmet interneti bozduğu için durdurulduysa bekleme süresi dolunca.
    $h = Get-Hizmet $Script:HizmetAdi
    if ($h.Status -ne 'Running') {
        # Neden bilinmiyorsa (1.1.0'dan kalan kayıt) açılır; interneti bozarsa 3. adım yeniden durdurur.
        Start-Service $Script:HizmetAdi
        if (-not (Wait-HizmetDurumu $Script:HizmetAdi 'Running')) { throw 'Hizmet yeniden başlatılamadı.' }
        Start-Sleep -Seconds 3
        if ($durum.durduruldu) { Yaz 'Hizmet yeniden başlatıldı.' }
        $durum.durduruldu = $null; $durum.durdurmaNedeni = $null
    }

    # 3) Hizmet genel interneti bozuyor mu?
    if (-not (Test-Internet)) {
        Stop-Hizmet $Script:HizmetAdi
        Start-Sleep -Seconds 2
        if (-not (Test-Internet)) {
            Start-Service $Script:HizmetAdi -ErrorAction SilentlyContinue
            Yaz 'İnternet yok (hizmetten bağımsız); bekleniyor.'
            & $kaydet
            return
        }
        Yaz 'Hizmet interneti bozuyordu; durduruldu.'
        $durum.durduruldu = (Get-Date).ToString('s'); $durum.durdurmaNedeni = 'internet'
        $durum.ardisikHata = 99   # yeniden profil aramayı tetikle
    }

    # 4) Hedefler açılıyor mu? Üst üste iki kez açılmazsa (en çok 6 saatte bir) profili yeniden bul.
    if (-not $durum.durduruldu) {
        $sonuc = Test-Hedefler @($ayar.hedefler)
        if ($sonuc.Values -contains $false) { $durum.ardisikHata = [int]$durum.ardisikHata + 1 } else { $durum.ardisikHata = 0 }
    }
    if ([int]$durum.ardisikHata -ge 2 -and (Test-SureGecti $durum.sonYenidenBul $Script:YenidenBulAraligi)) {
        Yaz 'Hedefler açılmıyor; profil yeniden aranıyor.'
        $durum.sonYenidenBul = (Get-Date).ToString('s'); & $kaydet
        $yeni = Invoke-Bul -Hedefler @($ayar.hedefler) -Genel:([bool]$ayar.genel) -Kaydetme
        if ($yeni) {
            # Hizmet bekçi tarafından durdurulmuşsa (durduruldu) yeniden başlatmak için her durumda uygulanır.
            if (-not $durum.durduruldu -and (Test-AyniAyar $ayar $yeni)) {
                Yaz 'Profil yeniden arandı; mevcut profil ve DNS korundu, hizmet yeniden başlatılmadı.'
            } else {
                Update-HizmetKomutu $yeni
                Yaz "Yeni profil uygulandı: $($yeni.profil)"
            }
            $durum.ardisikHata = 0
            $durum.durduruldu = $null
            $durum.durdurmaNedeni = $null
        }
    }

    # 5) Başarılı güncellemeden sonra günde bir dene. Hata olursa bir saat sonra yeniden
    # dene; başarısız isteği son başarılı güncelleme olarak kaydetme.
    if ((Test-SureGecti $durum.sonListe (New-TimeSpan -Days 1)) -and
        (Test-SureGecti $durum.sonListeDeneme (New-TimeSpan -Hours 1))) {
        $durum.sonListeDeneme = (Get-Date).ToString('s')
        try {
            if (Update-Liste) { Yaz 'Alan adı listesi güncellendi.' }
            $durum.sonListe = (Get-Date).ToString('s')
        } catch {
            Yaz "Liste güncellenemedi; bir saat sonra yeniden denenecek: $($_.Exception.Message)"
        }
    }
    & $kaydet
}

function Invoke-KilitliIslem([scriptblock]$Islem, [switch]$Bekci) {
    # Kilit kurulum dizininin dışında kalır; kaldırma işlemi de aynı kilidi tutar.
    $yol = $Script:KurulumDizini + '.lock'
    try {
        $kilit = [IO.File]::Open($yol, 'OpenOrCreate', 'ReadWrite', 'None')
    } catch [IO.IOException] {
        $kod = $_.Exception.GetBaseException().HResult -band 0xFFFF
        if ($kod -notin 32, 33) { throw }
        if ($Bekci) { return }
        throw 'Başka bir GoodbyeDPI-TR işlemi devam ediyor. Tamamlandıktan sonra yeniden deneyin.'
    }
    try {
        & $Islem
    } finally {
        $kilit.Dispose()
    }
}

function Show-Menu {
    while ($true) {
        Yaz ''
        Yaz "GoodbyeDPI-TR $Script:Surum" 'Cyan'
        Yaz '  1) Çalışan ayarı bul ve kur (önerilen)'
        Yaz '  2) Yalnızca çalışan ayarı bul'
        Yaz '  3) Durum ve erişim testi'
        Yaz '  4) Doktor (sorun tarama)'
        Yaz '  5) Engelli site listesini güncelle'
        Yaz '  6) Tamamen kaldır'
        Yaz '  7) Eski GoodbyeDPI hizmetini de kaldır'
        Yaz '  8) Duraklat'
        Yaz '  9) Devam et'
        Yaz '  10) Gizlilik korumalı teşhis raporu oluştur'
        Yaz '  11) Bağlantı süresi ölçümü'
        Yaz '  0) Çıkış'
        $s = Read-Host 'Seçim'
        try {
            switch ($s) {
                '1' { Invoke-KilitliIslem { Invoke-Kur -Hedefler $Script:Hedefler -YenidenBul } }
                '2' { Invoke-KilitliIslem { Invoke-Bul -Hedefler $Script:Hedefler | Out-Null } }
                '3' { Invoke-Durum }
                '4' { Invoke-Doktor }
                '5' { Invoke-KilitliIslem { Invoke-ListeGuncelle } }
                '6' { Invoke-KilitliIslem { Invoke-Kaldir } }
                '7' { Invoke-KilitliIslem { Invoke-Kaldir -Eski } }
                '8' { Invoke-KilitliIslem { Invoke-Duraklat } }
                '9' { Invoke-KilitliIslem { Invoke-Devam } }
                '10' { Invoke-Rapor }
                '11' { Invoke-Hiz -Hedefler $Script:Hedefler | Out-Null }
                '0' { return }
            }
        } catch {
            Hata $_.Exception.Message
        }
    }
}

# --- Giriş ----------------------------------------------------------------

function Main {
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $hedefVerildi = [bool]$Hedef
    $Script:Hedefler = $Hedef
    if (-not $Script:Hedefler) { $Script:Hedefler = $Script:VarsayilanHedefler }

    if ($Json) {
        if ($Komut -ne 'durum') {
            [Console]::Error.WriteLine('-Json yalnızca durum komutunda kullanılabilir.')
            exit 1
        }
        Get-DurumOzeti | ConvertTo-Json -Depth 5
        return
    }

    if (($Komut -notin @('test', 'rapor', 'hiz') -or ($Komut -eq 'hiz' -and $AB)) -and -not (Test-Yonetici)) {
        Hata 'Bu araç yönetici olarak çalıştırılmalı (GoodbyeDPI-TR.cmd dosyasını kullanın).'
        exit 1
    }
    try {
        switch ($Komut) {
            'menu'   { Show-Menu }
            'bul'    { Invoke-KilitliIslem { Invoke-Bul -Hedefler $Script:Hedefler -Genel:$Genel | Out-Null } }
            # -Genel veya -Hedef verildiyse kayıtlı ayar yerine yeniden aranır.
            'kur'    { Invoke-KilitliIslem { Invoke-Kur -Hedefler $Script:Hedefler -Genel:$Genel -YenidenBul:($Genel -or $hedefVerildi) } }
            'kaldir' { Invoke-KilitliIslem { Invoke-Kaldir -Eski:$Eski } }
            'durum'  { Invoke-Durum }
            'duraklat' { Invoke-KilitliIslem { Invoke-Duraklat } }
            'devam' { Invoke-KilitliIslem { Invoke-Devam } }
            'doktor' { Invoke-Doktor }
            'rapor'  { Invoke-Rapor }
            'test'   { Invoke-Test -Hedefler $Script:Hedefler | Out-Null }
            'hiz'    {
                if (@($Kaydet, $Gecmis, $DnsSirala, $Oneriler, $AB, $Indirme | Where-Object { $_ }).Count -gt 1) {
                    throw '-Kaydet, -Gecmis, -DnsSirala, -Oneriler, -AB ve -Indirme birlikte kullanılamaz.'
                }
                if ($IndirmeUrl -and -not $Indirme) {
                    throw '-IndirmeUrl yalnızca -Indirme ile birlikte kullanılabilir.'
                }
                if ($Indirme) {
                    Invoke-IndirmeHiz -Adresler $IndirmeUrl -Tekrar $Tekrar | Out-Null
                } elseif ($AB) {
                    Invoke-KilitliIslem { Invoke-HizAb -Hedefler $Script:Hedefler -Tekrar $Tekrar | Out-Null }
                } elseif ($Oneriler) {
                    Invoke-Oneriler | Out-Null
                } elseif ($DnsSirala) {
                    Invoke-DnsSiralamasi -Hedefler $Script:Hedefler | Out-Null
                } elseif ($Gecmis) {
                    Invoke-OlcumGecmisi
                } else {
                    $ozetler = Invoke-Hiz -Hedefler $Script:Hedefler -Tekrar $Tekrar
                    if ($Kaydet) { Save-HizOlcumu $ozetler $Tekrar | Out-Null }
                }
            }
            'liste-guncelle' { Invoke-KilitliIslem { Invoke-ListeGuncelle } }
            'bekci'  { Invoke-KilitliIslem { Invoke-Bekci } -Bekci }
        }
    } catch {
        Hata $_.Exception.Message
        exit 1
    }
}

# Testler dot-source ettiğinde Main çalışmasın.
if ($MyInvocation.InvocationName -ne '.') { Main }
