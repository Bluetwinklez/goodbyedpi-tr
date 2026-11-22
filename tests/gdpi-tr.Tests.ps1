# Pester 3.4 (Windows ile gelir):  Invoke-Pester .\tests
. (Join-Path $PSScriptRoot '..\gdpi-tr.ps1')

Describe 'Get-DurumOzeti' {
    It 'duraklatılmış hizmeti ağ testi veya hizmet değişikliği yapmadan raporlar' {
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = 'Stopped'; StartMode = 'Disabled' } }
        Mock Read-Ayarlar { [pscustomobject]@{ profil = 'modern-9'; arg = '-9'; genel = $false } }
        Mock Test-Internet { throw 'Durum okuma ağ testi yapmamalı.' }
        Mock Start-Service { throw 'Durum okuma hizmet başlatmamalı.' }
        $d = Get-DurumOzeti
        $d.Duraklatildi | Should Be $true
        $d.Hizmet | Should Be 'Stopped'
        $d.AyarOkundu | Should Be $true
        $d.Profil | Should Be 'modern-9'
        Assert-MockCalled Test-Internet -Times 0 -Exactly -Scope It
        Assert-MockCalled Start-Service -Times 0 -Exactly -Scope It
    }
    It 'okunamayan hizmeti kurulu değil gibi göstermez' {
        Mock Get-GdpiHizmetBilgisi { throw 'Erişim reddedildi.' }
        Mock Read-Ayarlar { throw 'Ayar okunamadı.' }
        $d = Get-DurumOzeti
        $d.Hizmet | Should Be 'Unknown'
        $d.Duraklatildi | Should BeNullOrEmpty
        $d.Hatalar.Count | Should Be 2
    }
}

Describe 'HTTPS teşhisi' {
    It 'URL veya komut içeren hedefi curl çalışmadan reddeder' {
        Mock Get-Curl { throw 'curl çalışmamalı.' }
        { Invoke-HttpsOlcum 'example.com/yonlendir' } | Should Throw 'geçerli bir alan adı'
        { Invoke-HttpsOlcum 'example.com --insecure' } | Should Throw 'geçerli bir alan adı'
        Assert-MockCalled Get-Curl -Times 0 -Exactly -Scope It
    }
    It 'DNS ve TLS hatalarını ayrı raporlar' {
        (Get-HttpsSonucu 'ornek.com' '000' 6).Durum | Should Be 'dns'
        (Get-HttpsSonucu 'ornek.com' '000' 35).Durum | Should Be 'tls'
        (Get-HttpsSonucu 'ornek.com' '000' 60).Durum | Should Be 'sertifika'
        (Get-HttpsSonucu 'ornek.com' '200' 28).Erisim | Should Be $false
    }
    It 'HTTP hatasını HTTPS bağlantısı kurulmasıyla birlikte raporlar' {
        $yasak = Get-HttpsSonucu 'ornek.com' '403' 0
        $yasak.Erisim | Should Be $true
        $yasak.Durum | Should Be 'http'
        (Get-HttpsSonucu 'ornek.com' '503' 0).Durum | Should Be 'sunucu'
        (Get-HttpsSonucu 'ornek.com' '000' 0).Erisim | Should Be $false
    }
    It 'normal test komutunda HTTP hatası için uyarı, DNS hatası için hata gösterir' {
        Mock Invoke-HttpsOlcum {
            if ($Alan -eq 'dns.example') { return Get-HttpsSonucu $Alan '000' 6 }
            Get-HttpsSonucu $Alan '403' 0
        }
        Mock Uyari { }
        Mock Hata { }
        Mock Baslik { }
        $sonuc = @(Invoke-Test -Hedefler @('http.example', 'dns.example'))
        $sonuc[0] | Should Be $true
        $sonuc[1] | Should Be $false
        Assert-MockCalled Hata -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match 'DNS adı çözülemedi' }
        Assert-MockCalled Uyari -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match '^http.example:.*HTTP 403' }
    }
}

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

Describe 'Update-HizmetKomutu' {
    It 'yeni ayarı ancak hizmet ve bağlantı denetimi geçince kaydeder' {
        $adimlar = New-Object 'System.Collections.Generic.List[string]'
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = 'Stopped'; StartMode = 'Auto'; PathName = 'eski-komut' } }
        Mock Set-HizmetYolu { $adimlar.Add('komut') }
        Mock Start-Service { $adimlar.Add('başlat') }
        Mock Wait-HizmetDurumu { $adimlar.Add('hizmet'); $true }
        Mock Start-Sleep { }
        Mock Test-Internet { $adimlar.Add('bağlantı'); $true }
        Mock Save-Ayarlar { $adimlar.Add('kaydet') }
        Update-HizmetKomutu @{ profil = 'modern-9' }
        ($adimlar -join ',') | Should Be 'komut,başlat,hizmet,bağlantı,kaydet'
    }
    It '<Durum> durumundaki hizmette başarısız ayarı kalıcılaştırmaz' -TestCases @(
        @{ Durum = 'Running' }, @{ Durum = 'Stopped' }
    ) {
        param($Durum)
        $durumKaydi = @{ Status = $Durum }
        $yollar = New-Object 'System.Collections.Generic.List[string]'
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = $Durum; StartMode = 'Auto'; PathName = 'eski-komut' } }
        Mock Get-Hizmet { $durumKaydi }
        Mock Set-HizmetYolu { $yollar.Add($Yol) }
        Mock Stop-Hizmet { $durumKaydi.Status = 'Stopped' }
        Mock Start-Service { $durumKaydi.Status = 'Running' }
        Mock Wait-HizmetDurumu { $true }
        Mock Start-Sleep { }
        Mock Test-Internet { $false }
        Mock Save-Ayarlar { throw 'Başarısız ayar yazılmamalı.' }
        { Update-HizmetKomutu @{ profil = 'modern-9' } } | Should Throw 'bağlantı denetimi başarısız'
        $yollar.Count | Should Be 2
        $yollar[1] | Should Be 'eski-komut'
        $durumKaydi.Status | Should Be $Durum
        Assert-MockCalled Save-Ayarlar -Times 0 -Exactly -Scope It
    }
}

Describe 'Invoke-Kaldir' {
    It 'hizmet silinemediyse görevi veya dosyaları kaldırmaz' {
        Mock Assert-KurulumSilmeYolu { }
        Mock Test-WinDivertKaydi { $false }
        Mock Remove-Hizmet { throw 'Silinmesi bekleniyor.' }
        Mock Get-BekciGorevi { throw 'Göreve dokunulmamalı.' }
        Mock Remove-Item { throw 'Dosyalara dokunulmamalı.' }
        { Invoke-Kaldir } | Should Throw 'Silinmesi bekleniyor.'
        Assert-MockCalled Get-BekciGorevi -Times 0 -Exactly -Scope It
        Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
    }
    It 'ortak sürücü kaydı varken bin klasörünü silmeye çalışmaz' {
        $eskiKurulum = $Script:KurulumDizini
        $eskiVeri = $Script:EskiVeriDizini
        $eskiKisayol = $Script:Kisayol
        $eskiAnahtar = $Script:KaldirmaAnahtari
        $Script:KurulumDizini = Join-Path $TestDrive 'kaldirma'
        $Script:EskiVeriDizini = Join-Path $TestDrive 'eski-veri'
        $Script:Kisayol = Join-Path $TestDrive 'kisayol'
        $Script:KaldirmaAnahtari = Join-Path $TestDrive 'kaldirma-anahtari'
        try {
            $bin = Join-Path $Script:KurulumDizini 'bin'
            $veri = Join-Path $Script:KurulumDizini 'veri'
            New-Item -ItemType Directory -Path $bin, $veri, $Script:EskiVeriDizini | Out-Null
            Mock Assert-KurulumSilmeYolu { }
            Mock Test-WinDivertKaydi { $true }
            Mock Remove-Hizmet { $true }
            Mock Get-BekciGorevi { }
            Mock Remove-Item { }
            Invoke-Kaldir
            Assert-MockCalled Remove-Item -Times 1 -Exactly -Scope It
            Assert-MockCalled Remove-Item -Times 1 -Exactly -Scope It -ParameterFilter { $LiteralPath -eq $veri }
        } finally {
            $Script:KurulumDizini = $eskiKurulum
            $Script:EskiVeriDizini = $eskiVeri
            $Script:Kisayol = $eskiKisayol
            $Script:KaldirmaAnahtari = $eskiAnahtar
        }
    }
}

Describe 'Get-HizmetKomutu' {
    It 'bilinen eski argümanları kabul eder ve DNS alanlarını türlerine göre işler' {
        $ayar = [pscustomobject]@{
            arg = '-9'
            genel = $false
            dns = @{ V4 = '192.0.2.1'; V6 = '2001:db8::1'; Port = [long]5353; V6Etkin = $true }
        }
        $exe = Join-Path $Script:KurulumDizini 'bin\goodbyedpi.exe'
        $liste = Join-Path $Script:KurulumDizini 'liste.txt'
        Get-HizmetKomutu $ayar |
            Should Be ('"{0}" -9 --blacklist "{1}" --dns-addr 192.0.2.1 --dns-port 5353 --dnsv6-addr 2001:db8::1 --dnsv6-port 5353' -f $exe, $liste)
    }
    It 'kayıtlı profilin ham komutunu değiştiren değeri reddeder' {
        { Get-HizmetKomutu @{ profil = 'modern-9'; arg = 'bilinmeyen' } } | Should Throw 'profil geçersiz'
    }
    It 'kapsamı yanlışlıkla genişletebilecek metin değerini reddeder' {
        { Get-HizmetKomutu @{ profil = 'modern-9'; genel = 'false' } } | Should Throw 'kapsam seçeneği geçersiz'
    }
    It 'geçersiz DNS alanlarını hizmet komutuna aktarmaz' {
        $ayar = @{ profil = 'modern-9'; dns = @{ V4 = '192.0.2.1'; Port = 65536 } }
        { Get-HizmetKomutu $ayar } | Should Throw 'DNS portu geçersiz'
        $ayar.dns.Port = 53
        $ayar.dns.V4 = '2001:db8::1'
        { Get-HizmetKomutu $ayar } | Should Throw 'IPv4 DNS adresi geçersiz'
    }
}

Describe 'Install-BekciGorevi' {
    It 'Windows PowerShell için sistem dizininden mutlak yol kullanır' {
        $beklenen = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
        Mock New-ScheduledTaskAction { throw 'Eylem denetlendi.' }
        { Install-BekciGorevi } | Should Throw 'Eylem denetlendi.'
        Assert-MockCalled New-ScheduledTaskAction -Times 1 -Exactly -Scope It -ParameterFilter {
            $Execute -eq $beklenen
        }
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
    It 'yalnızca beklenen soruya ait tam ve başarılı A cevabını kabul eder' {
        $sorgu = New-DnsSorgusu 'a.bc'
        $cevap = [byte[]]($sorgu[0..1] + @(0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0) +
            $sorgu[12..($sorgu.Length - 1)] + @(0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 192, 0, 2, 1))
        Read-DnsCevabi $cevap 0x1234 $sorgu | Should Be '192.0.2.1'
        Read-DnsCevabi $cevap 0x1234 (New-DnsSorgusu 'b.bc') | Should BeNullOrEmpty
        Read-DnsCevabi ($cevap[0..($cevap.Length - 2)]) 0x1234 $sorgu | Should BeNullOrEmpty
        $cevap[2] = 0x83
        Read-DnsCevabi $cevap 0x1234 $sorgu | Should BeNullOrEmpty
    }
}

Describe 'Save-Json' {
    It 'ana dosya bozulduğunda önceki geçerli yedeği okur ve korur' {
        $yol = Join-Path $TestDrive 'kurtarma.json'
        Save-Json @{ ad = 'Geçerli' } $yol
        Save-Json @{ ad = 'Yeni' } $yol
        [IO.File]::WriteAllText($yol, '{yarim')
        (Read-Json $yol).ad | Should Be 'Geçerli'
        Save-Json @{ ad = 'Onarıldı' } $yol
        (Read-Json $yol).ad | Should Be 'Onarıldı'
        (Read-Json "$yol.bak").ad | Should Be 'Geçerli'
    }
    It 'boş veya nesne olmayan dosyayı ve bozuk yedeği reddeder' {
        $yol = Join-Path $TestDrive 'bozuk.json'
        foreach ($icerik in '', 'null', '[]', '1', '"metin"') {
            [IO.File]::WriteAllText($yol, $icerik)
            { Read-Json $yol } | Should Throw 'Ayar dosyası geçersiz'
        }
        [IO.File]::WriteAllText("$yol.bak", '{yarim')
        { Read-Json $yol } | Should Throw 'yedeği kullanılamıyor'
    }
    It 'üçüncü kayıtta yedeği bir önceki geçerli sürüme ilerletir' {
        $yol = Join-Path $TestDrive 'ucuncu.json'
        Save-Json @{ ad = 'Bir' } $yol
        Save-Json @{ ad = 'İki' } $yol
        Save-Json @{ ad = 'Üç' } $yol
        (Read-Json $yol).ad | Should Be 'Üç'
        (Read-Json "$yol.bak").ad | Should Be 'İki'
    }
    It 'özel karakterli dosyaya Türkçe veriyi yazar ve atomik olarak değiştirir' {
        $yol = Join-Path $TestDrive 'ayar[1].json'
        Save-Json @{ ad = 'Önceki' } $yol
        (Read-Json $yol).ad | Should Be 'Önceki'
        Save-Json @{ ad = 'Çalışıyor' } $yol
        (Read-Json $yol).ad | Should Be 'Çalışıyor'
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.tmp').Count | Should Be 0
    }
    It 'serileştirme başarısız olursa geçerli ayarı korur' {
        $yol = Join-Path $TestDrive 'gecerli.json'
        Save-Json @{ ad = 'Önceki' } $yol
        Mock ConvertTo-Json { throw 'Ayar JSON biçimine çevrilemedi.' }
        { Save-Json @{ ad = 'Yeni' } $yol } | Should Throw 'Ayar JSON biçimine çevrilemedi.'
        (Read-Json $yol).ad | Should Be 'Önceki'
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.tmp').Count | Should Be 0
    }
}

Describe 'Get-KurulumListeKopyalari' {
    It 'mevcut kullanıcı listesini korurken paket listesini yeniler' {
        $kaynak = Join-Path $TestDrive 'paket'
        $hedef = Join-Path $TestDrive 'kurulu'
        New-Item -ItemType Directory -Path (Join-Path $kaynak 'listeler'), $hedef | Out-Null
        Set-Content (Join-Path $kaynak 'listeler\kullanici.txt') '# paket şablonu'
        Set-Content (Join-Path $kaynak 'listeler\turkiye.txt') 'yeni.example'
        Set-Content (Join-Path $hedef 'kullanici.txt') 'benim.example'
        foreach ($dosya in Get-KurulumListeKopyalari $kaynak $hedef) {
            Copy-Item -LiteralPath $dosya.Kaynak -Destination $dosya.Hedef
        }
        Get-Content (Join-Path $hedef 'kullanici.txt') | Should Be 'benim.example'
        Get-Content (Join-Path $hedef 'turkiye.txt') | Should Be 'yeni.example'
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
    It 'bozuk sayaç ve tarihleri onarır, bilinmeyen durdurma kaydını temizler' {
        $onceki = $Script:BekciDosyasi
        $Script:BekciDosyasi = Join-Path $TestDrive 'bozuk-alanlar.json'
        try {
            Save-Json ([pscustomobject]@{
                ardisikHata = 'sayi-degil'; sonYenidenBul = @()
                durduruldu = '2026-10-21T22:57:27'; durdurmaNedeni = 'bilinmeyen'; sonListe = 'bozuk'
            }) $Script:BekciDosyasi
            Mock Uyari { }
            $d = Read-BekciDurumu
            $d.ardisikHata | Should Be 0
            $d.sonYenidenBul | Should BeNullOrEmpty
            $d.sonListe | Should BeNullOrEmpty
            $d.durduruldu | Should BeNullOrEmpty
            $d.durdurmaNedeni | Should BeNullOrEmpty
        } finally {
            $Script:BekciDosyasi = $onceki
        }
    }
    It 'eski sürümün dosyasına eksik alanları ekler' {
        $Script:BekciDosyasi = Join-Path $TestDrive 'bekci.json'
        '{"ardisikHata":1,"sonYenidenBul":null,"durduruldu":"2026-10-21T22:57:27","sonListe":null}' | Set-Content $Script:BekciDosyasi
        $d = Read-BekciDurumu
        $d.ardisikHata | Should Be 1
        ($d.PSObject.Properties.Name -contains 'durdurmaNedeni') | Should Be $true
        { $d.durdurmaNedeni = 'dns' } | Should Not Throw
    }
}

Describe 'Test-SureGecti' {
    It 'bozuk veya gelecek tarih yüzünden kurtarmayı sürekli bekletmez' {
        $aralik = New-TimeSpan -Hours 6
        Test-SureGecti 'gecersiz' $aralik | Should Be $true
        Test-SureGecti ((Get-Date).AddHours(1).ToString('s')) $aralik | Should Be $true
        Test-SureGecti ((Get-Date).AddHours(-1).ToString('s')) $aralik | Should Be $false
        Test-SureGecti ((Get-Date).AddHours(-7).ToString('o')) $aralik | Should Be $true
    }
}

Describe 'Invoke-Bekci' {
    It 'bekçinin durdurmadığı bir hizmete veya ağa dokunmaz' {
        Mock Read-Ayarlar { [pscustomobject]@{ dns = $null } }
        Mock Get-Hizmet { [pscustomobject]@{ Status = 'Stopped' } }
        Mock Read-BekciDurumu { [pscustomobject]@{ durduruldu = $null } }
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ StartMode = 'Auto' } }
        Mock Test-AgVar { throw 'Ağ denetimi çağrılmamalı.' }
        Mock Start-Service { throw 'Hizmet başlatılmamalı.' }
        $sessiz = $Script:Sessiz
        try {
            Invoke-Bekci
            Assert-MockCalled Test-AgVar -Times 0 -Exactly -Scope It
            Assert-MockCalled Start-Service -Times 0 -Exactly -Scope It
        } finally {
            $Script:Sessiz = $sessiz
        }
    }
    It 'önceki bekçi kaydından bağımsız olarak devre dışı hizmeti atlar' {
        Mock Get-Hizmet { [pscustomobject]@{ Status = 'Stopped' } }
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ StartMode = 'Disabled' } }
        Mock Read-BekciDurumu { throw 'Bekçi önceki durumu okumamalı.' }
        Mock Test-AgVar { throw 'Ağ denetimi çağrılmamalı.' }
        $sessiz = $Script:Sessiz
        try {
            Invoke-Bekci
            Assert-MockCalled Read-BekciDurumu -Times 0 -Exactly -Scope It
            Assert-MockCalled Test-AgVar -Times 0 -Exactly -Scope It
        } finally {
            $Script:Sessiz = $sessiz
        }
    }
    It 'internet arızası bekleme süresinde DNS değiştirip hizmeti başlatmaz' {
        Mock Get-Hizmet { [pscustomobject]@{ Status = 'Stopped' } }
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ StartMode = 'Auto' } }
        Mock Read-Ayarlar { [pscustomobject]@{ dns = @{} } }
        Mock Read-BekciDurumu {
            [pscustomobject]@{ durduruldu = (Get-Date).AddMinutes(-5).ToString('s'); durdurmaNedeni = 'internet' }
        }
        Mock Test-AgVar { throw 'Bekleme sırasında ağa dokunulmamalı.' }
        $sessiz = $Script:Sessiz
        try {
            Invoke-Bekci
            Assert-MockCalled Test-AgVar -Times 0 -Exactly -Scope It
        } finally {
            $Script:Sessiz = $sessiz
        }
    }
}

Describe 'Duraklatma ve devam' {
    It 'hizmeti durdurmadan önce açılışta otomatik başlatmayı kapatır' {
        $adimlar = New-Object 'System.Collections.Generic.List[string]'
        Mock Get-Hizmet { [pscustomobject]@{ Status = 'Running' } }
        Mock Set-Service { $adimlar.Add([string]$StartupType) }
        Mock Stop-Hizmet { $adimlar.Add('Stop') }
        Mock Wait-HizmetDurumu { $true }
        Invoke-Duraklat
        ($adimlar -join ',') | Should Be 'Disabled,Stop'
    }
    It 'devam ederken başlatma başarısız olursa duraklatmayı geri yükler' {
        $adimlar = New-Object 'System.Collections.Generic.List[string]'
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ StartMode = 'Disabled'; State = 'Stopped' } }
        Mock Set-Service { $adimlar.Add([string]$StartupType) }
        Mock Start-Service { $adimlar.Add('Start'); throw 'Sürücü başlatılamadı.' }
        Mock Stop-Hizmet { $adimlar.Add('Stop') }
        Mock Wait-HizmetDurumu { $true }
        { Invoke-Devam } | Should Throw 'Sürücü başlatılamadı.'
        ($adimlar -join ',') | Should Be 'Automatic,Start,Disabled,Stop'
    }
}

Describe 'Invoke-Kur' {
    It 'paket hazırlanamazsa mevcut hizmeti kaldırmaz' {
        Mock Get-Hizmet { }
        Mock Get-YabanciGdpiSurecleri { }
        Mock Read-Ayarlar { [pscustomobject]@{ profil = 'modern-9' } }
        Mock Get-Ikililer { throw 'Paket doğrulanamadı.' }
        Mock Remove-Hizmet { throw 'Mevcut hizmete dokunulmamalı.' }
        { Invoke-Kur } | Should Throw 'Paket doğrulanamadı.'
        Assert-MockCalled Remove-Hizmet -Times 0 -Exactly -Scope It
    }
    It '<Asama> başarısızsa önceki dosyaları ve hizmet komutunu geri yükler' -TestCases @(
        @{ Asama = 'internet denetimi' },
        @{ Asama = 'bekçi kaydı' },
        @{ Asama = 'kısayol kaydı' }
    ) {
        param($Asama)
        $eskiKurulum = $Script:KurulumDizini
        $eskiKaynak = $Script:KaynakDizini
        $eskiPaket = $Script:Paket
        $Script:KurulumDizini = Join-Path $TestDrive 'kurulu-surum'
        $Script:KaynakDizini = $Script:KurulumDizini
        $Script:Paket = @{ Dosyalar = @{ x86_64 = @{ 'goodbyedpi.exe' = 'test' } } }
        try {
            $gelen = Join-Path $TestDrive 'yeni-surum'
            $eskiExe = Join-Path $Script:KurulumDizini 'bin\goodbyedpi.exe'
            $liste = Join-Path $Script:KurulumDizini 'liste.txt'
            New-Item -ItemType Directory -Force -Path (Split-Path $eskiExe), $gelen | Out-Null
            Set-Content $eskiExe 'eski ikili'
            Set-Content (Join-Path $gelen 'goodbyedpi.exe') 'yeni ikili'
            Set-Content $liste 'eski.example'
            Mock Get-Hizmet { } -ParameterFilter { $Ad -eq 'GoodbyeDPI' }
            Mock Get-Hizmet { [pscustomobject]@{ Status = 'Stopped' } } -ParameterFilter { $Ad -ne 'GoodbyeDPI' }
            Mock Get-YabanciGdpiSurecleri { }
            Mock Read-Ayarlar { [pscustomobject]@{ arg = '-9'; hedefler = @('yeni.example') } }
            Mock Get-Ikililer { $gelen }
            Mock Get-Mimari { 'x86_64' }
            Mock Test-IkiliHashleri { $true }
            Mock Get-CimInstance { [pscustomobject]@{ State = 'Running'; PathName = 'eski-hizmet-komutu' } }
            Mock Set-HizmetYolu { }
            Mock Stop-Hizmet { }
            Mock Start-Service { }
            Mock Wait-HizmetDurumu { $true }
            Mock Start-Sleep { }
            Mock Test-Internet { $Asama -ne 'internet denetimi' }
            Mock Get-KurulumKayitYedegi { @{ GorevXml = '<onceki/>' } }
            Mock Install-BekciGorevi { if ($Asama -eq 'bekçi kaydı') { throw 'bekçi kaydı başarısız' } }
            Mock Install-Kisayollar { throw 'kısayol kaydı başarısız' }
            Mock Restore-KurulumKayitlari { }
            Mock Save-Ayarlar { throw 'Başarısız deneme kaydedilmemeli.' }

            { Invoke-Kur } | Should Throw "$Asama başarısız"
            Get-Content $eskiExe | Should Be 'eski ikili'
            Get-Content $liste | Should Be 'eski.example'
            Assert-MockCalled Set-HizmetYolu -Times 1 -Exactly -Scope It -ParameterFilter { $Yol -eq 'eski-hizmet-komutu' }
            Assert-MockCalled Start-Service -Times 2 -Exactly -Scope It
            Assert-MockCalled Save-Ayarlar -Times 0 -Exactly -Scope It
            switch ($Asama) {
                'internet denetimi' { Assert-MockCalled Restore-KurulumKayitlari -Times 0 -Exactly -Scope It }
                'bekçi kaydı' {
                    Assert-MockCalled Restore-KurulumKayitlari -Times 1 -Exactly -Scope It -ParameterFilter {
                        $Yedek.GorevXml -eq '<onceki/>' -and -not $KisayolaDokunuldu
                    }
                }
                'kısayol kaydı' {
                    Assert-MockCalled Restore-KurulumKayitlari -Times 1 -Exactly -Scope It -ParameterFilter {
                        $Yedek.GorevXml -eq '<onceki/>' -and $KisayolaDokunuldu
                    }
                }
            }
        } finally {
            $Script:KurulumDizini = $eskiKurulum
            $Script:KaynakDizini = $eskiKaynak
            $Script:Paket = $eskiPaket
        }
    }
}

Describe 'Restore-KurulumKayitlari' {
    It 'bekçi kaydı geri yüklenemezse bile kısayolu geri yükler' {
        $eskiKisayol = $Script:Kisayol
        $eskiAnahtar = $Script:KaldirmaAnahtari
        $Script:Kisayol = Join-Path $TestDrive 'GoodbyeDPI-TR.lnk'
        $Script:KaldirmaAnahtari = Join-Path $TestDrive 'olmayan-kayit'
        try {
            [IO.File]::WriteAllBytes($Script:Kisayol, [byte[]]@(9, 8))
            Mock Register-ScheduledTask { throw 'Görev Zamanlayıcı kullanılamıyor.' }
            $yedek = @{ GorevXml = '<Task/>'; Kisayol = [byte[]]@(1, 2, 3); AnahtarVardi = $false }
            { Restore-KurulumKayitlari $yedek $true } | Should Throw 'Görev Zamanlayıcı kullanılamıyor.'
            ([IO.File]::ReadAllBytes($Script:Kisayol) -join ',') | Should Be '1,2,3'
            Assert-MockCalled Register-ScheduledTask -Times 1 -Exactly -Scope It -ParameterFilter {
                $Xml -eq '<Task/>' -and $TaskPath -eq '\' -and $TaskName -eq $Script:GorevAdi
            }
        } finally {
            $Script:Kisayol = $eskiKisayol
            $Script:KaldirmaAnahtari = $eskiAnahtar
        }
    }
}

Describe 'Update-Liste' {
    It 'birleşik liste uygulanamazsa merkezi listeyi geri yükler' {
        $eskiKurulum = $Script:KurulumDizini
        $Script:KurulumDizini = Join-Path $TestDrive 'yazma-hatasi'
        try {
            $listeler = Join-Path $Script:KurulumDizini 'listeler'
            $birlesik = Join-Path $Script:KurulumDizini 'liste.txt'
            New-Item -ItemType Directory -Path $listeler, $birlesik | Out-Null
            $merkezi = Join-Path $listeler 'turkiye.txt'
            Set-Content $merkezi 'eski.example'
            Mock Invoke-WebRequest { @{ Content = "yeni.example`niki.example`nuc.example" } }
            Mock Read-Ayarlar { }
            Mock Get-Hizmet { [pscustomobject]@{ Status = 'Stopped' } }
            { Update-Liste } | Should Throw 'Liste dosyası yerine klasör var'
            (Get-Content $merkezi) | Should Be 'eski.example'
            (Test-Path -LiteralPath $birlesik -PathType Container) | Should Be $true
            @(Get-ChildItem $Script:KurulumDizini -Recurse | Where-Object { $_.Extension -in '.bak', '.tmp' }).Count | Should Be 0
        } finally {
            $Script:KurulumDizini = $eskiKurulum
        }
    }

    It '<Senaryo> senaryosunda liste ve hizmet durumunu tutarlı bırakır' -TestCases @(
        @{ Senaryo = 'kapalı hizmet'; Durum = 'Stopped'; IlkBaslatmaHatasi = $false },
        @{ Senaryo = 'çalışan hizmet'; Durum = 'Running'; IlkBaslatmaHatasi = $false },
        @{ Senaryo = 'başlatma hatası'; Durum = 'Running'; IlkBaslatmaHatasi = $true }
    ) {
        param($Senaryo, $Durum, $IlkBaslatmaHatasi)
        $eskiKurulum = $Script:KurulumDizini
        $oncekiTls = [Net.ServicePointManager]::SecurityProtocol
        $Script:KurulumDizini = Join-Path $TestDrive $Senaryo
        try {
            $listeler = Join-Path $Script:KurulumDizini 'listeler'
            New-Item -ItemType Directory -Path $listeler | Out-Null
            $merkezi = Join-Path $listeler 'turkiye.txt'
            $ozel = Join-Path $listeler 'kullanici.txt'
            $birlesik = Join-Path $Script:KurulumDizini 'liste.txt'
            Set-Content $merkezi 'eski.example'
            Set-Content $ozel 'benim.example'
            Set-Content $birlesik @('benim.example', 'eski.example')

            $baslatmalardaListe = New-Object 'System.Collections.Generic.List[string]'
            $durumKaydi = @{ Status = $Durum }
            Mock Invoke-WebRequest { @{ Content = "yeni.example`niki.example`nuc.example" } }
            Mock Read-Ayarlar { [pscustomobject]@{ hedefler = @('ek.example') } }
            Mock Get-Hizmet { $durumKaydi }
            Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ StartMode = 'Auto' } }
            Mock Stop-Hizmet { $durumKaydi.Status = 'Stopped' }
            Mock Wait-HizmetDurumu { $durumKaydi.Status -eq $Durum }
            Mock Start-Service {
                $baslatmalardaListe.Add(((Get-Content $birlesik) -join ','))
                if ($IlkBaslatmaHatasi -and $baslatmalardaListe.Count -eq 1) { throw 'Başlatma hatası.' }
                $durumKaydi.Status = 'Running'
            }

            if ($IlkBaslatmaHatasi) {
                { Update-Liste } | Should Throw 'Başlatma hatası.'
                (Get-Content $merkezi) | Should Be 'eski.example'
                ((Get-Content $birlesik) -join ',') | Should Be 'benim.example,eski.example'
                $baslatmalardaListe.Count | Should Be 2
                $baslatmalardaListe[0] | Should Be 'benim.example,yeni.example,iki.example,uc.example,ek.example'
                $baslatmalardaListe[1] | Should Be 'benim.example,eski.example'
            } else {
                Update-Liste | Should Be $true
                ((Get-Content $merkezi) -join ',') | Should Be 'yeni.example,iki.example,uc.example'
                ((Get-Content $birlesik) -join ',') | Should Be 'benim.example,yeni.example,iki.example,uc.example,ek.example'
                $beklenen = if ($Durum -eq 'Running') { 1 } else { 0 }
                $baslatmalardaListe.Count | Should Be $beklenen
            }
            $durumKaydi.Status | Should Be $Durum
            (Get-Content $ozel) | Should Be 'benim.example'
            @(Get-ChildItem $Script:KurulumDizini -Recurse | Where-Object { $_.Extension -in '.bak', '.tmp' }).Count | Should Be 0
        } finally {
            $Script:KurulumDizini = $eskiKurulum
            [Net.ServicePointManager]::SecurityProtocol = $oncekiTls
        }
    }
}

Describe 'Invoke-KilitliIslem' {
    It 'çakışan komutu reddeder, bekçiyi atlar ve hata sonrasında kilidi bırakır' {
        $eskiDizin = $Script:KurulumDizini
        $Script:KurulumDizini = Join-Path $TestDrive 'kurulum'
        try {
            {
                Invoke-KilitliIslem {
                    { Invoke-KilitliIslem { throw 'İkinci işlem çalıştı.' } } |
                        Should Throw 'Başka bir GoodbyeDPI-TR işlemi'
                    Invoke-KilitliIslem { throw 'Bekçi çalıştı.' } -Bekci
                    throw 'İlk işlem başarısız.'
                }
            } | Should Throw 'İlk işlem başarısız.'
            Invoke-KilitliIslem { 'Kilit bırakıldı.' } | Should Be 'Kilit bırakıldı.'
        } finally {
            $Script:KurulumDizini = $eskiDizin
        }
    }
}
