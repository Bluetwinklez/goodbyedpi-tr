<#
.SYNOPSIS
  GoodbyeDPI-TR Windows VM sürüm kapısı için salt okunur kanıt ve güvenlik doğrulama betiği.
.DESCRIPTION
  Kurulum öncesi, kurulum sonrası ve 24 saatlik bekçi gözlemi aşamalarında sistem durumunu,
  klasör/hizmet ACL'lerini, reparse point/junction durumunu, rapor gizliliğini ve bekci.log
  özetini hiçbir ayarı değiştirmeden toplar; JSON ve Markdown kanıt dosyası üretir.
#>
[CmdletBinding()]
param(
    [ValidateSet('oncesi', 'sonrasi', 'bekci24s')]
    [string]$Asama = 'sonrasi',
    [string]$KurulumDizini = (Join-Path $env:ProgramFiles 'GoodbyeDPI-TR'),
    [string]$GdpiBetigi = '',
    [string]$CiktiDizini = '',
    [ValidateRange(1, 720)]
    [int]$SaatPenceresi = 24
)

$ErrorActionPreference = 'Stop'

$Script:VmHizmetAdi = 'GoodbyeDPI-TR'
$Script:VmGorevAdi = 'GoodbyeDPI-TR Bekci'

function Test-AclNesnesiGuvenli {
    param(
        [Parameter(Mandatory)]
        [string]$Yol,
        $AccessRules
    )
    $riskliKimlikler = @(
        'BUILTIN\Users',
        'NT AUTHORITY\Authenticated Users',
        'NT AUTHORITY\INTERACTIVE',
        'Everyone',
        'S-1-1-0',
        'S-1-5-11',
        'S-1-5-4',
        'S-1-5-32-545'
    )
    $yazmaMaskesi = (
        [System.Security.AccessControl.FileSystemRights]::WriteData -bor
        [System.Security.AccessControl.FileSystemRights]::AppendData -bor
        [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
        [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [System.Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [System.Security.AccessControl.FileSystemRights]::Delete -bor
        [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [System.Security.AccessControl.FileSystemRights]::TakeOwnership
    )
    $riskler = [System.Collections.Generic.List[string]]::new()
    foreach ($kural in @($AccessRules)) {
        if (-not $kural) { continue }
        if ([string]$kural.AccessControlType -ne 'Allow') { continue }
        $kimlik = [string]$kural.IdentityReference
        $eslesti = $false
        foreach ($hedef in $riskliKimlikler) {
            if ($kimlik -ieq $hedef -or $kimlik -like "*\$hedef") {
                $eslesti = $true
                break
            }
        }
        if (-not $eslesti) { continue }
        $hak = [int]$kural.FileSystemRights
        if (($hak -band [int]$yazmaMaskesi) -ne 0) {
            $riskler.Add("$kimlik -> $($kural.FileSystemRights)")
        }
    }
    [pscustomobject]@{
        Yol            = $Yol
        Var            = $true
        Guvenli        = ($riskler.Count -eq 0)
        RiskliKurallar = @($riskler)
    }
}

function Test-DizinAclGuvenli {
    param([Parameter(Mandatory)][string]$Yol)
    if (-not (Test-Path -LiteralPath $Yol)) {
        return [pscustomobject]@{
            Yol            = $Yol
            Var            = $false
            Guvenli        = $null
            RiskliKurallar = @()
        }
    }
    $acl = Get-Acl -LiteralPath $Yol
    return (Test-AclNesnesiGuvenli -Yol $Yol -AccessRules $acl.Access)
}

function Test-ReparseNoktasi {
    param([Parameter(Mandatory)][string]$KokYol)
    if (-not (Test-Path -LiteralPath $KokYol)) {
        return [pscustomobject]@{
            KokYol   = $KokYol
            Var      = $false
            Guvenli  = $null
            Bulunan  = @()
        }
    }
    $bulunan = [System.Collections.Generic.List[string]]::new()
    $kokOge = Get-Item -LiteralPath $KokYol -Force
    if (($kokOge.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $bulunan.Add($kokOge.FullName)
    }
    Get-ChildItem -LiteralPath $KokYol -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $bulunan.Add($_.FullName)
        }
    }
    [pscustomobject]@{
        KokYol  = $KokYol
        Var     = $true
        Guvenli = ($bulunan.Count -eq 0)
        Bulunan = @($bulunan)
    }
}

function Test-HizmetSddlGuvenli {
    param([string]$Sddl)
    if (-not $Sddl -or -not $Sddl.Trim()) {
        return [pscustomobject]@{
            Okundu         = $false
            Guvenli        = $null
            RiskliKurallar = @()
        }
    }
    $riskliSidler = @('BU', 'AU', 'WD', 'IU', 'S-1-1-0', 'S-1-5-11', 'S-1-5-4', 'S-1-5-32-545')
    $riskliHaklar = @('DC', 'WD', 'WO', 'GA', 'GW', 'GX', 'RP', 'WP', 'SD')
    $riskler = [System.Collections.Generic.List[string]]::new()
    $eslesmeler = [regex]::Matches($Sddl, '\(([^()]+)\)')
    foreach ($m in $eslesmeler) {
        $parca = $m.Groups[1].Value -split ';'
        if ($parca.Count -lt 6) { continue }
        $tip = $parca[0]
        $hakMetni = $parca[2]
        $sid = $parca[5]
        if ($tip -ne 'A') { continue }
        if ($riskliSidler -notcontains $sid) { continue }
        $bulunanHak = @()
        for ($i = 0; $i + 1 -lt $hakMetni.Length; $i += 2) {
            $kod = $hakMetni.Substring($i, 2)
            if ($riskliHaklar -contains $kod) { $bulunanHak += $kod }
        }
        if ($bulunanHak.Count -gt 0) {
            $riskler.Add("$sid -> $($bulunanHak -join ',')")
        }
    }
    [pscustomobject]@{
        Okundu         = $true
        Guvenli        = ($riskler.Count -eq 0)
        RiskliKurallar = @($riskler)
    }
}

function Get-BekciGunlukOzeti {
    param(
        [string[]]$Satirlar,
        [int]$SaatPenceresi = 24,
        [datetime]$ReferansZamani = (Get-Date)
    )
    $esik = $ReferansZamani.AddHours(-$SaatPenceresi)
    $ozet = [ordered]@{
        SaatPenceresi          = $SaatPenceresi
        ToplamSatir            = 0
        PenceredekiSatir       = 0
        DnsDegisimi            = 0
        HizmetYenidenBaslatma  = 0
        HizmetDurdurma         = 0
        ProfilDegisimi         = 0
        ProfilKorundu          = 0
        AgYok                  = 0
        ListeGuncelleme        = 0
        ListeHatasi            = 0
        ChurnUyari             = $false
    }
    foreach ($satir in @($Satirlar)) {
        if (-not $satir) { continue }
        $ozet.ToplamSatir++
        $dahil = $true
        if ($satir -match '^\[(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2})\]') {
            try {
                $ts = [datetime]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
                if ($ts -lt $esik) { $dahil = $false }
            } catch {
                $dahil = $true
            }
        }
        if (-not $dahil) { continue }
        $ozet.PenceredekiSatir++
        if ($satir -match 'DNS değiştirildi:') { $ozet.DnsDegisimi++ }
        if ($satir -match 'Hizmet yeniden başlatıldı\.') { $ozet.HizmetYenidenBaslatma++ }
        if ($satir -match 'Yeni profil uygulandı:') { $ozet.ProfilDegisimi++ }
        if ($satir -match 'hizmet durduruldu|Hizmet interneti bozuyordu; durduruldu') { $ozet.HizmetDurdurma++ }
        if ($satir -match 'mevcut profil ve DNS korundu, hizmet yeniden başlatılmadı') { $ozet.ProfilKorundu++ }
        if ($satir -match 'Ağ bağlantısı yok') { $ozet.AgYok++ }
        if ($satir -match 'Alan adı listesi güncellendi') { $ozet.ListeGuncelleme++ }
        if ($satir -match 'Liste güncellenemedi') { $ozet.ListeHatasi++ }
    }
    $ozet.ChurnUyari = ($ozet.DnsDegisimi -gt 0 -or $ozet.HizmetYenidenBaslatma -gt 0 -or $ozet.ProfilDegisimi -gt 0)
    return [pscustomobject]$ozet
}

function Test-RaporGizlilik {
    param([string]$RaporJson)
    if (-not $RaporJson -or -not $RaporJson.Trim()) {
        return [pscustomobject]@{
            Okundu  = $false
            Guvenli = $null
            Bulgular = @()
        }
    }
    $bulgular = [System.Collections.Generic.List[string]]::new()
    if ($RaporJson -match '(?i)[A-Z]:\\+Users\\+') { $bulgular.Add('Kullanıcı dizin yolu sızıntısı tespit edildi.') }
    if ($RaporJson -match '(?i)[A-Z]:\\+Program Files') { $bulgular.Add('Tam kurulum yolu sızıntısı tespit edildi.') }
    if ($RaporJson -match '\b(?:\d{1,3}\.){3}\d{1,3}\b') { $bulgular.Add('Ham IPv4 adresi tespit edildi.') }
    try {
        $null = $RaporJson | ConvertFrom-Json
    } catch {
        $bulgular.Add('Rapor geçerli JSON değil.')
    }
    [pscustomobject]@{
        Okundu   = $true
        Guvenli  = ($bulgular.Count -eq 0)
        Bulgular = @($bulgular)
    }
}

function Get-HizmetSddlMetni {
    param([string]$HizmetAdi = $Script:VmHizmetAdi)
    $sc = Join-Path ([Environment]::SystemDirectory) 'sc.exe'
    $cikti = & $sc sdshow $HizmetAdi 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $cikti) { return $null }
    return (($cikti | Where-Object { $_ -and $_.Trim() }) -join '').Trim()
}

function Invoke-VmVerify {
    param(
        [string]$Asama = 'sonrasi',
        [string]$KurulumDizini = (Join-Path $env:ProgramFiles 'GoodbyeDPI-TR'),
        [string]$GdpiBetigi = '',
        [string]$CiktiDizini = '',
        [int]$SaatPenceresi = 24
    )
    $veriDizini = Join-Path $KurulumDizini 'veri'
    $gunlukYolu = Join-Path $veriDizini 'bekci.log'
    $hizmet = Get-Service -Name $Script:VmHizmetAdi -ErrorAction SilentlyContinue
    $gorev = $null
    try { $gorev = Get-ScheduledTask -TaskName $Script:VmGorevAdi -ErrorAction SilentlyContinue } catch { $gorev = $null }

    $sddlMetni = if ($hizmet) { Get-HizmetSddlMetni -HizmetAdi $Script:VmHizmetAdi } else { $null }
    $gunlukSatirlari = if (Test-Path -LiteralPath $gunlukYolu) { Get-Content -LiteralPath $gunlukYolu -Encoding UTF8 -ErrorAction SilentlyContinue } else { @() }

    $durumJson = $null
    $raporJson = $null
    if ($GdpiBetigi -and (Test-Path -LiteralPath $GdpiBetigi -PathType Leaf)) {
        $psExe = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
        try {
            $durumJson = (& $psExe -NoProfile -ExecutionPolicy Bypass -File $GdpiBetigi durum -Json 2>$null) -join "`n"
        } catch {
            $durumJson = $null
        }
        try {
            $raporJson = (& $psExe -NoProfile -ExecutionPolicy Bypass -File $GdpiBetigi rapor 2>$null) -join "`n"
        } catch {
            $raporJson = $null
        }
    }

    $sonuc = [pscustomobject]@{
        Zaman         = (Get-Date).ToUniversalTime().ToString('o')
        Asama         = $Asama
        PowerShell    = $PSVersionTable.PSVersion.ToString()
        Yonetici      = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Hizmet        = if ($hizmet) { [pscustomobject]@{ Var = $true; Durum = [string]$hizmet.Status } } else { [pscustomobject]@{ Var = $false; Durum = 'Yok' } }
        Gorev         = if ($gorev) { [pscustomobject]@{ Var = $true; Durum = [string]$gorev.State } } else { [pscustomobject]@{ Var = $false; Durum = 'Yok' } }
        KurulumAcl    = Test-DizinAclGuvenli -Yol $KurulumDizini
        VeriAcl       = Test-DizinAclGuvenli -Yol $veriDizini
        Reparse       = Test-ReparseNoktasi -KokYol $KurulumDizini
        HizmetSddl    = Test-HizmetSddlGuvenli -Sddl $sddlMetni
        BekciGunlugu  = Get-BekciGunlukOzeti -Satirlar $gunlukSatirlari -SaatPenceresi $SaatPenceresi
        RaporGizlilik = Test-RaporGizlilik -RaporJson $raporJson
        DurumJsonVar  = [bool]($durumJson -and $durumJson.Trim())
    }

    if ($CiktiDizini) {
        if (-not (Test-Path -LiteralPath $CiktiDizini)) {
            New-Item -ItemType Directory -Path $CiktiDizini -Force | Out-Null
        }
        $damga = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $temelAd = "vm-verify-$Asama-$damga"
        $jsonYol = Join-Path $CiktiDizini "$temelAd.json"
        $mdYol = Join-Path $CiktiDizini "$temelAd.md"
        $sonuc | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonYol -Encoding UTF8

        $md = @(
            "# GoodbyeDPI-TR VM Doğrulama Raporu ($Asama)"
            ""
            "- **Zaman (UTC):** $($sonuc.Zaman)"
            "- **PowerShell:** $($sonuc.PowerShell)"
            "- **Yönetici:** $($sonuc.Yonetici)"
            "- **Hizmet:** $($sonuc.Hizmet.Durum)"
            "- **Bekçi Görevi:** $($sonuc.Gorev.Durum)"
            "- **Kurulum ACL Güvenli:** $($sonuc.KurulumAcl.Guvenli)"
            "- **Veri ACL Güvenli:** $($sonuc.VeriAcl.Guvenli)"
            "- **Reparse/Junction Temiz:** $($sonuc.Reparse.Guvenli)"
            "- **Hizmet SDDL Güvenli:** $($sonuc.HizmetSddl.Guvenli)"
            "- **Rapor Gizlilik Güvenli:** $($sonuc.RaporGizlilik.Guvenli)"
            "- **Bekçi Son $($sonuc.BekciGunlugu.SaatPenceresi) Saat:** DNS değişimi=$($sonuc.BekciGunlugu.DnsDegisimi), Yeniden başlatma=$($sonuc.BekciGunlugu.HizmetYenidenBaslatma), Profil değişimi=$($sonuc.BekciGunlugu.ProfilDegisimi), Churn uyarısı=$($sonuc.BekciGunlugu.ChurnUyari)"
        )
        $md -join "`r`n" | Set-Content -LiteralPath $mdYol -Encoding UTF8
    }

    return $sonuc
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-VmVerify -Asama $Asama -KurulumDizini $KurulumDizini -GdpiBetigi $GdpiBetigi -CiktiDizini $CiktiDizini -SaatPenceresi $SaatPenceresi
}

