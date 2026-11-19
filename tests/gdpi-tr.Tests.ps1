# Pester 3.4 (Windows ile gelir):  Invoke-Pester .\tests
. (Join-Path $PSScriptRoot '..\gdpi-tr.ps1')

Describe 'Get-GdpiArgumanlari' {
    It 'liste modunda --blacklist ekler' {
        $a = Get-GdpiArgumanlari -Profil '-9' -ListeDosyalari 'C:\a b\liste.txt'
        $a | Should Be '-9 --blacklist "C:\a b\liste.txt"'
    }
    It 'genel modda listeyi eklemez' {
        Get-GdpiArgumanlari -Profil '-9' -ListeDosyalari 'x.txt' -Genel | Should Be '-9'
    }
    It 'max-payload içermeyen profile ekler' {
        Get-GdpiArgumanlari -Profil '--set-ttl 3' -Genel | Should Be '--set-ttl 3 --max-payload'
    }
    It 'DNS yönlendirmesini ekler' {
        $dns = @{ V4 = '1.2.3.4'; V6 = '::1'; Port = 5353; V6Etkin = $true }
        Get-GdpiArgumanlari -Profil '-5' -Dns $dns -Genel |
            Should Be '-5 --dns-addr 1.2.3.4 --dns-port 5353 --dnsv6-addr ::1 --dnsv6-port 5353'
    }
    It 'test edilmemiş IPv6 DNS yönlendirmesini eklemez' {
        $dns = @{ V4 = '1.2.3.4'; V6 = '::1'; Port = 5353; V6Etkin = $false }
        Get-GdpiArgumanlari -Profil '-5' -Dns $dns -Genel | Should Be '-5 --dns-addr 1.2.3.4 --dns-port 5353'
    }
}

Describe 'Get-SiraliProfiller' {
    It 'bilinen İSS profilini başa alır, sayıyı korur' {
        $p = Get-SiraliProfiller '9121'
        $p[0].Ad | Should Be 'modern-5'
        $p.Count | Should Be $Script:Profiller.Count
    }
    It 'bilinmeyen İSS için varsayılan sırayı döndürür' {
        (Get-SiraliProfiller '1')[0].Ad | Should Be 'modern-9'
        (Get-SiraliProfiller $null)[0].Ad | Should Be 'modern-9'
    }
}

Describe 'Test-AlanAdi' {
    It 'geçerli alan adlarını kabul eder' {
        foreach ($a in 'discord.com', 'dis.gd', 'a-b.example.co', 'xn--bcher-kva.example') { Test-AlanAdi $a | Should Be $true }
    }
    It 'geçersiz satırları reddeder' {
        foreach ($a in 'discord', '-a.com', 'a..com', 'a.com --set-ttl 1', 'a.com"', '') { Test-AlanAdi $a | Should Be $false }
    }
}

Describe 'DNS paketleri' {
    It 'sorgu doğru kodlanır' {
        $q = New-DnsSorgusu 'a.bc'
        $q.Length | Should Be (12 + 1 + 1 + 1 + 2 + 1 + 4)
        $q[12] | Should Be 1
        $q[14] | Should Be 2
    }
    It 'sıkıştırılmış isimli A cevabını okur' {
        $q = New-DnsSorgusu 'a.bc'
        $c = [byte[]]($q[0..1] + @(0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0) + $q[12..($q.Length - 1)] +
            @(0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 162, 159, 135, 232))
        Read-DnsCevabi $c | Should Be '162.159.135.232'
        Read-DnsCevabi $c 0x1234 | Should Be '162.159.135.232'
        Read-DnsCevabi $c 0x9999 | Should BeNullOrEmpty
    }
    It 'engel adresini tanır' {
        Test-EngelAdresi @('195.175.254.2') | Should Be $true
        Test-EngelAdresi @('162.159.135.232') | Should Be $false
    }
}

Describe 'Write-Liste' {
    It 'yorumları atar, tekrarları birleştirir, BOM yazmaz' {
        $kaynak = Join-Path $TestDrive 'k.txt'
        Set-Content $kaynak "# yorum`nDiscord.com  # satır sonu`n`ndiscord.com`nroblox.com`nkotu satir" -Encoding UTF8
        $cikti = Write-Liste @($kaynak) @('ornek.com') (Join-Path $TestDrive 'o\liste.txt')
        $satirlar = Get-Content $cikti
        ($satirlar -join ',') | Should Be 'discord.com,roblox.com,ornek.com'
        ([IO.File]::ReadAllBytes($cikti)[0]) | Should Be ([byte][char]'d')
    }
}

Describe 'Read-BekciDurumu' {
    It 'eski sürümün dosyasına eksik alanları ekler' {
        $Script:BekciDosyasi = Join-Path $TestDrive 'bekci.json'
        '{"ardisikHata":1,"sonYenidenBul":null,"durduruldu":"2026-10-21T22:57:27","sonListe":null}' | Set-Content $Script:BekciDosyasi
        $d = Read-BekciDurumu
        $d.ardisikHata | Should Be 1
        ($d.PSObject.Properties.Name -contains 'durdurmaNedeni') | Should Be $true
        ($d.PSObject.Properties.Name -contains 'sonListeDeneme') | Should Be $true
        { $d.durdurmaNedeni = 'dns' } | Should Not Throw
    }
}

Describe 'Yabancı GoodbyeDPI işlemlerinin korunması' {
    It 'ölçümde çalışan eski hizmeti kendiliğinden durdurmaz' {
        Mock Get-Hizmet {
            if ($Ad -eq 'GoodbyeDPI') { return [pscustomobject]@{ Status = 'Running' } }
            return $null
        }
        Mock Get-YabanciGdpiSurecleri { @() }
        Mock Stop-Hizmet { }
        { Invoke-Bul -Hedefler @('discord.com') } | Should Throw
        Assert-MockCalled Stop-Hizmet -Times 0
    }

    It 'ölçümde başka goodbyedpi.exe süreçlerine dokunmaz' {
        Mock Get-Hizmet { return $null }
        Mock Get-YabanciGdpiSurecleri { return @([pscustomobject]@{ Id = 4242 }) }
        Mock Stop-Process { }
        { Invoke-Bul -Hedefler @('discord.com') } | Should Throw
        Assert-MockCalled Stop-Process -Times 0
    }

    It 'kurulumda eski hizmeti izinsiz kaldırmaz' {
        Mock Read-Ayarlar { return [pscustomobject]@{ profil = 'modern-9'; arg = '-9' } }
        Mock Get-Hizmet {
            if ($Ad -eq 'GoodbyeDPI') { return [pscustomobject]@{ Status = 'Stopped' } }
            return $null
        }
        Mock Remove-Hizmet { }
        { Invoke-Kur } | Should Throw
        Assert-MockCalled Remove-Hizmet -Times 0
    }
}


Describe 'Güvenli alan adı listesi güncellemesi' {
    BeforeEach {
        $Script:EskiKurulum = $Script:KurulumDizini
        $Script:EskiVeri = $Script:VeriDizini
        $Script:KurulumDizini = Join-Path $TestDrive 'installed'
        $Script:VeriDizini = Join-Path $TestDrive 'data'
        $Script:KaynakListe = Join-Path $Script:KurulumDizini 'listeler\turkiye.txt'
        $Script:EtkinListe = Join-Path $Script:KurulumDizini 'liste.txt'
        New-Item -ItemType Directory -Force -Path (Split-Path $Script:KaynakListe) | Out-Null
        Set-Content -Path $Script:KaynakListe -Value @('discord.com', 'roblox.com', 'old.example') -Encoding UTF8
        Set-Content -Path $Script:EtkinListe -Value @('discord.com', 'roblox.com', 'old.example') -Encoding ASCII
        Mock Read-Ayarlar { $null }
        Mock Invoke-WebRequest {
            [pscustomobject]@{ Content = [string]::Join([Environment]::NewLine, @('discord.com', 'roblox.com', 'new.example')) }
        }
    }
    AfterEach {
        $Script:KurulumDizini = $Script:EskiKurulum
        $Script:VeriDizini = $Script:EskiVeri
    }
    It 'geçersiz uzak listeyi mevcut dosyalara dokunmadan reddeder' {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = 'evil --set-ttl 1' } }
        Mock Stop-Hizmet { throw 'Hizmete dokunulmamalı' }
        { Update-Liste } | Should Throw
        (Get-Content $Script:KaynakListe -Raw -Encoding UTF8) | Should Match 'old.example'
        (Get-Content $Script:EtkinListe -Raw -Encoding ASCII) | Should Match 'old.example'
        Assert-MockCalled Stop-Hizmet -Times 0
    }
    It 'servis başlatılamazsa iki listeyi de geri yükler ve geçici dosyaları temizler' {
        Mock Get-Hizmet { [pscustomobject]@{ Status = 'Running' } }
        Mock Stop-Hizmet { }
        $script:UpdateListStarts = 0
        Mock Start-Service {
            $script:UpdateListStarts++
            if ($script:UpdateListStarts -eq 1) { throw 'Simulated startup failure' }
        }
        { Update-Liste } | Should Throw
        (Get-Content $Script:KaynakListe -Raw -Encoding UTF8) | Should Match 'old.example'
        (Get-Content $Script:EtkinListe -Raw -Encoding ASCII) | Should Match 'old.example'
        (Get-Content $Script:EtkinListe -Raw -Encoding ASCII) | Should Not Match 'new.example'
        @(Get-ChildItem $Script:VeriDizini -File -ErrorAction SilentlyContinue).Count | Should Be 0
        Assert-MockCalled Start-Service -Times 2
    }
    It 'servis çalışmıyorken doğrulanmış listeleri günceller, servis başlatmaz' {
        Mock Get-Hizmet { $null }
        Mock Start-Service { throw 'Servis başlatılmamalı' }
        (Update-Liste) | Should Be $true
        (Get-Content $Script:KaynakListe -Raw -Encoding UTF8) | Should Match 'new.example'
        (Get-Content $Script:EtkinListe -Raw -Encoding ASCII) | Should Match 'new.example'
        Assert-MockCalled Start-Service -Times 0
    }
}
