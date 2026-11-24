# Pester 3.4 / 4.10.1 uyumlu: Invoke-Pester .\tests
. (Join-Path $PSScriptRoot '..\scripts\vm-verify.ps1')

Describe 'Test-AclNesnesiGuvenli' {
    It 'yalnızca yönetici/SYSTEM yazma ve Users salt okuma iznini güvenli sayar' {
        $kurallar = @(
            [pscustomobject]@{ IdentityReference = 'NT AUTHORITY\SYSTEM'; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl }
            [pscustomobject]@{ IdentityReference = 'BUILTIN\Administrators'; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::FullControl }
            [pscustomobject]@{ IdentityReference = 'BUILTIN\Users'; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute }
        )
        $r = Test-AclNesnesiGuvenli -Yol 'C:\Program Files\GoodbyeDPI-TR' -AccessRules $kurallar
        $r.Guvenli | Should Be $true
        $r.RiskliKurallar.Count | Should Be 0
    }

    It 'standart kullanıcılara veya Everyone grubuna yazma iznini riskli işaretler' {
        $kurallar = @(
            [pscustomobject]@{ IdentityReference = 'BUILTIN\Users'; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Modify }
            [pscustomobject]@{ IdentityReference = 'Everyone'; AccessControlType = 'Allow'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::WriteData }
        )
        $r = Test-AclNesnesiGuvenli -Yol 'C:\Program Files\GoodbyeDPI-TR\veri' -AccessRules $kurallar
        $r.Guvenli | Should Be $false
        $r.RiskliKurallar.Count | Should Be 2
    }

    It 'Deny kuralını yazma riski olarak saymaz' {
        $kurallar = @(
            [pscustomobject]@{ IdentityReference = 'BUILTIN\Users'; AccessControlType = 'Deny'; FileSystemRights = [System.Security.AccessControl.FileSystemRights]::Write }
        )
        $r = Test-AclNesnesiGuvenli -Yol 'C:\Program Files\GoodbyeDPI-TR' -AccessRules $kurallar
        $r.Guvenli | Should Be $true
    }
}

Describe 'Test-HizmetSddlGuvenli' {
    It 'standart sertleştirilmiş Windows hizmet SDDL dizgesini güvenli sayar' {
        $sddl = 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)'
        $r = Test-HizmetSddlGuvenli -Sddl $sddl
        $r.Okundu | Should Be $true
        $r.Guvenli | Should Be $true
        $r.RiskliKurallar.Count | Should Be 0
    }

    It 'standart kullanıcılara hizmet değiştirme izni veren SDDL dizgesini riskli sayar' {
        $sddl = 'D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;DCWP;;;BU)(A;;GA;;;WD)'
        $r = Test-HizmetSddlGuvenli -Sddl $sddl
        $r.Okundu | Should Be $true
        $r.Guvenli | Should Be $false
        $r.RiskliKurallar.Count | Should Be 2
    }

    It 'boş SDDL için Okundu false döner' {
        $r = Test-HizmetSddlGuvenli -Sddl ''
        $r.Okundu | Should Be $false
        $r.Guvenli | Should BeNullOrEmpty
    }
}

Describe 'Get-BekciGunlukOzeti' {
    It 'sabit 24 saatlik günlükte gereksiz değişim yoksa ChurnUyari false döner' {
        $ref = [datetime]'2026-11-24T12:00:00'
        $satirlar = @(
            '[2026-11-24 02:00:00] Ağ bağlantısı yok; değişiklik yapılmadı.'
            '[2026-11-24 06:00:00] Profil yeniden arandı; mevcut profil ve DNS korundu, hizmet yeniden başlatılmadı.'
            '[2026-11-24 08:00:00] Alan adı listesi güncellendi.'
        )
        $o = Get-BekciGunlukOzeti -Satirlar $satirlar -SaatPenceresi 24 -ReferansZamani $ref
        $o.PenceredekiSatir | Should Be 3
        $o.AgYok | Should Be 1
        $o.ProfilKorundu | Should Be 1
        $o.ListeGuncelleme | Should Be 1
        $o.DnsDegisimi | Should Be 0
        $o.HizmetYenidenBaslatma | Should Be 0
        $o.ChurnUyari | Should Be $false
    }

    It 'pencere içindeki DNS değişimi ve yeniden başlatmayı sayar, pencere dışını dışlar' {
        $ref = [datetime]'2026-11-24T12:00:00'
        $satirlar = @(
            '[2026-11-22 10:00:00] DNS değiştirildi: OpenDNS'
            '[2026-11-24 09:00:00] DNS değiştirildi: Quad9 (filtresiz)'
            '[2026-11-24 09:05:00] Hizmet yeniden başlatıldı.'
        )
        $o = Get-BekciGunlukOzeti -Satirlar $satirlar -SaatPenceresi 24 -ReferansZamani $ref
        $o.ToplamSatir | Should Be 3
        $o.PenceredekiSatir | Should Be 2
        $o.DnsDegisimi | Should Be 1
        $o.HizmetYenidenBaslatma | Should Be 1
        $o.ChurnUyari | Should Be $true
    }
}

Describe 'Test-RaporGizlilik' {
    It 'özel bilgi içermeyen geçerli JSON raporunu güvenli sayar' {
        $json = '{"Surum":"1.2.0","Hizmet":"Running","Profil":"modern-5","AlanSayisi":120}'
        $r = Test-RaporGizlilik -RaporJson $json
        $r.Okundu | Should Be $true
        $r.Guvenli | Should Be $true
    }

    It 'kullanıcı yolu veya ham IP sızıntısını yakalar' {
        $json = '{"Yol":"C:\\Users\\ornek\\Desktop","Ip":"192.168.1.10"}'
        $r = Test-RaporGizlilik -RaporJson $json
        $r.Guvenli | Should Be $false
        $r.Bulgular.Count | Should Be 2
    }

    It 'bozuk JSON metnini reddeder' {
        $r = Test-RaporGizlilik -RaporJson '{bozuk'
        $r.Guvenli | Should Be $false
    }
}

Describe 'Test-ReparseNoktasi ve Invoke-VmVerify' {
    It 'normal dizinde reparse noktası bulmaz ve kanıt dosyalarını yazar' {
        $gecici = Join-Path ([IO.Path]::GetTempPath()) ('gdpi-vmverify-' + [guid]::NewGuid().ToString('N'))
        $kurulum = Join-Path $gecici 'kurulum'
        $cikti = Join-Path $gecici 'cikti'
        try {
            New-Item -ItemType Directory -Path $kurulum -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $kurulum 'ornek.txt') -Value 'test' -Encoding UTF8
            $rp = Test-ReparseNoktasi -KokYol $kurulum
            $rp.Var | Should Be $true
            $rp.Guvenli | Should Be $true

            $sonuc = Invoke-VmVerify -Asama oncesi -KurulumDizini $kurulum -CiktiDizini $cikti
            $sonuc.Asama | Should Be 'oncesi'
            @(Get-ChildItem -LiteralPath $cikti -Filter 'vm-verify-oncesi-*.json').Count | Should Be 1
            @(Get-ChildItem -LiteralPath $cikti -Filter 'vm-verify-oncesi-*.md').Count | Should Be 1
        } finally {
            if (Test-Path -LiteralPath $gecici) { Remove-Item -LiteralPath $gecici -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

