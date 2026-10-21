<#
  GoodbyeDPI-TR — Türkiye için GoodbyeDPI kurulum ve yönetim aracı.

  Orijinal GoodbyeDPI-Turkey fork'unun sorunlarını giderir:
    - Hileler tüm trafiğe değil, yalnızca listedeki alan adlarına uygulanır
      (oyunlar, bankalar, devlet siteleri bozulmaz).
    - İSS'ine göre çalışan profili ve DNS sunucusunu kendisi bulur.
    - Kurulumdan sonra interneti test eder; bozulursa geri alır.
    - Sabit bir klasöre kurulur, tam olarak kaldırılır.
    - GoodbyeDPI ikili dosyalarını resmi kaynaktan indirip SHA256 ile doğrular.

  Kullanım (yönetici PowerShell):
    .\gdpi-tr.ps1              menü
    .\gdpi-tr.ps1 bul          çalışan profili ve DNS'i bul
    .\gdpi-tr.ps1 kur          bulunan ayarla hizmet olarak kur
    .\gdpi-tr.ps1 kaldir [-Eski]  tamamen kaldır (-Eski: eski GoodbyeDPI hizmetini de)
    .\gdpi-tr.ps1 durum        hizmet ve erişim durumu
    .\gdpi-tr.ps1 doktor       çakışan yazılım ve sorun taraması
    .\gdpi-tr.ps1 test         hedef siteleri test et
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('menu', 'bul', 'kur', 'kaldir', 'durum', 'doktor', 'test')]
    [string]$Komut = 'menu',
    [switch]$Eski,
    [switch]$Genel,
    [string[]]$Hedef
)

$ErrorActionPreference = 'Stop'

# --- Sabitler -------------------------------------------------------------

$Script:Surum = '1.0.0'
$Script:HizmetAdi = 'GoodbyeDPI-TR'
$Script:KurulumDizini = Join-Path $env:ProgramFiles 'GoodbyeDPI-TR'
$Script:VeriDizini = Join-Path $env:ProgramData 'GoodbyeDPI-TR'
$Script:AyarDosyasi = Join-Path $Script:VeriDizini 'ayarlar.json'
$Script:KaynakDizini = $PSScriptRoot

# Resmi ValdikSS/GoodbyeDPI sürümü. Hash bu zip için elle doğrulandı.
$Script:Paket = @{
    Url    = 'https://github.com/ValdikSS/GoodbyeDPI/releases/download/0.2.3rc3/goodbyedpi-0.2.3rc3-2.zip'
    Sha256 = '37F96B32D050DADCC930A639EBA68E1CCD57ED5C04A5F77DFCA908F01905A4C5'
    Klasor = 'goodbyedpi-0.2.3rc3-2'
}

# Engelli olduğu bilinen test hedefleri ve engelsiz kontrol siteleri.
$Script:VarsayilanHedefler = @('discord.com', 'www.roblox.com')
$Script:KontrolSiteleri = @('www.google.com', 'www.turkiye.gov.tr')

# Güvenliden riskliye sıralı. --set-ttl içerenler siteleri bozabildiği için sonda.
$Script:Profiller = @(
    @{ Ad = 'modern-9';       Arg = '-9' }
    @{ Ad = 'modern-7';       Arg = '-7' }
    @{ Ad = 'modern-6';       Arg = '-6' }
    @{ Ad = 'modern-8';       Arg = '-8' }
    @{ Ad = 'modern-5';       Arg = '-5' }
    @{ Ad = 'sni-bolme';      Arg = '-e 2 --frag-by-sni --reverse-frag --wrong-chksum --max-payload -q' }
    @{ Ad = 'ttl-3';          Arg = '--set-ttl 3' }
    @{ Ad = 'superonline-3';  Arg = '-3 --set-ttl 4' }
    @{ Ad = 'fork-varsayilan'; Arg = '-5 --set-ttl 5' }
)

# Standart dışı portta dinleyen genel DNS sunucuları (İSS'ler 53'ü yakalıyor).
$Script:DnsAdaylari = @(
    # Türk Telekom hattında 2026-10 itibarıyla doğrulandı; AdGuard 5353 ve OpenDNS 5353 yanıt vermiyor.
    @{ Ad = 'Quad9 (filtresiz)'; V4 = '9.9.9.10';       V6 = '2620:fe::10';        Port = 9953 }
    @{ Ad = 'OpenDNS';           V4 = '208.67.222.222'; V6 = '2620:119:35::35';    Port = 443 }
    @{ Ad = 'Yandex';            V4 = '77.88.8.8';      V6 = '2a02:6b8::feed:0ff'; Port = 1253 }
)

# Türkiye'deki erişim engeli sayfasının adres bloğu.
$Script:EngelBloklari = @('195.175.254.')

# --- Yardımcılar ----------------------------------------------------------

function Yaz([string]$Metin, [string]$Renk = 'Gray') { Write-Host $Metin -ForegroundColor $Renk }
function Basari([string]$Metin) { Yaz "  [+] $Metin" 'Green' }
function Uyari([string]$Metin) { Yaz "  [!] $Metin" 'Yellow' }
function Hata([string]$Metin) { Yaz "  [x] $Metin" 'Red' }
function Baslik([string]$Metin) { Yaz ''; Yaz "== $Metin ==" 'Cyan' }

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

function Read-Ayarlar {
    if (Test-Path $Script:AyarDosyasi) {
        return Get-Content $Script:AyarDosyasi -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return $null
}

function Save-Ayarlar($Ayarlar) {
    New-Item -ItemType Directory -Force -Path $Script:VeriDizini | Out-Null
    $Ayarlar | ConvertTo-Json -Depth 5 | Set-Content -Path $Script:AyarDosyasi -Encoding UTF8
}

# --- Liste ----------------------------------------------------------------

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
        if ($Dns.V6) { $parca.Add("--dnsv6-addr $($Dns.V6) --dnsv6-port $($Dns.Port)") }
    }
    return ($parca -join ' ')
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

function Read-DnsCevabi([byte[]]$Veri) {
    # A kayıtlarının IPv4 adreslerini döndürür.
    if ($Veri.Length -lt 12) { return @() }
    $soru = ($Veri[4] -shl 8) -bor $Veri[5]
    $cevap = ($Veri[6] -shl 8) -bor $Veri[7]
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
        $tip = ($Veri[$i] -shl 8) -bor $Veri[$i + 1]
        $uzunluk = ($Veri[$i + 8] -shl 8) -bor $Veri[$i + 9]
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
    $istemci = New-Object System.Net.Sockets.UdpClient
    try {
        $istemci.Client.ReceiveTimeout = $ZamanAsimiMs
        $sorgu = New-DnsSorgusu $Alan
        [void]$istemci.Send($sorgu, $sorgu.Length, $Sunucu, $Port)
        $uc = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        return Read-DnsCevabi ($istemci.Receive([ref]$uc))
    } catch {
        return @()
    } finally {
        $istemci.Close()
    }
}

function Find-DnsSunucusu([string[]]$Hedefler) {
    foreach ($aday in $Script:DnsAdaylari) {
        $tamam = $true
        foreach ($h in $Hedefler) {
            $ipler = Resolve-UdpDns $aday.V4 $aday.Port $h
            if (-not $ipler -or (Test-EngelAdresi $ipler)) { $tamam = $false; break }
        }
        if ($tamam) { return $aday }
        Uyari "$($aday.Ad) ($($aday.V4):$($aday.Port)) kullanılamıyor"
    }
    return $null
}

# --- Bağlantı testi -------------------------------------------------------

function Test-Https([string]$Alan, [switch]$DoH, [int]$Sure = 8) {
    # Hedefe HTTPS bağlantısı kurulabiliyor mu? DoH ile DNS engelini devre dışı bırakıp
    # yalnızca DPI'ı ölçer.
    $curl = Get-Curl
    if (-not $curl) { throw 'Windows curl.exe bulunamadı (Windows 10 1803+ gerekir).' }
    $arg = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--connect-timeout', '5', '-m', "$Sure", "https://$Alan/")
    if ($DoH) { $arg = @('--doh-url', 'https://1.1.1.1/dns-query') + $arg }
    $kod = & $curl @arg 2>$null
    return ($LASTEXITCODE -eq 0 -and $kod -match '^[1-5]\d\d$' -and $kod -ne '000')
}

function Test-Hedefler([string[]]$Hedefler, [switch]$DoH) {
    $sonuc = [ordered]@{}
    foreach ($h in $Hedefler) { $sonuc[$h] = Test-Https $h -DoH:$DoH }
    return $sonuc
}

# --- İkili dosyalar -------------------------------------------------------

function Get-Ikililer {
    # Resmi zip'i indirir, hash'ini doğrular, mimariye uygun klasörü döndürür.
    $mimari = Get-Mimari
    if (-not $mimari) { throw 'Bu işlemci mimarisi desteklenmiyor. WinDivert sürücüsünün ARM64 sürümü yok.' }
    $onbellek = Join-Path $Script:VeriDizini 'onbellek'
    $zip = Join-Path $onbellek 'goodbyedpi.zip'
    $acik = Join-Path $onbellek $Script:Paket.Klasor
    New-Item -ItemType Directory -Force -Path $onbellek | Out-Null

    $gecerli = (Test-Path $zip) -and ((Get-FileHash $zip -Algorithm SHA256).Hash -eq $Script:Paket.Sha256)
    if (-not $gecerli) {
        Yaz "  GoodbyeDPI resmi sürümü indiriliyor..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Script:Paket.Url -OutFile $zip -UseBasicParsing
        $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
        if ($hash -ne $Script:Paket.Sha256) {
            Remove-Item $zip -Force
            throw "İndirilen dosyanın hash'i tutmuyor ($hash). Dosya değiştirilmiş olabilir, kurulum durduruldu."
        }
        if (Test-Path $acik) { Remove-Item $acik -Recurse -Force }
    }
    if (-not (Test-Path $acik)) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $onbellek)
    }
    $bin = Join-Path $acik $mimari
    if (-not (Test-Path (Join-Path $bin 'goodbyedpi.exe'))) { throw "goodbyedpi.exe bulunamadı: $bin" }
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

function Remove-Hizmet([string]$Ad) {
    $h = Get-Hizmet $Ad
    if (-not $h) { return $false }
    if ($h.Status -ne 'Stopped') { & sc.exe stop $Ad | Out-Null; Start-Sleep -Seconds 2 }
    & sc.exe delete $Ad | Out-Null
    return $true
}

function Get-WinDivertKullanicilari {
    # WinDivert'i kullanan diğer araçlar (sürücüyü bunlar açıkken kaldırmamak için).
    $adlar = @('goodbyedpi', 'winws', 'zapret', 'SplitWire-Turkey')
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $adlar -contains $_.ProcessName })
}

function Remove-WinDivert {
    if (Get-WinDivertKullanicilari) {
        Uyari 'WinDivert başka bir araç tarafından kullanılıyor, sürücüye dokunulmadı.'
        return
    }
    foreach ($ad in @('WinDivert', 'WinDivert1.4', 'WinDivert14')) {
        if (Get-Hizmet $ad) {
            & sc.exe stop $ad | Out-Null
            & sc.exe delete $ad | Out-Null
            Basari "$ad sürücüsü kaldırıldı"
        }
    }
}

# --- Komutlar -------------------------------------------------------------

function Invoke-Bul {
    param([string[]]$Hedefler, [switch]$Genel)
    Baslik 'Çalışan ayar aranıyor'

    $kontrolTamam = $false
    foreach ($k in $Script:KontrolSiteleri) { if (Test-Https $k) { $kontrolTamam = $true; break } }
    if (-not $kontrolTamam) { throw 'İnternet bağlantısı yok (kontrol sitelerine ulaşılamadı). Önce bağlantınızı kontrol edin.' }

    $bin = Get-Ikililer
    $exe = Join-Path $bin 'goodbyedpi.exe'
    $liste = Write-Liste (Get-ListeDosyalari $Script:KaynakDizini) $Hedefler (Join-Path $Script:VeriDizini 'deneme-liste.txt')

    # 1) DNS: İSS DNS'i engelli adresi mi veriyor?
    Yaz '  DNS sunucusu seçiliyor...'
    $dns = Find-DnsSunucusu $Hedefler
    if ($dns) { Basari "DNS: $($dns.Ad) ($($dns.V4):$($dns.Port))" }
    else { Uyari 'Standart dışı porttaki DNS sunucularına ulaşılamadı, DNS yönlendirmesi kapalı kalacak.' }

    # 2) DPI: DoH ile DNS'ten bağımsız ölç.
    $once = Test-Hedefler $Hedefler -DoH
    $engelli = @($once.Keys | Where-Object { -not $once[$_] })
    if (-not $engelli) {
        Basari 'Hedefler GoodbyeDPI olmadan da açılıyor. DPI engeli yok, yalnızca DNS yönlendirmesi kullanılacak.'
        $secilen = $Script:Profiller[0]
    } else {
        Yaz "  DPI engeli olan hedefler: $($engelli -join ', ')"
        $secilen = $null
        foreach ($p in $Script:Profiller) {
            $arg = Get-GdpiArgumanlari -Profil $p.Arg -ListeDosyalari $liste -Genel:$Genel
            Yaz "  Deneniyor: $($p.Ad)  ($($p.Arg))" 'DarkGray'
            $surec = $null
            try {
                $surec = Start-GdpiGecici $exe $arg
                $sonuc = Test-Hedefler $engelli -DoH
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

    $ayar = [ordered]@{
        surum   = $Script:Surum
        profil  = $secilen.Ad
        arg     = $secilen.Arg
        dns     = $dns
        genel   = [bool]$Genel
        hedefler = $Hedefler
        tarih   = (Get-Date).ToString('s')
    }
    Save-Ayarlar $ayar
    Basari "Ayarlar kaydedildi: $Script:AyarDosyasi"
    return $ayar
}

function Invoke-Kur {
    param([switch]$Genel, [string[]]$Hedefler)
    $ayar = Read-Ayarlar
    if (-not $ayar) { $ayar = Invoke-Bul -Hedefler $Hedefler -Genel:$Genel; if (-not $ayar) { return } }
    Baslik 'Kurulum'

    $eski = Get-Hizmet 'GoodbyeDPI'
    if ($eski) { Uyari "Eski 'GoodbyeDPI' hizmeti çalışıyor; çakışmaması için kaldırılıyor."; Remove-Hizmet 'GoodbyeDPI' | Out-Null }
    Remove-Hizmet $Script:HizmetAdi | Out-Null

    $bin = Get-Ikililer
    $hedefBin = Join-Path $Script:KurulumDizini 'bin'
    $hedefListe = Join-Path $Script:KurulumDizini 'listeler'
    New-Item -ItemType Directory -Force -Path $hedefBin, $hedefListe | Out-Null
    Copy-Item (Join-Path $bin '*') $hedefBin -Force
    Get-ListeDosyalari $Script:KaynakDizini | ForEach-Object { Copy-Item $_ $hedefListe -Force }
    if ($PSCommandPath -ne (Join-Path $Script:KurulumDizini 'gdpi-tr.ps1')) {
        Copy-Item $PSCommandPath (Join-Path $Script:KurulumDizini 'gdpi-tr.ps1') -Force
    }

    $liste = Write-Liste (Get-ListeDosyalari $Script:KurulumDizini) @($ayar.hedefler) (Join-Path $Script:KurulumDizini 'liste.txt')
    $arg = Get-GdpiArgumanlari -Profil $ayar.arg -Dns $ayar.dns -ListeDosyalari $liste -Genel:([bool]$ayar.genel)
    $exe = Join-Path $hedefBin 'goodbyedpi.exe'

    # sc.exe yerine New-Service: PowerShell 5.1 yerel komutlara gömülü tırnakları bozuyor.
    New-Service -Name $Script:HizmetAdi -BinaryPathName "`"$exe`" $arg" -DisplayName 'GoodbyeDPI-TR' `
        -StartupType Automatic -Description 'Türkiye için DPI atlatma. Kaldırmak için: gdpi-tr.ps1 kaldir' | Out-Null
    & sc.exe failure $Script:HizmetAdi reset= 86400 actions= restart/5000/restart/30000// | Out-Null
    & sc.exe start $Script:HizmetAdi | Out-Null
    Start-Sleep -Seconds 3

    # Bekçi: genel internet bozulduysa geri al.
    $kontrol = $false
    foreach ($k in $Script:KontrolSiteleri) { if (Test-Https $k) { $kontrol = $true; break } }
    if (-not $kontrol) {
        Hata 'Kurulumdan sonra internet çalışmadı. Değişiklik geri alınıyor.'
        Remove-Hizmet $Script:HizmetAdi | Out-Null
        Remove-WinDivert
        Yaz '  "doktor" komutuyla çakışan yazılımları kontrol edin (Kaspersky, Avast vb.).'
        return
    }
    Basari "Hizmet kuruldu ve çalışıyor ($($ayar.profil))."
    Invoke-Test -Hedefler @($ayar.hedefler)
}

function Invoke-Kaldir {
    param([switch]$Eski)
    Baslik 'Kaldırma'
    if (Remove-Hizmet $Script:HizmetAdi) { Basari "$Script:HizmetAdi hizmeti kaldırıldı" } else { Yaz '  GoodbyeDPI-TR hizmeti yok.' }
    if ($Eski -and (Remove-Hizmet 'GoodbyeDPI')) { Basari 'Eski GoodbyeDPI hizmeti kaldırıldı' }
    Start-Sleep -Seconds 1
    Remove-WinDivert
    foreach ($d in @($Script:KurulumDizini, $Script:VeriDizini)) {
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
}

function Invoke-Durum {
    Baslik 'Durum'
    $h = Get-Hizmet $Script:HizmetAdi
    if ($h) { Yaz "  Hizmet: $($h.Status)" } else { Yaz '  Hizmet: kurulu değil' }
    $ayar = Read-Ayarlar
    if ($ayar) {
        Yaz "  Profil: $($ayar.profil)  ($($ayar.arg))"
        if ($ayar.dns) { Yaz "  DNS:    $($ayar.dns.Ad) $($ayar.dns.V4):$($ayar.dns.Port)" } else { Yaz '  DNS:    yönlendirme yok' }
        if ($ayar.genel) { Yaz '  Kapsam: tüm trafik' } else { Yaz '  Kapsam: yalnızca listedeki alan adları' }
        Invoke-Test -Hedefler @($ayar.hedefler)
    }
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
    if (-not $bulundu) { Basari 'Çakışan yazılım bulunmadı' }

    $wd = Get-Hizmet 'WinDivert'
    if ($wd) { Yaz "  WinDivert sürücüsü: $($wd.Status)" }

    $vpn = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'TAP|WireGuard|Wintun|VPN|TUN' }
    foreach ($v in $vpn) { Uyari "Etkin VPN bağdaştırıcısı: $($v.Name) ($($v.InterfaceDescription))" }

    $dnsler = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses }
    foreach ($d in $dnsler) { Yaz "  DNS [$($d.InterfaceAlias)]: $($d.ServerAddresses -join ', ')" }

    foreach ($k in $Script:KontrolSiteleri) { if (Test-Https $k) { Basari "$k açılıyor" } else { Hata "$k açılmıyor" } }
}

function Show-Menu {
    while ($true) {
        Yaz ''
        Yaz "GoodbyeDPI-TR $Script:Surum" 'Cyan'
        Yaz '  1) Çalışan ayarı bul ve kur (önerilen)'
        Yaz '  2) Yalnızca çalışan ayarı bul'
        Yaz '  3) Durum ve erişim testi'
        Yaz '  4) Doktor (sorun tarama)'
        Yaz '  5) Tamamen kaldır'
        Yaz '  6) Eski GoodbyeDPI-Turkey dahil tamamen kaldır'
        Yaz '  0) Çıkış'
        $s = Read-Host 'Seçim'
        try {
            switch ($s) {
                '1' { if (Invoke-Bul -Hedefler $Script:Hedefler) { Invoke-Kur -Hedefler $Script:Hedefler } }
                '2' { Invoke-Bul -Hedefler $Script:Hedefler | Out-Null }
                '3' { Invoke-Durum }
                '4' { Invoke-Doktor }
                '5' { Invoke-Kaldir }
                '6' { Invoke-Kaldir -Eski }
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
    $Script:Hedefler = $Hedef
    if (-not $Script:Hedefler) { $Script:Hedefler = $Script:VarsayilanHedefler }

    if ($Komut -ne 'test' -and -not (Test-Yonetici)) {
        Hata 'Bu araç yönetici olarak çalıştırılmalı (GoodbyeDPI-TR.cmd dosyasını kullanın).'
        exit 1
    }
    try {
        switch ($Komut) {
            'menu'   { Show-Menu }
            'bul'    { Invoke-Bul -Hedefler $Script:Hedefler -Genel:$Genel | Out-Null }
            'kur'    { Invoke-Kur -Hedefler $Script:Hedefler -Genel:$Genel }
            'kaldir' { Invoke-Kaldir -Eski:$Eski }
            'durum'  { Invoke-Durum }
            'doktor' { Invoke-Doktor }
            'test'   { Invoke-Test -Hedefler $Script:Hedefler }
        }
    } catch {
        Hata $_.Exception.Message
        exit 1
    }
}

# Testler dot-source ettiğinde Main çalışmasın.
if ($MyInvocation.InvocationName -ne '.') { Main }
