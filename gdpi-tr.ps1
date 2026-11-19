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
    .\gdpi-tr.ps1 doktor          çakışan yazılım ve sorun taraması
    .\gdpi-tr.ps1 rapor           özel bilgileri içermeyen yerel teşhis JSON'u üret
    .\gdpi-tr.ps1 test            hedef siteleri test et
    .\gdpi-tr.ps1 liste-guncelle  engelli alan adı listesini GitHub'dan güncelle
    .\gdpi-tr.ps1 bekci           bekçi görevinin çalıştırdığı denetim (elle gerekmez)
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('menu', 'bul', 'kur', 'kaldir', 'durum', 'doktor', 'test', 'liste-guncelle', 'bekci', 'rapor')]
    [string]$Komut = 'menu',
    [switch]$Eski,
    [switch]$Genel,
    [string[]]$Hedef
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # PS 5.1'de ilerleme çubuğu indirmeyi çok yavaşlatıyor

# --- Sabitler -------------------------------------------------------------

$Script:Surum = '1.1.1'
$Script:HizmetAdi = 'GoodbyeDPI-TR'
$Script:GorevAdi = 'GoodbyeDPI-TR Bekci'
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
    $yol = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $yol) { return $yol }
    return $null
}

function Read-Json([string]$Yol) {
    if (Test-Path $Yol) { return Get-Content $Yol -Raw -Encoding UTF8 | ConvertFrom-Json }
    return $null
}

function Save-Json($Nesne, [string]$Yol) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Yol) | Out-Null
    $Nesne | ConvertTo-Json -Depth 5 | Set-Content -Path $Yol -Encoding UTF8
}

function Read-Ayarlar { return Read-Json $Script:AyarDosyasi }
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
    $org = & $curl -s --connect-timeout 3 -m 5 https://ipinfo.io/org 2>$null
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

function Read-DnsCevabi([byte[]]$Veri, [int]$Kimlik = -1) {
    # A kayıtlarının IPv4 adreslerini döndürür. Kimlik verilirse eşleşmeyen cevap reddedilir.
    # [int] dönüşümleri şart: PowerShell'de byte -shl 8 sonucu byte olarak taşar.
    if ($Veri.Length -lt 12) { return @() }
    if ($Kimlik -ge 0 -and ((([int]$Veri[0] -shl 8) -bor $Veri[1]) -ne $Kimlik)) { return @() }
    $soru = ([int]$Veri[4] -shl 8) -bor $Veri[5]
    $cevap = ([int]$Veri[6] -shl 8) -bor $Veri[7]
    $i = 12
    $atla = {
        param($p)
        while ($p -lt $Veri.Length) {
            $u = $Veri[$p]
            if ($u -eq 0) { return $p + 1 }
            if (($u -band 0xC0) -eq 0xC0) { return $p + 2 }
            $p += $u + 1
        }
        return $p
    }
    for ($q = 0; $q -lt $soru; $q++) { $i = (& $atla $i) + 4 }
    $ipler = @()
    for ($a = 0; $a -lt $cevap -and $i -lt $Veri.Length; $a++) {
        $i = & $atla $i
        if ($i + 10 -gt $Veri.Length) { break }
        $tip = ([int]$Veri[$i] -shl 8) -bor $Veri[$i + 1]
        $uzunluk = ([int]$Veri[$i + 8] -shl 8) -bor $Veri[$i + 9]
        $i += 10
        if ($tip -eq 1 -and $uzunluk -eq 4 -and $i + 4 -le $Veri.Length) {
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
        $kimlik = Get-Random -Minimum 1 -Maximum 65535
        $sorgu = New-DnsSorgusu $Alan ([uint16]$kimlik)
        [void]$istemci.Send($sorgu, $sorgu.Length, (New-Object System.Net.IPEndPoint($adres, $Port)))
        $uc = New-Object System.Net.IPEndPoint($adres, 0)
        return Read-DnsCevabi ($istemci.Receive([ref]$uc)) $kimlik
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

function Test-DnsSunucusu($Aday, [string[]]$Alanlar) {
    foreach ($h in $Alanlar) {
        $ipler = Resolve-UdpDns $Aday.V4 $Aday.Port $h
        if (-not $ipler -or (Test-EngelAdresi $ipler)) { return $false }
    }
    return $true
}

function Find-DnsSunucusu([string[]]$Hedefler) {
    $ipv6 = Test-GenelIPv6
    foreach ($aday in $Script:DnsAdaylari) {
        if (-not (Test-DnsSunucusu $aday $Hedefler)) {
            Uyari "$($aday.Ad) ($($aday.V4):$($aday.Port)) kullanılamıyor"
            continue
        }
        $sonuc = @{ Ad = $aday.Ad; V4 = $aday.V4; V6 = $aday.V6; Port = $aday.Port; V6Etkin = $false }
        if ($ipv6) {
            $ip6 = Resolve-UdpDns $aday.V6 $aday.Port $Hedefler[0]
            $sonuc.V6Etkin = [bool]($ip6 -and -not (Test-EngelAdresi $ip6))
            if (-not $sonuc.V6Etkin) { Uyari "IPv6 DNS ($($aday.V6)) yanıt vermedi; IPv6 DNS yönlendirilmeyecek." }
        }
        return $sonuc
    }
    return $null
}

# --- Bağlantı testi -------------------------------------------------------

function Test-Https([string]$Alan, [string]$DohUrl, [int]$Sure = 8) {
    # Hedefe HTTPS bağlantısı kurulabiliyor mu? DohUrl verilirse DNS engeli devre dışı kalır,
    # yalnızca DPI ölçülür.
    $curl = Get-Curl
    if (-not $curl) { throw 'Windows curl.exe bulunamadı (Windows 10 1803+ gerekir).' }
    $arg = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--connect-timeout', '5', '-m', "$Sure", "https://$Alan/")
    if ($DohUrl) { $arg = @('--doh-url', $DohUrl) + $arg }
    $kod = & $curl @arg 2>$null
    return ($LASTEXITCODE -eq 0 -and $kod -match '^[1-5]\d\d$')
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
    & sc.exe stop $Ad | Out-Null
    if (-not (Wait-HizmetDurumu $Ad 'Stopped')) {
        # Hizmet durmuyorsa süreci zorla kapat.
        $pid_ = (Get-CimInstance Win32_Service -Filter "Name='$Ad'").ProcessId
        if ($pid_) { Stop-Process -Id $pid_ -Force -ErrorAction SilentlyContinue }
        Wait-HizmetDurumu $Ad 'Stopped' 5 | Out-Null
    }
}

function Remove-Hizmet([string]$Ad) {
    if (-not (Get-Hizmet $Ad)) { return $false }
    Stop-Hizmet $Ad
    & sc.exe delete $Ad | Out-Null
    if (-not (Wait-HizmetDurumu $Ad 'Yok')) { Uyari "$Ad hizmeti silinmek üzere işaretlendi; yeniden başlatmadan sonra tamamen kalkacak." }
    return $true
}

function Get-YabanciGdpiSurecleri {
    # Bizim hizmetimize ait olmayan goodbyedpi.exe süreçleri (eski fork'un .cmd pencereleri vb.).
    $bizim = (Get-CimInstance Win32_Service -Filter "Name='$Script:HizmetAdi'" -ErrorAction SilentlyContinue).ProcessId
    return @(Get-Process -Name goodbyedpi -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $bizim })
}

function Get-WinDivertKullanicilari {
    # WinDivert'i kullanan diğer araçlar (sürücüyü bunlar açıkken kaldırmamak için).
    $adlar = @('goodbyedpi', 'winws', 'zapret', 'SplitWire-Turkey')
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $adlar -contains $_.ProcessName })
}

# WinDivert paylaşılan bir sistem sürücüsüdür; sahibini doğrulamadan silinmez.
# GoodbyeDPI-TR kaldırması yalnız kendi hizmetini ve dosyalarını temizler.

function Get-HizmetKomutu($Ayar) {
    $exe = Join-Path $Script:KurulumDizini 'bin\goodbyedpi.exe'
    $liste = Join-Path $Script:KurulumDizini 'liste.txt'
    $arg = Get-GdpiArgumanlari -Profil $Ayar.arg -Dns $Ayar.dns -ListeDosyalari $liste -Genel:([bool]$Ayar.genel)
    return "`"$exe`" $arg"
}

function Update-HizmetKomutu($Ayar) {
    # Kayıt defterine doğrudan yazılır: sc.exe config'e gömülü tırnak geçirmek PS 5.1'de güvenilir değil.
    $anahtar = "HKLM:\SYSTEM\CurrentControlSet\Services\$Script:HizmetAdi"
    Set-ItemProperty -Path $anahtar -Name ImagePath -Value (Get-HizmetKomutu $Ayar)
    Stop-Hizmet $Script:HizmetAdi
    Start-Service $Script:HizmetAdi
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
    return $d
}

function Test-SureGecti($Zaman, [TimeSpan]$Aralik) {
    if (-not $Zaman) { return $true }
    return ((Get-Date) - [datetime]$Zaman) -ge $Aralik
}

# --- Komutlar -------------------------------------------------------------

function Invoke-Bul {
    param([string[]]$Hedefler, [switch]$Genel)
    Baslik 'Çalışan ayar aranıyor'

    # Başka bir aracın hizmetini veya sürecini otomatik durdurma.
    # Bir çakışma varsa kullanıcıya haber ver; yalnız kendi hizmetimizi ölçüm için geçici durdur.
    $hizmetCalisiyordu = $false
    try {
        $eski = Get-Hizmet 'GoodbyeDPI'
        if ($eski -and $eski.Status -eq 'Running') {
            throw "Eski 'GoodbyeDPI' hizmeti çalışıyor. Ölçüm için hizmeti kendiniz durdurun; bu araç başka hizmetleri durdurmaz."
        }
        $yabanci = @(Get-YabanciGdpiSurecleri)
        if ($yabanci.Count -gt 0) {
            throw "Başka bir goodbyedpi.exe çalışıyor (PID: $(($yabanci | ForEach-Object Id) -join ', ')). Önce kendi uygulamasından durdurun; süreçlere dokunulmadı."
        }
        $h = Get-Hizmet $Script:HizmetAdi
        if ($h -and $h.Status -eq 'Running') {
            Yaz '  Ölçüm için yalnız GoodbyeDPI-TR hizmeti geçici olarak durduruluyor...'
            Stop-Hizmet $Script:HizmetAdi
            $hizmetCalisiyordu = $true
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
        $dns = Find-DnsSunucusu $Hedefler
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
            foreach ($p in Get-SiraliProfiller $asn) {
                $arg = Get-GdpiArgumanlari -Profil $p.Arg -ListeDosyalari $liste -Genel:$Genel
                Yaz "  Deneniyor: $($p.Ad)  ($($p.Arg))" 'DarkGray'
                $surec = $null
                try {
                    $surec = Start-GdpiGecici $exe $arg
                    $sonuc = Test-Hedefler $engelli $doh
                    $tumu = -not ($sonuc.Values -contains $false)
                    $kontrol = Test-Https $Script:KontrolSiteleri[0]
                } catch {
                    Uyari $_.Exception.Message
                    $tumu = $false; $kontrol = $false
                } finally {
                    Stop-GdpiGecici $surec
                }
                if ($tumu -and $kontrol) { $secilen = $p; break }
            }
            if (-not $secilen) {
                Hata 'Hiçbir profil engeli aşamadı. İSS IP tabanlı engel uyguluyor olabilir; bu durumda VPN gerekir.'
                return $null
            }
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
        Save-Ayarlar $ayar
        Basari "Ayarlar kaydedildi: $Script:AyarDosyasi"
        return $ayar
    } finally {
        if ($hizmetCalisiyordu -and (Get-Hizmet $Script:HizmetAdi)) { Start-Service $Script:HizmetAdi -ErrorAction SilentlyContinue }
    }
}

function Install-Kisayollar {
    # Başlat menüsü kısayolu ve Programlar ve Özellikler kaydı.
    $cmd = Join-Path $Script:KurulumDizini 'GoodbyeDPI-TR.cmd'
    $kabuk = New-Object -ComObject WScript.Shell
    $k = $kabuk.CreateShortcut($Script:Kisayol)
    $k.TargetPath = $cmd
    $k.WorkingDirectory = $Script:KurulumDizini
    $k.Description = 'GoodbyeDPI-TR menüsü'
    $k.Save()

    New-Item -Path $Script:KaldirmaAnahtari -Force | Out-Null
    $degerler = @{
        DisplayName     = 'GoodbyeDPI-TR'
        DisplayVersion  = $Script:Surum
        Publisher       = 'GoodbyeDPI-TR'
        InstallLocation = $Script:KurulumDizini
        URLInfoAbout    = $Script:ProjeUrl
        UninstallString = "`"$cmd`" kaldir"
    }
    foreach ($ad in $degerler.Keys) { Set-ItemProperty -Path $Script:KaldirmaAnahtari -Name $ad -Value $degerler[$ad] }
    Set-ItemProperty -Path $Script:KaldirmaAnahtari -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty -Path $Script:KaldirmaAnahtari -Name NoRepair -Value 1 -Type DWord
}

function Install-BekciGorevi {
    $ps1 = Join-Path $Script:KurulumDizini 'gdpi-tr.ps1'
    $eylem = New-ScheduledTaskAction -Execute 'powershell.exe' `
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
    $ayar = Read-Ayarlar
    if (-not $ayar -or $YenidenBul) {
        $ayar = Invoke-Bul -Hedefler $Hedefler -Genel:$Genel
        if (-not $ayar) { return }
    }
    Baslik 'Kurulum'

    if (Get-Hizmet 'GoodbyeDPI') {
        throw "Eski 'GoodbyeDPI' hizmeti yüklü. Başka yazılımı otomatik kaldırmıyoruz; önce bu hizmeti kendiniz kaldırın veya 'kaldir -Eski' komutunu bilinçli olarak çalıştırın."
    }
    $yabanci = @(Get-YabanciGdpiSurecleri)
    if ($yabanci.Count -gt 0) {
        throw "Başka bir goodbyedpi.exe çalışıyor (PID: $(($yabanci | ForEach-Object Id) -join ', ')). Kurulum için önce ilgili uygulamadan kapatın."
    }
    Remove-Hizmet $Script:HizmetAdi | Out-Null

    $bin = Get-Ikililer
    $hedefBin = Join-Path $Script:KurulumDizini 'bin'
    $hedefListe = Join-Path $Script:KurulumDizini 'listeler'
    New-Item -ItemType Directory -Force -Path $hedefBin, $hedefListe | Out-Null
    Copy-Item (Join-Path $bin '*') $hedefBin -Force
    if (-not (Test-IkiliHashleri $hedefBin (Get-Mimari))) { throw 'Kopyalanan dosyaların hash doğrulaması başarısız.' }

    if ($Script:KaynakDizini -ne $Script:KurulumDizini) {
        Get-ListeDosyalari $Script:KaynakDizini | ForEach-Object { Copy-Item $_ $hedefListe -Force }
        Copy-Item $PSCommandPath (Join-Path $Script:KurulumDizini 'gdpi-tr.ps1') -Force
        $cmd = Join-Path $Script:KaynakDizini 'GoodbyeDPI-TR.cmd'
        if (Test-Path $cmd) { Copy-Item $cmd $Script:KurulumDizini -Force }
    }

    Write-Liste (Get-ListeDosyalari $Script:KurulumDizini) @($ayar.hedefler) (Join-Path $Script:KurulumDizini 'liste.txt') | Out-Null

    # sc.exe yerine New-Service: PowerShell 5.1 yerel komutlara gömülü tırnakları bozuyor.
    New-Service -Name $Script:HizmetAdi -BinaryPathName (Get-HizmetKomutu $ayar) -DisplayName 'GoodbyeDPI-TR' `
        -StartupType Automatic -Description 'Türkiye için DPI atlatma. Kaldırmak için Başlat menüsünden GoodbyeDPI-TR.' | Out-Null
    & sc.exe failure $Script:HizmetAdi reset= 86400 actions= restart/5000/restart/30000// | Out-Null
    Start-Service $Script:HizmetAdi
    Start-Sleep -Seconds 3

    # Kurulum bekçisi: genel internet bozulduysa geri al.
    if (-not (Test-Internet)) {
        Hata 'Kurulumdan sonra internet çalışmadı. Değişiklik geri alınıyor.'
        Remove-Hizmet $Script:HizmetAdi | Out-Null
        # WinDivert başka yazılımların da olabilir; sistem sürücülerini silme.
        Yaz '  "doktor" komutuyla çakışan yazılımları kontrol edin (Kaspersky, Avast vb.).'
        return
    }

    Install-BekciGorevi
    Install-Kisayollar
    Basari "Hizmet kuruldu ve çalışıyor ($($ayar.profil)). Bekçi görevi her 15 dakikada ve ağ değişiminde denetleyecek."
    $sonuc = Invoke-Test -Hedefler @($ayar.hedefler)
    if ($sonuc -contains $false) {
        Uyari 'Bazı hedefler açılmıyor. Menüden "Çalışan ayarı bul ve kur" seçeneğini tekrar deneyin.'
    }
}

function Invoke-Kaldir {
    param([switch]$Eski)
    Baslik 'Kaldırma'
    if (Get-ScheduledTask -TaskName $Script:GorevAdi -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $Script:GorevAdi -Confirm:$false
        Basari 'Bekçi görevi kaldırıldı'
    }
    if (Remove-Hizmet $Script:HizmetAdi) { Basari "$Script:HizmetAdi hizmeti kaldırıldı" } else { Yaz '  GoodbyeDPI-TR hizmeti yok.' }
    if ($Eski) {
        if (Remove-Hizmet 'GoodbyeDPI') { Basari 'Eski GoodbyeDPI hizmeti kaldırıldı' }
    }
    $yabanci = @(Get-YabanciGdpiSurecleri)
    if ($yabanci.Count -gt 0) {
        Uyari "Diğer goodbyedpi.exe süreçleri çalışmaya devam ediyor (PID: $(($yabanci | ForEach-Object Id) -join ', ')). Bu süreçler otomatik kapatılmadı."
    }
    Start-Sleep -Seconds 1
    Uyari 'Paylaşılan WinDivert sürücüleri kaldırılmadı; başka araçlar bunları kullanıyor olabilir.'
    foreach ($y in @($Script:Kisayol, $Script:KaldirmaAnahtari)) {
        if (Test-Path $y) { Remove-Item $y -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($d in @($Script:KurulumDizini, $Script:EskiVeriDizini)) {
        if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue; Basari "Silindi: $d" }
    }
    Yaz '  DNS ayarlarınıza dokunulmadı; bu araç sistem DNS ayarını değiştirmez.'
}

function Invoke-Test {
    param([string[]]$Hedefler)
    Baslik 'Erişim testi (sistem DNS ile)'
    $sonuc = Test-Hedefler $Hedefler
    foreach ($h in $sonuc.Keys) { if ($sonuc[$h]) { Basari "$h açılıyor" } else { Hata "$h açılmıyor" } }
    foreach ($k in $Script:KontrolSiteleri) { if (Test-Https $k) { Basari "$k (kontrol) açılıyor" } else { Hata "$k (kontrol) açılmıyor" } }
    return @($sonuc.Values)
}

function Invoke-Durum {
    Baslik 'Durum'
    $h = Get-Hizmet $Script:HizmetAdi
    if ($h) { Yaz "  Hizmet: $($h.Status)" } else { Yaz '  Hizmet: kurulu değil' }
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
        Invoke-Test -Hedefler @($ayar.hedefler) | Out-Null
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
    $etkin = Join-Path $Script:KurulumDizini 'liste.txt'
    if (-not (Test-Path $hedef)) { throw 'GoodbyeDPI-TR kurulu değil veya Türkiye listesi bulunamadı.' }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $icerik = [string](Invoke-WebRequest -Uri $Script:ListeUrl -UseBasicParsing -TimeoutSec 15).Content
    $alanlar = @($icerik -split "\r?\n" | ForEach-Object { ($_ -replace '#.*$', '').Trim().ToLowerInvariant() } | Where-Object { $_ })
    $gecersiz = @($alanlar | Where-Object { -not (Test-AlanAdi $_) })
    if ($gecersiz.Count -gt 0 -or $alanlar.Count -lt 3 -or $alanlar.Count -gt 5000) {
        throw "İndirilen liste geçersiz ($($alanlar.Count) satır, $($gecersiz.Count) hatalı); güncellenmedi."
    }
    $eskiIcerik = Get-Content $hedef -Raw -Encoding UTF8
    if (($eskiIcerik -replace '\r', '').Trim() -eq ($icerik -replace '\r', '').Trim()) { return $false }

    $id = [guid]::NewGuid().ToString('N')
    $taslakKaynak = Join-Path $Script:VeriDizini "liste-kaynak-$id.tmp"
    $taslakEtkin = Join-Path $Script:VeriDizini "liste-etkin-$id.tmp"
    $yedekKaynak = Join-Path $Script:VeriDizini "liste-kaynak-$id.bak"
    $yedekEtkin = Join-Path $Script:VeriDizini "liste-etkin-$id.bak"
    $etkinVardi = Test-Path $etkin
    try {
        New-Item -ItemType Directory -Path $Script:VeriDizini -Force | Out-Null
        Set-Content -Path $taslakKaynak -Value $icerik.TrimEnd() -Encoding UTF8

        # Kullanıcı listeleri korunur; yalnız uzak kaynak geçici dosya ile değiştirilir.
        $kaynaklar = @(Get-ListeDosyalari $Script:KurulumDizini | Where-Object { $_ -ne $hedef })
        $kaynaklar += $taslakKaynak
        $ayar = Read-Ayarlar
        $ekler = @()
        if ($ayar -and $ayar.hedefler) { $ekler = @($ayar.hedefler) }
        Write-Liste $kaynaklar $ekler $taslakEtkin | Out-Null

        Copy-Item -Path $hedef -Destination $yedekKaynak -Force
        if ($etkinVardi) { Copy-Item -Path $etkin -Destination $yedekEtkin -Force }
        $hizmet = Get-Hizmet $Script:HizmetAdi
        $calisiyordu = [bool]($hizmet -and $hizmet.Status -eq 'Running')
        try {
            Copy-Item -Path $taslakKaynak -Destination $hedef -Force
            Copy-Item -Path $taslakEtkin -Destination $etkin -Force
            if ($calisiyordu) {
                Stop-Hizmet $Script:HizmetAdi
                Start-Service $Script:HizmetAdi -ErrorAction Stop
            }
        } catch {
            $sebep = $_.Exception.Message
            try {
                Copy-Item -Path $yedekKaynak -Destination $hedef -Force
                if ($etkinVardi) {
                    Copy-Item -Path $yedekEtkin -Destination $etkin -Force
                } elseif (Test-Path $etkin) {
                    Remove-Item $etkin -Force
                }
                if ($calisiyordu) {
                    Stop-Hizmet $Script:HizmetAdi
                    Start-Service $Script:HizmetAdi -ErrorAction Stop
                }
            } catch {
                throw "Liste güncellemesi başarısız; geri yükleme de başarısız: $($_.Exception.Message)"
            }
            throw "Yeni liste uygulanamadı; önceki liste geri yüklendi. Neden: $sebep"
        }
        return $true
    } finally {
        foreach ($dosya in @($taslakKaynak, $taslakEtkin, $yedekKaynak, $yedekEtkin)) {
            Remove-Item -Path $dosya -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ListeGuncelle {
    Baslik 'Liste güncelleme'
    if (Update-Liste) { Basari 'Liste güncellendi ve hizmet yeniden başlatıldı.' } else { Basari 'Liste zaten güncel.' }
}

function Invoke-Bekci {
    # Bekçi görevi tarafından çalıştırılır. Sessizdir, bekci.log'a yazar.
    $Script:Sessiz = $true
    $ayar = Read-Ayarlar
    if (-not $ayar -or -not (Get-Hizmet $Script:HizmetAdi)) { return }
    $durum = Read-BekciDurumu
    $kaydet = { Save-Json $durum $Script:BekciDosyasi }
    $kontrolAlani = $Script:KontrolSiteleri[0]

    # 0) Ağ hiç yoksa (modem kopuyor, Wi-Fi değişiyor) hiçbir şeye dokunma; sonraki denetimi bekle.
    if (-not (Test-AgVar)) {
        Yaz 'Ağ bağlantısı yok; değişiklik yapılmadı.'
        return
    }

    # 1) Yönlendirilen DNS sunucusu hâlâ yanıt veriyor mu? Vermiyorsa tüm DNS çöker.
    if ($ayar.dns -and -not (Test-DnsSunucusu $ayar.dns @($kontrolAlani))) {
        Yaz "DNS sunucusu yanıt vermiyor: $($ayar.dns.Ad)"
        $yeni = Find-DnsSunucusu @($kontrolAlani)
        if ($yeni) {
            $ayar.dns = $yeni
            Save-Ayarlar $ayar
            Update-HizmetKomutu $ayar
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
        $bekle = $durum.durduruldu -and $durum.durdurmaNedeni -eq 'internet' -and
            -not (Test-SureGecti $durum.durduruldu $Script:YenidenBulAraligi)
        if ($bekle) { return }
        Start-Service $Script:HizmetAdi -ErrorAction SilentlyContinue
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
        $yeni = Invoke-Bul -Hedefler @($ayar.hedefler) -Genel:([bool]$ayar.genel)
        if ($yeni) {
            Update-HizmetKomutu $yeni
            $durum.ardisikHata = 0
            $durum.durduruldu = $null
            Yaz "Yeni profil uygulandı: $($yeni.profil)"
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
        Yaz '  7) Eski GoodbyeDPI-Turkey dahil tamamen kaldır'
        Yaz '  8) Gizlilik korumalı teşhis raporu oluştur'
        Yaz '  0) Çıkış'
        $s = Read-Host 'Seçim'
        try {
            switch ($s) {
                '1' { Invoke-Kur -Hedefler $Script:Hedefler -YenidenBul }
                '2' { Invoke-Bul -Hedefler $Script:Hedefler | Out-Null }
                '3' { Invoke-Durum }
                '4' { Invoke-Doktor }
                '5' { Invoke-ListeGuncelle }
                '6' { Invoke-Kaldir }
                '7' { Invoke-Kaldir -Eski }
                '8' { Invoke-Rapor }
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

    if ($Komut -notin @('test', 'rapor') -and -not (Test-Yonetici)) {
        Hata 'Bu araç yönetici olarak çalıştırılmalı (GoodbyeDPI-TR.cmd dosyasını kullanın).'
        exit 1
    }
    try {
        switch ($Komut) {
            'menu'   { Show-Menu }
            'bul'    { Invoke-Bul -Hedefler $Script:Hedefler -Genel:$Genel | Out-Null }
            # -Genel veya -Hedef verildiyse kayıtlı ayar yerine yeniden aranır.
            'kur'    { Invoke-Kur -Hedefler $Script:Hedefler -Genel:$Genel -YenidenBul:($Genel -or $hedefVerildi) }
            'kaldir' { Invoke-Kaldir -Eski:$Eski }
            'durum'  { Invoke-Durum }
            'doktor' { Invoke-Doktor }
            'rapor'  { Invoke-Rapor }
            'test'   { Invoke-Test -Hedefler $Script:Hedefler | Out-Null }
            'liste-guncelle' { Invoke-ListeGuncelle }
            'bekci'  { Invoke-Bekci }
        }
    } catch {
        Hata $_.Exception.Message
        exit 1
    }
}

# Testler dot-source ettiğinde Main çalışmasın.
if ($MyInvocation.InvocationName -ne '.') { Main }
