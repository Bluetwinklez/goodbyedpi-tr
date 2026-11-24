# Pester 3.4 (Windows ile gelir):  Invoke-Pester .\tests
. (Join-Path $PSScriptRoot '..\gdpi-tr.ps1')

Describe 'Get-DurumOzeti' {
    It 'duraklatılmış hizmeti ağ testi veya hizmet değişikliği yapmadan raporlar' {
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = 'Stopped'; StartMode = 'Disabled' } }
        Mock Read-Ayarlar { [pscustomobject]@{ profil = 'modern-9'; arg = '-9'; genel = $false } }
        Mock Read-OlcumGecmisi { @() }
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
        Mock Read-OlcumGecmisi { @() }
        $d = Get-DurumOzeti
        $d.Hizmet | Should Be 'Unknown'
        $d.Duraklatildi | Should BeNullOrEmpty
        $d.Hatalar.Count | Should Be 2
    }
    It 'son ölçümü raporlar; okunamayan geçmişi hata olarak bildirir' {
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = 'Running'; StartMode = 'Auto' } }
        Mock Read-Ayarlar { }
        Mock Read-OlcumGecmisi { @([pscustomobject]@{ Zaman = '2026-11-01T10:00:00.0000000Z'; Tekrar = 5 }, [pscustomobject]@{ Zaman = '2026-11-02T10:00:00.0000000Z'; Tekrar = 3 }) }
        (Get-DurumOzeti).SonOlcum.Tekrar | Should Be 3
        Mock Read-OlcumGecmisi { throw 'Bozuk.' }
        $d = Get-DurumOzeti
        $d.SonOlcum | Should BeNullOrEmpty
        $d.Hatalar -contains 'Ölçüm geçmişi okunamadı.' | Should Be $true
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
        ($d.PSObject.Properties.Name -contains 'sonListeDeneme') | Should Be $true
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


Describe 'Gizlilik korumalı rapor' {
    It 'yalnız yerel bilgileri toplar, özel ağ adresleri ve hedefleri sızdırmaz' {
        $once = $Script:KurulumDizini
        try {
            $Script:KurulumDizini = $TestDrive
            Set-Content (Join-Path $TestDrive 'liste.txt') -Value @('discord.com', 'roblox.com') -Encoding ASCII
            Mock Get-Hizmet { [pscustomobject]@{ Status = 'Running' } }
            Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } }
            Mock Get-Mimari { 'x86_64' }
            Mock Read-Ayarlar {
                [pscustomobject]@{
                    profil = 'modern-9'
                    genel = $false
                    dns = [pscustomobject]@{ Ad = 'Quad9'; V4 = '9.9.9.10' }
                    hedefler = @('secret.example.com')
                    iss = 'Private ISP account'
                }
            }
            Mock Test-Https { throw 'Ağ isteği yapılmamalı' }
            Mock Start-Service { throw 'Servis değiştirilmemeli' }
            $r = Get-TaniRapor
            $json = $r | ConvertTo-Json -Depth 4
            $r.serviceStatus | Should Be 'Running'
            $r.watchdogStatus | Should Be 'Ready'
            $r.activeDomainCount | Should Be 2
            $r.selectedProfile | Should Be 'modern-9'
            $r.configurationReadable | Should Be $true
            $json | Should Not Match '9\.9\.9\.10|secret\.example\.com|Private ISP|discord\.com|roblox\.com'
            Assert-MockCalled Test-Https -Times 0
            Assert-MockCalled Start-Service -Times 0
        } finally { $Script:KurulumDizini = $once }
    }
    It 'bozuk ayarlarda da yalnız hata durumu raporlar' {
        Mock Read-Ayarlar { throw 'C:\Users\secret-user\broken.json' }
        Mock Get-Hizmet { return $null }
        Mock Get-ScheduledTask { return $null }
        Mock Get-Mimari { 'x86_64' }
        $r = Get-TaniRapor
        $r.configurationReadable | Should Be $false
        $r.configurationPresent | Should Be $false
        ($r | ConvertTo-Json) | Should Not Match 'secret-user|broken\.json'
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
        $script:UpdateListHizmet = @{ Status = 'Running' }
        Mock Get-Hizmet { $script:UpdateListHizmet }
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ StartMode = 'Auto' } }
        Mock Stop-Hizmet { $script:UpdateListHizmet.Status = 'Stopped' }
        Mock Wait-HizmetDurumu { $true }
        $script:UpdateListStarts = 0
        Mock Start-Service {
            $script:UpdateListStarts++
            if ($script:UpdateListStarts -eq 1) { throw 'Simulated startup failure' }
            $script:UpdateListHizmet.Status = 'Running'
        }
        { Update-Liste } | Should Throw
        (Get-Content $Script:KaynakListe -Raw -Encoding UTF8) | Should Match 'old.example'
        (Get-Content $Script:EtkinListe -Raw -Encoding ASCII) | Should Match 'old.example'
        (Get-Content $Script:EtkinListe -Raw -Encoding ASCII) | Should Not Match 'new.example'
        @(Get-ChildItem $Script:VeriDizini -File -ErrorAction SilentlyContinue).Count | Should Be 0
        Assert-MockCalled Start-Service -Times 2 -Scope It
    }
    It 'servis çalışmıyorken doğrulanmış listeleri günceller, servis başlatmaz' {
        Mock Get-Hizmet { $null }
        Mock Start-Service { throw 'Servis başlatılmamalı' }
        (Update-Liste) | Should Be $true
        (Get-Content $Script:KaynakListe -Raw -Encoding UTF8) | Should Match 'new.example'
        (Get-Content $Script:EtkinListe -Raw -Encoding ASCII) | Should Match 'new.example'
        Assert-MockCalled Start-Service -Times 0 -Scope It
    }
}

Describe 'Hız ölçümü' {
    $tam = '200|0.012000|0.036000|0.097000|0.215000|0.300000|1500000.000|450000'

    It 'curl çıktısını aşamalara ayırır' {
        $o = Get-HizOlcumuSonucu 'ornek.com' $tam 0
        $o.Erisim | Should Be $true
        $o.DnsMs | Should Be 12
        $o.TcpMs | Should Be 24
        $o.TlsMs | Should Be 61
        $o.SunucuMs | Should Be 118
        $o.IlkBaytMs | Should Be 215
        $o.ToplamMs | Should Be 300
        $o.VerimBps | Should Be 1500000
        $o.Bayt | Should Be 450000
    }
    It 'IP hedefinde DNS ve TLS yoksa bunları uydurmaz' {
        $o = Get-HizOlcumuSonucu '192.0.2.1' '200|0.000000|0.020000|0.000000|0.050000|0.060000|1000.000|100' 0
        $o.Erisim | Should Be $true
        $o.DnsMs | Should Be 0
        $o.TcpMs | Should Be 20
        $o.TlsMs | Should BeNullOrEmpty
        $o.SunucuMs | Should Be 30
    }
    It 'başarısız istekte süre üretmez ve nedeni korur' {
        $o = Get-HizOlcumuSonucu 'ornek.com' '000|0.000000|0.000000|0.000000|0.000000|10.000000|0.000|0' 28
        $o.Erisim | Should Be $false
        $o.Durum | Should Be 'zaman-asimi'
        $o.IlkBaytMs | Should BeNullOrEmpty
        $o.VerimBps | Should BeNullOrEmpty
    }
    It 'bozuk, eksik veya tutarsız çıktıdan süre çıkarmaz' {
        (Get-HizOlcumuSonucu 'ornek.com' 'anlamsiz' 0).Erisim | Should Be $false
        $eksik = Get-HizOlcumuSonucu 'ornek.com' '200|0.012000|0.036000' 0
        $eksik.Erisim | Should Be $true
        $eksik.IlkBaytMs | Should BeNullOrEmpty
        $sayiDegil = Get-HizOlcumuSonucu 'ornek.com' '200|abc|0.036000|0.097000|0.215000|0.3|1|1' 0
        $sayiDegil.IlkBaytMs | Should BeNullOrEmpty
        # İmkânsız sıralar: ilk bayt bağlantıdan önce; toplam ilk bayttan önce; TLS bağlantıdan önce.
        foreach ($imkansiz in '200|0.010000|0.300000|0.310000|0.200000|0.5|1|1',
            '200|0.010000|0.030000|0.090000|0.400000|0.3|1|1',
            '200|0.010000|0.090000|0.050000|0.400000|0.5|1|1') {
            (Get-HizOlcumuSonucu 'ornek.com' $imkansiz 0).IlkBaytMs | Should BeNullOrEmpty
        }
    }
    It 'çözümleyici bağlantıdan sonra yanıt verirse yalnızca TCP aşamasını boş bırakır (gerçek roblox örneği)' {
        $o = Get-HizOlcumuSonucu 'www.roblox.com' '200|0.141091|0.087419|0.146879|0.323995|0.409426|155432|63637' 0
        $o.DnsMs | Should Be 141.1
        $o.TcpMs | Should BeNullOrEmpty
        $o.TlsMs | Should Be 59.5
        $o.SunucuMs | Should Be 177.1
        $o.IlkBaytMs | Should Be 324
        $o.ToplamMs | Should Be 409.4
    }
    It 'hedef açılıp süre çıkarılamadıysa bunu özet satırında belirtir' {
        $o = Get-HizOlcumuSonucu 'a.example' '200|0.010000|0.300000|0.310000|0.200000|0.5|1|1' 0
        (Format-HizOzeti (Get-HizOzeti 'a.example' @($o))) | Should Match 'süre okunamadı'
    }
    It 'geçersiz süre metinlerini reddeder, geçerlileri kültürden bağımsız çözer' {
        foreach ($m in '-1', 'NaN', 'Infinity', 'abc', '', '0,5') {
            ConvertTo-Milisaniye $m | Should BeNullOrEmpty
        }
        ConvertTo-Milisaniye '0.0125' | Should Be 12.5
        ConvertTo-Milisaniye '0' | Should Be 0
    }
    It 'ortanca ve p90 değerlerini doğru hesaplar' {
        $a = Get-Istatistik @(5, 1, 3, 2, 4)
        $a.Ortanca | Should Be 3
        $a.P90 | Should Be 5
        $a.Say | Should Be 5
        $b = Get-Istatistik @(1, 2, 3, 4)
        $b.Ortanca | Should Be 2.5
        $b.P90 | Should Be 4
        (Get-Istatistik @(1..10)).P90 | Should Be 9
        (Get-Istatistik @(7)).Ortanca | Should Be 7
        (Get-Istatistik @(7)).P90 | Should Be 7
        Get-Istatistik @() | Should BeNullOrEmpty
    }
    It 'hedefi yalnızca alan adı veya IP olarak kabul eder' {
        Get-TestSunucusu 'discord.com' | Should Be 'discord.com'
        Get-TestSunucusu '192.0.2.1' | Should Be '192.0.2.1'
        Get-TestSunucusu '2001:db8::1' | Should Be '[2001:db8::1]'
        foreach ($k in 'example.com/yol', 'example.com --insecure', 'https://example.com', '') {
            { Get-TestSunucusu $k } | Should Throw 'geçerli bir alan adı'
        }
    }
    It 'kötü hedefte curl çalıştırmaz' {
        Mock Get-Curl { throw 'curl çalışmamalı.' }
        { Invoke-HizOlcumu 'example.com/yonlendir' } | Should Throw 'geçerli bir alan adı'
        Assert-MockCalled Get-Curl -Times 0 -Exactly -Scope It
    }
    It 'denemeleri özetler ve başarısızlıkları nedeniyle sayar' {
        $olcumler = @(
            (Get-HizOlcumuSonucu 'ornek.com' '200|0.010000|0.030000|0.090000|0.200000|0.3|1|1' 0),
            (Get-HizOlcumuSonucu 'ornek.com' '200|0.020000|0.050000|0.110000|0.240000|0.3|1|1' 0),
            (Get-HizOlcumuSonucu 'ornek.com' '200|0.030000|0.060000|0.120000|0.280000|0.3|1|1' 0),
            (Get-HizOlcumuSonucu 'ornek.com' '000|0|0|0|0|10|0|0' 28)
        )
        $o = Get-HizOzeti 'ornek.com' $olcumler
        $o.Deneme | Should Be 4
        $o.Basarili | Should Be 3
        $o.Hatalar.Count | Should Be 1
        $o.Hatalar[0].Durum | Should Be 'zaman-asimi'
        $o.IlkBayt.Ortanca | Should Be 240
        $o.Dns.Ortanca | Should Be 20
    }
    It 'verimi yalnızca yeterince büyük örnekte gösterir' {
        $kucuk = Get-HizOzeti 'ornek.com' @(Get-HizOlcumuSonucu 'ornek.com' '200|0.01|0.03|0.09|0.2|0.3|9000.0|2000' 0)
        $buyuk = Get-HizOzeti 'ornek.com' @(Get-HizOlcumuSonucu 'ornek.com' '200|0.01|0.03|0.09|0.2|0.3|2000000.0|500000' 0)
        (Format-HizOzeti $kucuk) | Should Not Match 'MB/s'
        (Format-HizOzeti $buyuk) | Should Match 'MB/s'
        (Format-HizOzeti $buyuk) | Should Match '1/1 başarılı'
    }
    It 'her hedefi tekrar sayısı kadar ölçer, kontrol sitelerini ekler, yinelenenleri atlar' {
        Mock Baslik { }
        Mock Yaz { }
        Mock Basari { }
        Mock Uyari { }
        Mock Hata { }
        Mock Start-Sleep { }
        Mock Invoke-HizOlcumu {
            Get-HizOlcumuSonucu $Alan '200|0.010000|0.030000|0.090000|0.200000|0.3|1|1' 0
        }
        $sonuc = @(Invoke-Hiz -Hedefler @('a.example', 'www.google.com') -Tekrar 3)
        $sonuc.Count | Should Be 3
        Assert-MockCalled Invoke-HizOlcumu -Times 9 -Exactly -Scope It
        Assert-MockCalled Basari -Times 3 -Exactly -Scope It
        Assert-MockCalled Hata -Times 0 -Exactly -Scope It
    }
    It 'tamamen başarısız hedefi hata, kısmen başarısızı uyarı olarak gösterir' {
        Mock Baslik { }
        Mock Yaz { }
        Mock Basari { }
        Mock Uyari { }
        Mock Hata { }
        Mock Start-Sleep { }
        $script:HizCagri = @{}
        Mock Invoke-HizOlcumu {
            $script:HizCagri[$Alan] = 1 + [int]$script:HizCagri[$Alan]
            if ($Alan -eq 'olu.example') { return Get-HizOlcumuSonucu $Alan '000|0|0|0|0|5|0|0' 6 }
            if ($Alan -eq 'yari.example' -and $script:HizCagri[$Alan] -eq 1) { return Get-HizOlcumuSonucu $Alan '000|0|0|0|0|5|0|0' 28 }
            Get-HizOlcumuSonucu $Alan '200|0.010000|0.030000|0.090000|0.200000|0.3|1|1' 0
        }
        Invoke-Hiz -Hedefler @('olu.example', 'yari.example') -Tekrar 2 | Out-Null
        Assert-MockCalled Hata -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match '^olu.example: 0/2' }
        Assert-MockCalled Uyari -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match '^yari.example: 1/2' }
    }
}

Describe 'Ölçüm geçmişi' {
    BeforeEach {
        $Script:EskiOlcumDosyasi = $Script:OlcumDosyasi
        # Pester 3.4 TestDrive'ı It'ler arasında temizlemez; her test kendi klasörünü kullanır.
        $Script:OlcumDosyasi = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '\olcumler.json')
    }
    AfterEach {
        $Script:OlcumDosyasi = $Script:EskiOlcumDosyasi
    }

    function Yeni-Hedef($Alan, $IlkBayt, $Basarili = 3, $Deneme = 3) {
        [pscustomobject]@{ Alan = $Alan; Deneme = $Deneme; Basarili = $Basarili; DnsMs = 10; TcpMs = 20; TlsMs = 30
            SunucuMs = 40; IlkBaytMs = $IlkBayt; IlkBaytP90Ms = $IlkBayt; VerimBps = $null }
    }
    function Yeni-Kayit($Zaman, $Hedefler, $Hizmet = 'Running', $Profil = 'modern-9') {
        [pscustomobject]@{ Zaman = $Zaman; Tekrar = 3; Hizmet = $Hizmet; Profil = $Profil; Hedefler = @($Hedefler) }
    }

    It 'özetten yalnızca sayısal alanlı kayıt üretir ve bağlamı ekler' {
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = 'Running' } }
        Mock Read-Ayarlar { [pscustomobject]@{ profil = 'modern-9' } }
        $olcum = Get-HizOlcumuSonucu 'a.example' '200|0.010000|0.030000|0.090000|0.200000|0.3|2000000.0|500000' 0
        $kayit = ConvertTo-OlcumKaydi @(Get-HizOzeti 'a.example' @($olcum)) 3
        $kayit.Hizmet | Should Be 'Running'
        $kayit.Profil | Should Be 'modern-9'
        $kayit.Tekrar | Should Be 3
        $kayit.Hedefler.Count | Should Be 1
        $kayit.Hedefler[0].Alan | Should Be 'a.example'
        $kayit.Hedefler[0].IlkBaytMs | Should Be 200
        $kayit.Hedefler[0].VerimBps | Should Be 2000000
        $null -ne (ConvertTo-BekciZamani $kayit.Zaman) | Should Be $true
    }
    It 'hizmet veya ayar okunamazsa bağlamı bilinmiyor olarak kaydeder' {
        Mock Get-GdpiHizmetBilgisi { throw 'Erişim reddedildi.' }
        Mock Read-Ayarlar { throw 'Okunamadı.' }
        $kayit = ConvertTo-OlcumKaydi @() 5
        $kayit.Hizmet | Should Be 'Unknown'
        $kayit.Profil | Should BeNullOrEmpty
    }
    It 'kaydı diske yazıp aynen okur (tek hedefli kayıt dizi olarak kalır)' {
        Add-OlcumKaydi (Yeni-Kayit '2026-11-01T10:00:00.0000000Z' (Yeni-Hedef 'a.example' 100))
        $g = @(Read-OlcumGecmisi)
        $g.Count | Should Be 1
        @($g[0].Hedefler).Count | Should Be 1
        $g[0].Hedefler[0].IlkBaytMs | Should Be 100
        $g[0].Hizmet | Should Be 'Running'
    }
    It 'dosya yokken boş döner' {
        @(Read-OlcumGecmisi).Count | Should Be 0
    }
    It 'en fazla sınır kadar kayıt tutar ve en eskileri atar' {
        $Script:OlcumEnFazlaKayit = 3
        try {
            1..5 | ForEach-Object {
                Add-OlcumKaydi (Yeni-Kayit ('2026-11-0{0}T10:00:00.0000000Z' -f $_) (Yeni-Hedef 'a.example' (100 * $_)))
            }
            $g = @(Read-OlcumGecmisi)
            $g.Count | Should Be 3
            $g[0].Hedefler[0].IlkBaytMs | Should Be 300
            $g[2].Hedefler[0].IlkBaytMs | Should Be 500
        } finally {
            $Script:OlcumEnFazlaKayit = 50
        }
    }
    It 'geçersiz kayıtları atlar, geçerlileri korur' {
        $yol = $Script:OlcumDosyasi
        New-Item -ItemType Directory -Force -Path (Split-Path $yol) | Out-Null
        $icerik = @{
            SemaSurumu = 1
            Kayitlar = @(
                (Yeni-Kayit '2026-11-01T10:00:00.0000000Z' (Yeni-Hedef 'iyi.example' 100)),
                @{ Zaman = 'tarih-degil'; Hedefler = @() },
                @{ Hedefler = @() },
                (Yeni-Kayit '2026-11-02T10:00:00.0000000Z' @(@{ Alan = 5; Deneme = 1; Basarili = 1 }))
            )
        } | ConvertTo-Json -Depth 6
        [IO.File]::WriteAllText($yol, $icerik)
        $uyarilar = New-Object 'System.Collections.Generic.List[string]'
        $g = @(Read-OlcumGecmisi $uyarilar)
        $g.Count | Should Be 1
        $g[0].Hedefler[0].Alan | Should Be 'iyi.example'
        $uyarilar.Count | Should Be 1
    }
    It 'bozuk dosyayı sessizce ezmez: okuma ve ekleme hata verir, dosya olduğu gibi kalır' {
        $yol = $Script:OlcumDosyasi
        New-Item -ItemType Directory -Force -Path (Split-Path $yol) | Out-Null
        [IO.File]::WriteAllText($yol, '{yarim')
        { Read-OlcumGecmisi } | Should Throw 'Ölçüm geçmişi okunamadı'
        { Add-OlcumKaydi (Yeni-Kayit '2026-11-01T10:00:00.0000000Z' (Yeni-Hedef 'a.example' 1)) } | Should Throw 'Ölçüm geçmişi okunamadı'
        [IO.File]::ReadAllText($yol) | Should Be '{yarim'
    }
    It 'desteklenmeyen şema sürümünü reddeder' {
        $yol = $Script:OlcumDosyasi
        New-Item -ItemType Directory -Force -Path (Split-Path $yol) | Out-Null
        [IO.File]::WriteAllText($yol, '{"SemaSurumu":99,"Kayitlar":[]}')
        { Read-OlcumGecmisi } | Should Throw 'şema sürümü desteklenmiyor'
    }
    It 'kullanıcı klasörü bilinmiyorsa yazmaz' {
        $Script:OlcumDosyasi = $null
        { Read-OlcumGecmisi } | Should Throw 'LOCALAPPDATA'
    }
    It 'belirgin iyileşmeyi, belirgin yavaşlamayı ve gürültü düzeyindeki farkı ayırt eder' {
        $once = Yeni-Kayit '2026-11-01T10:00:00.0000000Z' @(
            (Yeni-Hedef 'hizli.example' 200), (Yeni-Hedef 'yavas.example' 200), (Yeni-Hedef 'gurultu.example' 200),
            (Yeni-Hedef 'kucuk.example' 40), (Yeni-Hedef 'yok.example' $null), (Yeni-Hedef 'sadece-eski.example' 100))
        $simdi = Yeni-Kayit '2026-11-02T10:00:00.0000000Z' @(
            (Yeni-Hedef 'hizli.example' 120), (Yeni-Hedef 'yavas.example' 300), (Yeni-Hedef 'gurultu.example' 215),
            (Yeni-Hedef 'kucuk.example' 70), (Yeni-Hedef 'yok.example' 100), (Yeni-Hedef 'yeni.example' 100))
        $f = @{}
        foreach ($x in @(Compare-OlcumKayitlari $once $simdi)) { $f[$x.Alan] = $x }
        $f.Count | Should Be 5
        $f['hizli.example'].Sonuc | Should Be 'daha-hizli'
        $f['hizli.example'].FarkMs | Should Be -80
        $f['hizli.example'].Yuzde | Should Be -40
        $f['yavas.example'].Sonuc | Should Be 'daha-yavas'
        $f['gurultu.example'].Sonuc | Should Be 'belirgin-degil'
        # 30 ms değişim ama %75: ms eşiğini geçer, yüzde geçer -> belirgin; 70-40=30 ms ve %75
        $f['kucuk.example'].Sonuc | Should Be 'daha-yavas'
        $f['yok.example'].Sonuc | Should Be 'karsilastirilamadi'
    }
    It 'yüzde yüksek ama mutlak fark küçükse belirgin saymaz' {
        $once = Yeni-Kayit '2026-11-01T10:00:00.0000000Z' (Yeni-Hedef 'a.example' 10)
        $simdi = Yeni-Kayit '2026-11-02T10:00:00.0000000Z' (Yeni-Hedef 'a.example' 25)
        (@(Compare-OlcumKayitlari $once $simdi))[0].Sonuc | Should Be 'belirgin-degil'
    }
    It 'karşılaştırma satırı yönü ve başarı oranı değişimini yazar' {
        $once = Yeni-Kayit '2026-11-01T10:00:00.0000000Z' (Yeni-Hedef 'a.example' 200 3 3)
        $simdi = Yeni-Kayit '2026-11-02T10:00:00.0000000Z' (Yeni-Hedef 'a.example' 100 2 3)
        $satir = Format-OlcumFarki (@(Compare-OlcumKayitlari $once $simdi))[0]
        $satir | Should Match 'a.example: ilk bayt 200 -> 100 ms'
        $satir | Should Match 'daha hızlı'
        $satir | Should Match 'başarı 3/3 -> 2/3'
    }
    It 'hiçbir hedef ölçülemediyse kaydetmez' {
        Mock Get-GdpiHizmetBilgisi { $null }
        Mock Read-Ayarlar { $null }
        Mock Uyari { }
        $olcum = Get-HizOlcumuSonucu 'a.example' '000|0|0|0|0|5|0|0' 6
        Save-HizOlcumu @(Get-HizOzeti 'a.example' @($olcum)) 3 | Should Be $false
        Test-Path -LiteralPath $Script:OlcumDosyasi | Should Be $false
    }
    It 'ikinci kayıtta öncekiyle karşılaştırır ve bağlam değişimini bildirir' {
        $durum = @{ Hizmet = 'Stopped' }
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = $durum.Hizmet } }
        Mock Read-Ayarlar { [pscustomobject]@{ profil = 'modern-9' } }
        Mock Baslik { }
        Mock Basari { }
        Mock Uyari { }
        Mock Yaz { }
        $hizli = Get-HizOlcumuSonucu 'a.example' '200|0.010000|0.030000|0.090000|0.400000|0.5|1|1' 0
        Save-HizOlcumu @(Get-HizOzeti 'a.example' @($hizli)) 3 | Should Be $true
        $durum.Hizmet = 'Running'
        $hizli2 = Get-HizOlcumuSonucu 'a.example' '200|0.010000|0.030000|0.090000|0.200000|0.3|1|1' 0
        Save-HizOlcumu @(Get-HizOzeti 'a.example' @($hizli2)) 3 | Should Be $true
        @(Read-OlcumGecmisi).Count | Should Be 2
        Assert-MockCalled Yaz -Scope It -ParameterFilter { $Metin -match 'hizmet Stopped -> Running' }
        Assert-MockCalled Basari -Scope It -ParameterFilter { $Metin -match 'daha hızlı' }
    }
    It 'geçmişi listeler; kayıt yoksa bunu söyler' {
        Mock Baslik { }
        Mock Yaz { }
        Invoke-OlcumGecmisi
        Assert-MockCalled Yaz -Scope It -ParameterFilter { $Metin -match 'Kayıtlı ölçüm yok' }
        Add-OlcumKaydi (Yeni-Kayit '2026-11-01T10:00:00.0000000Z' (Yeni-Hedef 'a.example' 100))
        Invoke-OlcumGecmisi
        Assert-MockCalled Yaz -Scope It -ParameterFilter { $Metin -match 'a.example: ilk bayt 100 ms \(3/3 başarılı\)' }
    }
}

Describe 'DNS gecikme sıralaması' {
    function Yeni-Siralama($Iyi, $Kotu = @()) {
        [pscustomobject]@{ Kullanilabilir = @($Iyi); Kullanilamaz = @($Kotu) }
    }
    function Yeni-Olcum($Ad, $V4, $Port, $Ortanca, $Engelli = $false) {
        [pscustomobject]@{
            Aday = @{ Ad = $Ad; V4 = $V4; V6 = '2001:db8::1'; Port = $Port }
            Denenen = 3; Basarisiz = 0; Engelli = $Engelli; Kullanilabilir = (-not $Engelli)
            Ortanca = $Ortanca; P90 = $Ortanca; Sira = 0
        }
    }

    It 'ilk sorgusu yanıtsız adayı kullanılamaz sayar ve ölçümü orada keser' {
        Mock Resolve-UdpDns { @() }
        $aday = @{ Ad = 'Olu'; V4 = '192.0.2.1'; V6 = 'x'; Port = 53 }
        $o = Measure-DnsAdayi $aday @('a.example', 'b.example') 3
        $o.Kullanilabilir | Should Be $false
        $o.Denenen | Should Be 1
        Assert-MockCalled Resolve-UdpDns -Times 1 -Exactly -Scope It
    }
    It 'engelli adres döndüren adayı eler' {
        Mock Resolve-UdpDns { @('195.175.254.2') }
        $aday = @{ Ad = 'Zehirli'; V4 = '192.0.2.2'; V6 = 'x'; Port = 53 }
        $o = Measure-DnsAdayi $aday @('a.example') 3
        $o.Engelli | Should Be $true
        $o.Kullanilabilir | Should Be $false
    }
    It 'aralıklı paket kaybını (yarıdan azı) tolere eder, ortancayı yanıtlananlardan hesaplar' {
        $script:DnsCagri = 0
        Mock Resolve-UdpDns {
            $script:DnsCagri++
            if ($script:DnsCagri -eq 2) { return @() }
            @('192.0.2.9')
        }
        $aday = @{ Ad = 'Kayipli'; V4 = '192.0.2.3'; V6 = 'x'; Port = 53 }
        $o = Measure-DnsAdayi $aday @('a.example') 4
        $o.Denenen | Should Be 4
        $o.Basarisiz | Should Be 1
        $o.Kullanilabilir | Should Be $true
        $o.Ortanca | Should Not BeNullOrEmpty
    }
    It 'sorguların yarısından fazlası yanıtsızsa adayı kullanılamaz sayar' {
        $script:DnsCagri = 0
        Mock Resolve-UdpDns {
            $script:DnsCagri++
            if ($script:DnsCagri -eq 1) { return @('192.0.2.9') }
            @()
        }
        $aday = @{ Ad = 'Cok-kayipli'; V4 = '192.0.2.4'; V6 = 'x'; Port = 53 }
        $o = Measure-DnsAdayi $aday @('a.example') 4
        $o.Basarisiz | Should Be 3
        $o.Kullanilabilir | Should Be $false
    }
    It 'adayları ortanca gecikmeye göre sıralar, yanıtsızı ayırır' {
        Mock Resolve-UdpDns {
            if ($Sunucu -eq '9.9.9.10') { Start-Sleep -Milliseconds 90; return @('192.0.2.9') }
            if ($Sunucu -eq '208.67.222.222') { Start-Sleep -Milliseconds 5; return @('192.0.2.9') }
            @()
        }
        $s = Get-DnsSiralamasi @('a.example') 2
        @($s.Kullanilabilir).Count | Should Be 2
        $s.Kullanilabilir[0].Aday.Ad | Should Be 'OpenDNS'
        $s.Kullanilabilir[1].Aday.Ad | Should Be 'Quad9 (filtresiz)'
        @($s.Kullanilamaz).Count | Should Be 1
        $s.Kullanilamaz[0].Aday.Ad | Should Be 'Yandex'
    }
    It 'mevcut sunucu en iyiden yeterince yavaş değilse değiştirmez (histerezis)' {
        $hizli = Yeni-Olcum 'Hizli' '1.1.1.1' 53 50
        $mevcut = Yeni-Olcum 'Mevcut' '2.2.2.2' 443 74
        $secim = Select-DnsAdayi (Yeni-Siralama @($hizli, $mevcut)) ([pscustomobject]@{ V4 = '2.2.2.2'; Port = [long]443 })
        $secim.Aday.Ad | Should Be 'Mevcut'
    }
    It 'mevcut sunucu eşiği aşacak kadar yavaşsa en hızlıya geçer' {
        $hizli = Yeni-Olcum 'Hizli' '1.1.1.1' 53 50
        $mevcut = Yeni-Olcum 'Mevcut' '2.2.2.2' 443 76
        $secim = Select-DnsAdayi (Yeni-Siralama @($hizli, $mevcut)) ([pscustomobject]@{ V4 = '2.2.2.2'; Port = 443 })
        $secim.Aday.Ad | Should Be 'Hizli'
    }
    It 'mevcut sunucu kullanılamıyorsa veya yoksa en hızlıyı seçer; hiç aday yoksa $null döner' {
        $hizli = Yeni-Olcum 'Hizli' '1.1.1.1' 53 50
        (Select-DnsAdayi (Yeni-Siralama @($hizli)) ([pscustomobject]@{ V4 = '9.9.9.9'; Port = 53 })).Aday.Ad | Should Be 'Hizli'
        (Select-DnsAdayi (Yeni-Siralama @($hizli)) $null).Aday.Ad | Should Be 'Hizli'
        Select-DnsAdayi (Yeni-Siralama @()) $null | Should BeNullOrEmpty
    }
    It 'Find-DnsSunucusu en hızlı adayı döndürür, kullanılamayanı uyarıyla bildirir' {
        Mock Test-GenelIPv6 { $false }
        Mock Uyari { }
        Mock Yaz { }
        Mock Get-DnsSiralamasi {
            Yeni-Siralama @((Yeni-Olcum 'Hizli' '1.1.1.1' 53 10), (Yeni-Olcum 'Yavas' '2.2.2.2' 443 40)) @(
                [pscustomobject]@{ Aday = @{ Ad = 'Olu'; V4 = '3.3.3.3'; Port = 1 }; Engelli = $false },
                [pscustomobject]@{ Aday = @{ Ad = 'Zehirli'; V4 = '4.4.4.4'; Port = 2 }; Engelli = $true })
        }
        $d = Find-DnsSunucusu @('a.example')
        $d.Ad | Should Be 'Hizli'
        $d.V4 | Should Be '1.1.1.1'
        $d.Port | Should Be 53
        $d.V6Etkin | Should Be $false
        Assert-MockCalled Uyari -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match '^Olu \(3.3.3.3:1\) kullanılamıyor' }
        Assert-MockCalled Uyari -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match '^Zehirli .* engelli adres döndürdü' }
    }
    It 'Find-DnsSunucusu mevcut sunucuyu histerezisle korur ve aday yoksa $null döner' {
        Mock Test-GenelIPv6 { $false }
        Mock Uyari { }
        Mock Yaz { }
        Mock Get-DnsSiralamasi {
            Yeni-Siralama @((Yeni-Olcum 'Hizli' '1.1.1.1' 53 50), (Yeni-Olcum 'Mevcut' '2.2.2.2' 443 60))
        }
        (Find-DnsSunucusu @('a.example') ([pscustomobject]@{ V4 = '2.2.2.2'; Port = 443 })).Ad | Should Be 'Mevcut'
        Mock Get-DnsSiralamasi { Yeni-Siralama @() }
        Find-DnsSunucusu @('a.example') | Should BeNullOrEmpty
    }
    It 'hiz -DnsSirala çıktısı sıralamayı ve kullanılamayanları gösterir, ayar değiştirmez' {
        Mock Baslik { }
        Mock Yaz { }
        Mock Basari { }
        Mock Uyari { }
        Mock Hata { }
        Mock Save-Ayarlar { throw 'Ayar yazılmamalı.' }
        Mock Get-DnsSiralamasi {
            Yeni-Siralama @((Yeni-Olcum 'Hizli' '1.1.1.1' 53 10), (Yeni-Olcum 'Yavas' '2.2.2.2' 443 40)) @(
                [pscustomobject]@{ Aday = @{ Ad = 'Olu'; V4 = '3.3.3.3'; Port = 1 }; Engelli = $false })
        }
        Invoke-DnsSiralamasi -Hedefler @('a.example') | Out-Null
        Assert-MockCalled Basari -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match '^1\. Hizli \(1.1.1.1:53\): ortanca 10 ms' }
        Assert-MockCalled Yaz -Scope It -ParameterFilter { $Metin -match '2\. Yavas' }
        Assert-MockCalled Uyari -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match 'Olu .* yanıt vermedi' }
        Assert-MockCalled Hata -Times 0 -Exactly -Scope It
    }
}

Describe 'Ölçüme dayalı profil seçimi' {
    function Yeni-Calisan($Ad, $Ortanca) { [pscustomobject]@{ Profil = @{ Ad = $Ad; Arg = '-x' }; Ortanca = $Ortanca } }

    It 'belirgin farkı yalnızca hem ms hem yüzde eşiği aşınca kabul eder' {
        Test-BelirginFark 100 60 | Should Be $true
        Test-BelirginFark 100 75 | Should Be $false
        Test-BelirginFark 200 160 | Should Be $true
        Test-BelirginFark 500 450 | Should Be $false
        Test-BelirginFark 0 0 | Should Be $false
        Test-BelirginFark 100 150 | Should Be $false
    }
    It 'profil hızını DNS hariç ölçer ve DoH adresini iletir' {
        Mock Invoke-HizOlcumu { Get-HizOlcumuSonucu $Alan '200|0.010000|0.030000|0.090000|0.110000|0.2|1|1' 0 }
        $h = Measure-ProfilHizi @('a.example', 'b.example') 'https://doh.example/dns-query' 2
        $h.Ortanca | Should Be 100
        $h.Denenen | Should Be 4
        $h.Olculen | Should Be 4
        Assert-MockCalled Invoke-HizOlcumu -Times 4 -Exactly -Scope It -ParameterFilter { $DohUrl -eq 'https://doh.example/dns-query' }
    }
    It 'örneklerin yarısından azı okunabildiyse hızı güvenilmez sayar' {
        $script:ProfilCagri = 0
        Mock Invoke-HizOlcumu {
            $script:ProfilCagri++
            if ($script:ProfilCagri -eq 1) { return Get-HizOlcumuSonucu $Alan '200|0.010000|0.030000|0.090000|0.110000|0.2|1|1' 0 }
            if ($script:ProfilCagri -eq 2) { throw 'curl yok' }
            Get-HizOlcumuSonucu $Alan '000|0|0|0|0|5|0|0' 28
        }
        $h = Measure-ProfilHizi @('a.example') 'https://doh.example/dns-query' 4
        $h.Denenen | Should Be 4
        $h.Olculen | Should Be 1
        $h.Ortanca | Should BeNullOrEmpty
    }
    It 'tek çalışan profili olduğu gibi seçer; aday yoksa $null döner' {
        (Select-ProfilAdayi @((Yeni-Calisan 'a' 100)) $null).Profil.Ad | Should Be 'a'
        Select-ProfilAdayi @() $null | Should BeNullOrEmpty
    }
    It 'fark belirgin değilse en güvenli (ilk) profili korur' {
        (Select-ProfilAdayi @((Yeni-Calisan 'guvenli' 100), (Yeni-Calisan 'hizli' 80)) $null).Profil.Ad | Should Be 'guvenli'
    }
    It 'başka profil belirgin hızlıysa onu seçer; eşitlikte güvenli olan kalır' {
        (Select-ProfilAdayi @((Yeni-Calisan 'guvenli' 200), (Yeni-Calisan 'orta' 120), (Yeni-Calisan 'hizli' 100)) $null).Profil.Ad | Should Be 'hizli'
        (Select-ProfilAdayi @((Yeni-Calisan 'guvenli' 200), (Yeni-Calisan 'a' 100), (Yeni-Calisan 'b' 100)) $null).Profil.Ad | Should Be 'a'
    }
    It 'güvenli profilin hızı ölçülemediyse karşılaştırma yapmadan onu seçer' {
        (Select-ProfilAdayi @((Yeni-Calisan 'guvenli' $null), (Yeni-Calisan 'hizli' 10)) $null).Profil.Ad | Should Be 'guvenli'
    }
    It 'kayıtlı profili belirgin yavaş değilse korur, belirgin yavaşsa bırakır' {
        $adaylar = @((Yeni-Calisan 'modern-9' 100), (Yeni-Calisan 'modern-7' 110))
        (Select-ProfilAdayi $adaylar 'modern-7').Profil.Ad | Should Be 'modern-7'
        $yavas = @((Yeni-Calisan 'modern-9' 100), (Yeni-Calisan 'modern-7' 135))
        (Select-ProfilAdayi $yavas 'modern-7').Profil.Ad | Should Be 'modern-9'
        (Select-ProfilAdayi $adaylar 'yok-boyle-profil').Profil.Ad | Should Be 'modern-9'
    }
}

Describe 'Invoke-Bul profil karşılaştırması' {
    BeforeEach {
        $script:SonProfil = $null
        $script:BaslatmaSayisi = 0
        $script:ProfilSonuc = @{}
        $script:KayitliAyar = $null
        Mock Baslik { }
        Mock Yaz { }
        Mock Basari { }
        Mock Uyari { }
        Mock Hata { }
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ StartMode = 'Auto'; State = 'Stopped' } }
        Mock Get-Hizmet { $null }
        Mock Get-YabanciGdpiSurecleri { @() }
        Mock Test-Internet { $true }
        Mock Find-Doh { 'https://doh.example/dns-query' }
        Mock Get-Ikililer { 'C:\sahte' }
        Mock Get-ListeDosyalari { @() }
        Mock Write-Liste { 'C:\sahte\liste.txt' }
        Mock Get-Iss { $null }
        Mock Read-Ayarlar { $script:KayitliAyar }
        Mock Find-DnsSunucusu { $null }
        Mock Test-Https { $true }
        Mock Start-GdpiGecici {
            $script:BaslatmaSayisi++
            $script:SonProfil = ($Argumanlar -split ' ')[0]
            [pscustomobject]@{ Id = 1 }
        }
        Mock Stop-GdpiGecici { $script:SonProfil = $null }
        Mock Test-Hedefler {
            $s = [ordered]@{}
            foreach ($h in $Hedefler) {
                $s[$h] = [bool]($script:SonProfil -and $script:ProfilSonuc.ContainsKey($script:SonProfil))
            }
            $s
        }
        Mock Measure-ProfilHizi { [pscustomobject]@{ Ortanca = $script:ProfilSonuc[$script:SonProfil]; Denenen = 3; Olculen = 3 } }
    }

    It 'ilk çalışandan sonra en çok iki ek aday dener ve belirgin hızlı olanı seçer' {
        $script:ProfilSonuc = @{ '-9' = 200; '-7' = 100; '-6' = 120; '-8' = 10 }
        $a = Invoke-Bul -Hedefler @('engelli.example') -Kaydetme
        $a.profil | Should Be 'modern-7'
        $script:BaslatmaSayisi | Should Be 3
    }
    It 'fark belirgin değilse en güvenli çalışan profilde kalır' {
        $script:ProfilSonuc = @{ '-9' = 100; '-7' = 95; '-6' = 90 }
        (Invoke-Bul -Hedefler @('engelli.example') -Kaydetme).profil | Should Be 'modern-9'
    }
    It 'ilk profiller başarısız olsa da karşılaştırma ilk çalışandan sonra başlar' {
        $script:ProfilSonuc = @{ '-7' = 100; '-6' = 90; '-8' = 40; '-5' = 10 }
        (Invoke-Bul -Hedefler @('engelli.example') -Kaydetme).profil | Should Be 'modern-8'
        $script:BaslatmaSayisi | Should Be 4
    }
    It 'riskli (--set-ttl) profilleri çalışan bir profil varken denemez' {
        $script:ProfilSonuc = @{ '-e' = 100 }
        (Invoke-Bul -Hedefler @('engelli.example') -Kaydetme).profil | Should Be 'sni-bolme'
        $script:BaslatmaSayisi | Should Be 6
    }
    It 'kayıtlı profil belirgin yavaş değilse korunur' {
        $script:KayitliAyar = [pscustomobject]@{ profil = 'modern-7'; dns = $null }
        $script:ProfilSonuc = @{ '-9' = 100; '-7' = 110 }
        (Invoke-Bul -Hedefler @('engelli.example') -Kaydetme).profil | Should Be 'modern-7'
    }
    It 'hiçbir profil çalışmazsa hata verir ve $null döner' {
        $script:ProfilSonuc = @{}
        Invoke-Bul -Hedefler @('engelli.example') -Kaydetme | Should BeNullOrEmpty
        Assert-MockCalled Hata -Scope It -ParameterFilter { $Metin -match 'Hiçbir profil engeli aşamadı' }
    }
    It 'engel yoksa profil denemez ve ilk profili seçer' {
        Mock Test-Hedefler { $s = [ordered]@{}; foreach ($h in $Hedefler) { $s[$h] = $true }; $s }
        (Invoke-Bul -Hedefler @('acik.example') -Kaydetme).profil | Should Be 'modern-9'
        $script:BaslatmaSayisi | Should Be 0
    }
}

Describe 'Sistem önerileri' {
    function Yeni-Adaptor($Ad, $Medya, $Hiz, $Durum = 'Up', $Duplex = $true, $Aciklama = 'Gercek Adaptor') {
        [pscustomobject]@{ Name = $Ad; MediaType = $Medya; Speed = $Hiz; Status = $Durum; FullDuplex = $Duplex; InterfaceDescription = $Aciklama }
    }
    function Yeni-Durum($Fiziksel = @(), $Tumu = $null, $Guc = '381b4222-f694-41f0-9685-ff5bb260df2e', $Proxy = $false) {
        if ($null -eq $Tumu) { $Tumu = $Fiziksel }
        [pscustomobject]@{ FizikselAgBagdastiricilari = $Fiziksel; TumAgBagdastiricilari = $Tumu; GucPlaniGuid = $Guc; ProxyAcik = $Proxy }
    }

    It '100 Mbps Ethernet için öneri üretir, gigabit için üretmez' {
        $o = @(Get-SistemOnerileri (Yeni-Durum @((Yeni-Adaptor 'Ethernet' '802.3' ([uint64]100000000)))))
        $o.Count | Should Be 1
        $o[0].Seviye | Should Be 'oneri'
        $o[0].Baslik | Should Match "Ethernet 100 Mbps'te bağlı"
        @(Get-SistemOnerileri (Yeni-Durum @((Yeni-Adaptor 'Ethernet' '802.3' ([uint64]1000000000))))).Count | Should Be 0
    }
    It 'hızı bilinmeyen veya bağlı olmayan bağdaştırıcı için öneri üretmez' {
        @(Get-SistemOnerileri (Yeni-Durum @((Yeni-Adaptor 'Ethernet' '802.3' $null)))).Count | Should Be 0
        @(Get-SistemOnerileri (Yeni-Durum @((Yeni-Adaptor 'Ethernet' '802.3' ([uint64]0))))).Count | Should Be 0
        @(Get-SistemOnerileri (Yeni-Durum @((Yeni-Adaptor 'Ethernet' '802.3' ([uint64]10000000) 'Disconnected')))).Count | Should Be 0
    }
    It 'yarım dupleks Ethernet için öneri üretir' {
        $o = @(Get-SistemOnerileri (Yeni-Durum @((Yeni-Adaptor 'Ethernet' '802.3' ([uint64]1000000000) 'Up' $false))))
        $o.Count | Should Be 1
        $o[0].Baslik | Should Match 'yarım dupleks'
    }
    It 'düşük Wi-Fi hızı için öneri üretir, yüksek hız için üretmez' {
        $o = @(Get-SistemOnerileri (Yeni-Durum @((Yeni-Adaptor 'Wi-Fi' 'Native 802.11' ([uint64]54000000)))))
        $o.Count | Should Be 1
        $o[0].Baslik | Should Match 'Wi-Fi bağlantı hızı düşük: 54 Mbps'
        @(Get-SistemOnerileri (Yeni-Durum @((Yeni-Adaptor 'Wi-Fi' 'Native 802.11' ([uint64]866000000))))).Count | Should Be 0
    }
    It 'birden fazla açık fiziksel bağdaştırıcıyı bilgi olarak bildirir' {
        $o = @(Get-SistemOnerileri (Yeni-Durum @((Yeni-Adaptor 'Ethernet' '802.3' ([uint64]1000000000)), (Yeni-Adaptor 'Wi-Fi' 'Native 802.11' ([uint64]866000000)))))
        $o.Count | Should Be 1
        $o[0].Seviye | Should Be 'bilgi'
        $o[0].Baslik | Should Match 'Ethernet, Wi-Fi'
    }
    It 'yalnızca açık VPN/tünel bağdaştırıcısını bildirir, sıradan bağdaştırıcıyı karıştırmaz' {
        $vpn = Yeni-Adaptor 'WireGuard' '802.3' ([uint64]1000000000) 'Up' $true 'WireGuard Tunnel'
        $kapali = Yeni-Adaptor 'NordLynx' '802.3' ([uint64]1000000000) 'Disconnected' $true 'NordLynx Tunnel'
        $normal = Yeni-Adaptor 'Ethernet' '802.3' ([uint64]1000000000) 'Up' $true 'Realtek PCIe GbE Family Controller'
        $o = @(Get-SistemOnerileri (Yeni-Durum @($normal) @($normal, $vpn, $kapali)))
        $o.Count | Should Be 1
        $o[0].Baslik | Should Match 'VPN/tünel bağdaştırıcısı etkin: WireGuard Tunnel'
    }
    It 'güç tasarrufu planını önerir, dengeli planı önermez' {
        $o = @(Get-SistemOnerileri (Yeni-Durum @() $null 'a1841308-3541-4fab-bc81-f71556f20b4a'))
        $o.Count | Should Be 1
        $o[0].Seviye | Should Be 'oneri'
        @(Get-SistemOnerileri (Yeni-Durum @() $null '381b4222-f694-41f0-9685-ff5bb260df2e')).Count | Should Be 0
    }
    It 'proxy açıksa bilgi verir, bilinmiyorsa susar' {
        $o = @(Get-SistemOnerileri (Yeni-Durum @() $null $null $true))
        $o.Count | Should Be 1
        $o[0].Baslik | Should Match 'proxy'
        @(Get-SistemOnerileri (Yeni-Durum @() $null $null $null)).Count | Should Be 0
    }
    It 'hiçbir bilgi toplanamadıysa hata vermeden boş döner' {
        $bos = [pscustomobject]@{ FizikselAgBagdastiricilari = $null; TumAgBagdastiricilari = $null; GucPlaniGuid = $null; ProxyAcik = $null }
        @(Get-SistemOnerileri $bos).Count | Should Be 0
    }
    It 'bağdaştırıcı sorgusu başarısız olsa da durum toplama hata vermez' {
        Mock Get-NetAdapter { throw 'Erişim reddedildi.' }
        $d = Get-SistemDurumu
        $d.FizikselAgBagdastiricilari | Should BeNullOrEmpty
        $d.TumAgBagdastiricilari | Should BeNullOrEmpty
    }
    It 'çıktıyı yazar: öneri uyarı, bilgi düz satır, hiçbiri yoksa dürüst bir not; ayar değiştirmez' {
        Mock Baslik { }
        Mock Yaz { }
        Mock Basari { }
        Mock Uyari { }
        Mock Save-Ayarlar { throw 'Ayar yazılmamalı.' }
        Mock Get-SistemDurumu {
            Yeni-Durum @((Yeni-Adaptor 'Ethernet' '802.3' ([uint64]100000000)), (Yeni-Adaptor 'Wi-Fi' 'Native 802.11' ([uint64]866000000)))
        }
        $o = @(Invoke-Oneriler)
        $o.Count | Should Be 2
        Assert-MockCalled Uyari -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match "Ethernet 100 Mbps'te bağlı" }
        Assert-MockCalled Yaz -Scope It -ParameterFilter { $Metin -match '^  \[i\] Birden fazla fiziksel' }
        Assert-MockCalled Basari -Times 0 -Exactly -Scope It
        Mock Get-SistemDurumu { Yeni-Durum @((Yeni-Adaptor 'Ethernet' '802.3' ([uint64]1000000000))) }
        Invoke-Oneriler | Out-Null
        Assert-MockCalled Basari -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match 'garanti etmez' }
    }
    It 'bağdaştırıcılar okunamazsa bunu açıkça bildirir' {
        Mock Baslik { }
        Mock Yaz { }
        Mock Basari { }
        Mock Uyari { }
        Mock Get-SistemDurumu {
            [pscustomobject]@{ FizikselAgBagdastiricilari = $null; TumAgBagdastiricilari = $null; GucPlaniGuid = $null; ProxyAcik = $null }
        }
        Invoke-Oneriler | Out-Null
        Assert-MockCalled Uyari -Times 1 -Exactly -Scope It -ParameterFilter { $Metin -match 'okunamadı' }
    }
}

Describe 'Bekçi kararlılığı' {
    $aday = @{ Ad = 'Test'; V4 = '192.0.2.53'; V6 = 'x'; Port = 53 }

    It 'tek kayıp paketi tekrar deneyerek tolere eder' {
        $script:DnsCagri = 0
        Mock Resolve-UdpDns {
            $script:DnsCagri++
            if ($script:DnsCagri -eq 1) { return @() }
            @('192.0.2.9')
        }
        Test-DnsSunucusu $aday @('a.example') 3 | Should Be $true
        $script:DnsCagri | Should Be 2
    }
    It 'varsayılan tek denemede eski davranışı korur' {
        Mock Resolve-UdpDns { @() }
        Test-DnsSunucusu $aday @('a.example') | Should Be $false
        Assert-MockCalled Resolve-UdpDns -Times 1 -Exactly -Scope It
    }
    It 'üç denemede de yanıt yoksa başarısız sayar' {
        Mock Resolve-UdpDns { @() }
        Test-DnsSunucusu $aday @('a.example', 'b.example') 3 | Should Be $false
        Assert-MockCalled Resolve-UdpDns -Times 3 -Exactly -Scope It
    }
    It 'engelli adres döndüren sunucuyu tekrar denemeden eler' {
        Mock Resolve-UdpDns { @('195.175.254.2') }
        Test-DnsSunucusu $aday @('a.example') 3 | Should Be $false
        Assert-MockCalled Resolve-UdpDns -Times 1 -Exactly -Scope It
    }
    It 'her hedefi ayrı doğrular' {
        Mock Resolve-UdpDns { if ($Alan -eq 'b.example') { @() } else { @('192.0.2.9') } }
        Test-DnsSunucusu $aday @('a.example', 'b.example') 2 | Should Be $false
        Test-DnsSunucusu $aday @('a.example') 2 | Should Be $true
    }

    It 'aynı profil ve DNS ise Test-AyniAyar doğru döner, herhangi bir fark yanlış döner' {
        $dns = @{ Ad = 'Quad9'; V4 = '9.9.9.10'; V6 = 'x'; Port = 9953; V6Etkin = $false }
        $eski = [pscustomobject]@{ profil = 'modern-9'; arg = '-9'; genel = $false; dns = [pscustomobject]@{ Ad = 'Quad9'; V4 = '9.9.9.10'; Port = [long]9953; V6Etkin = $false } }
        $ayni = [pscustomobject]@{ profil = 'modern-9'; arg = '-9'; genel = $false; dns = $dns }
        Test-AyniAyar $eski $ayni | Should Be $true
        Test-AyniAyar $eski ([pscustomobject]@{ profil = 'modern-7'; arg = '-7'; genel = $false; dns = $dns }) | Should Be $false
        Test-AyniAyar $eski ([pscustomobject]@{ profil = 'modern-9'; arg = '-9'; genel = $true; dns = $dns }) | Should Be $false
        $baskaDns = @{ Ad = 'OpenDNS'; V4 = '208.67.222.222'; V6 = 'x'; Port = 443; V6Etkin = $false }
        Test-AyniAyar $eski ([pscustomobject]@{ profil = 'modern-9'; arg = '-9'; genel = $false; dns = $baskaDns }) | Should Be $false
        Test-AyniAyar $eski ([pscustomobject]@{ profil = 'modern-9'; arg = '-9'; genel = $false; dns = $null }) | Should Be $false
        Test-AyniAyar ([pscustomobject]@{ profil = 'a'; arg = '-x'; genel = $false; dns = $null }) ([pscustomobject]@{ profil = 'a'; arg = '-x'; genel = $false; dns = $null }) | Should Be $true
        Test-AyniAyar $null $ayni | Should Be $false
    }

    Context 'yeniden profil araması' {
        BeforeEach {
            $script:BekciKayit = $null
            $script:Guncellenen = @()
            $script:Durum = [pscustomobject]@{
                ardisikHata = 1; sonYenidenBul = $null; durduruldu = $null; durdurmaNedeni = $null
                sonListe = (Get-Date).ToString('s'); sonListeDeneme = (Get-Date).ToString('s')
            }
            $script:MevcutAyar = [pscustomobject]@{
                profil = 'modern-9'; arg = '-9'; genel = $false; hedefler = @('x.example')
                dns = [pscustomobject]@{ Ad = 'Quad9'; V4 = '9.9.9.10'; Port = 9953; V6Etkin = $false }
            }
            Mock Get-Hizmet { [pscustomobject]@{ Status = 'Running' } }
            Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ StartMode = 'Auto' } }
            Mock Read-Ayarlar { $script:MevcutAyar }
            Mock Read-BekciDurumu { $script:Durum }
            Mock Save-Json { }
            Mock Yaz { }
            Mock Test-AgVar { $true }
            Mock Test-DnsSunucusu { $true }
            Mock Test-Internet { $true }
            Mock Test-Hedefler { $s = [ordered]@{}; foreach ($h in $Hedefler) { $s[$h] = $false }; $s }
            Mock Update-HizmetKomutu { $script:Guncellenen += $Ayar.profil }
            Mock Update-Liste { $false }
            Mock Start-Sleep { }
        }
        AfterEach { $Script:Sessiz = $false }

        It 'arama aynı sonucu verirse hizmeti yeniden başlatmaz ve sayacı sıfırlar' {
            Mock Invoke-Bul { [pscustomobject]@{ profil = 'modern-9'; arg = '-9'; genel = $false; hedefler = @('x.example')
                dns = @{ Ad = 'Quad9'; V4 = '9.9.9.10'; Port = 9953; V6Etkin = $false } } }
            Invoke-Bekci
            Assert-MockCalled Invoke-Bul -Times 1 -Exactly -Scope It
            @($script:Guncellenen).Count | Should Be 0
            $script:Durum.ardisikHata | Should Be 0
            Assert-MockCalled Yaz -Scope It -ParameterFilter { $Metin -match 'hizmet yeniden başlatılmadı' }
        }
        It 'arama farklı profil bulursa uygular' {
            Mock Invoke-Bul { [pscustomobject]@{ profil = 'modern-7'; arg = '-7'; genel = $false; hedefler = @('x.example')
                dns = @{ Ad = 'Quad9'; V4 = '9.9.9.10'; Port = 9953; V6Etkin = $false } } }
            Invoke-Bekci
            @($script:Guncellenen) -join ',' | Should Be 'modern-7'
            $script:Durum.ardisikHata | Should Be 0
        }
        It 'hizmeti 2. adım zaten yeniden başlattıysa aynı profil çıkınca tekrar başlatmaz' {
            $script:Durum.durduruldu = (Get-Date).AddHours(-7).ToString('s')
            $script:Durum.durdurmaNedeni = 'internet'
            $script:Durum.ardisikHata = 99
            Mock Get-Hizmet { [pscustomobject]@{ Status = 'Stopped' } }
            Mock Start-Service { }
            Mock Wait-HizmetDurumu { $true }
            Mock Invoke-Bul { [pscustomobject]@{ profil = 'modern-9'; arg = '-9'; genel = $false; hedefler = @('x.example')
                dns = @{ Ad = 'Quad9'; V4 = '9.9.9.10'; Port = 9953; V6Etkin = $false } } }
            Invoke-Bekci
            Assert-MockCalled Start-Service -Times 1 -Exactly -Scope It
            @($script:Guncellenen).Count | Should Be 0
        }
        It 'hizmet interneti bozduğu için durdurulduysa aynı profil çıksa da yeniden başlatmak için uygular' {
            $script:InternetCagri = 0
            Mock Test-Internet { $script:InternetCagri++; $script:InternetCagri -ge 2 }
            Mock Stop-Hizmet { }
            Mock Invoke-Bul { [pscustomobject]@{ profil = 'modern-9'; arg = '-9'; genel = $false; hedefler = @('x.example')
                dns = @{ Ad = 'Quad9'; V4 = '9.9.9.10'; Port = 9953; V6Etkin = $false } } }
            Invoke-Bekci
            @($script:Guncellenen) -join ',' | Should Be 'modern-9'
            $script:Durum.durduruldu | Should BeNullOrEmpty
        }
        It 'DNS denetimini üç denemeyle yapar' {
            $script:DnsDeneme = $null
            Mock Test-DnsSunucusu { $script:DnsDeneme = $Deneme; $true }
            Mock Test-Hedefler { $s = [ordered]@{}; foreach ($h in $Hedefler) { $s[$h] = $true }; $s }
            Invoke-Bekci
            $script:DnsDeneme | Should Be 3
        }
        It 'hedefler açılıyorsa profil aramaz' {
            Mock Test-Hedefler { $s = [ordered]@{}; foreach ($h in $Hedefler) { $s[$h] = $true }; $s }
            Mock Invoke-Bul { throw 'Arama yapılmamalı.' }
            Invoke-Bekci
            Assert-MockCalled Invoke-Bul -Times 0 -Exactly -Scope It
            $script:Durum.ardisikHata | Should Be 0
        }
    }
}

Describe 'hiz -AB' {
    It 'Compare-HizAb erişim açılmasını, kaybolmasını ve belirgin süre farkını ayırır' {
        $kapali = @(
            [pscustomobject]@{ Alan = 'engel.example'; Deneme = 3; Basarili = 0; IlkBayt = $null }
            [pscustomobject]@{ Alan = 'bozulan.example'; Deneme = 3; Basarili = 3; IlkBayt = [pscustomobject]@{ Ortanca = 100.0 } }
            [pscustomobject]@{ Alan = 'hizlanan.example'; Deneme = 3; Basarili = 3; IlkBayt = [pscustomobject]@{ Ortanca = 200.0 } }
            [pscustomobject]@{ Alan = 'benzer.example'; Deneme = 3; Basarili = 3; IlkBayt = [pscustomobject]@{ Ortanca = 200.0 } }
        )
        $acik = @(
            [pscustomobject]@{ Alan = 'engel.example'; Deneme = 3; Basarili = 3; IlkBayt = [pscustomobject]@{ Ortanca = 140.0 } }
            [pscustomobject]@{ Alan = 'bozulan.example'; Deneme = 3; Basarili = 0; IlkBayt = $null }
            [pscustomobject]@{ Alan = 'hizlanan.example'; Deneme = 3; Basarili = 3; IlkBayt = [pscustomobject]@{ Ortanca = 120.0 } }
            [pscustomobject]@{ Alan = 'benzer.example'; Deneme = 3; Basarili = 3; IlkBayt = [pscustomobject]@{ Ortanca = 190.0 } }
        )
        $f = @(Compare-HizAb $kapali $acik)
        $f.Count | Should Be 4
        ($f | Where-Object { $_.Alan -eq 'engel.example' }).Sonuc | Should Be 'erisim-acildi'
        ($f | Where-Object { $_.Alan -eq 'bozulan.example' }).Sonuc | Should Be 'erisim-kayboldu'
        ($f | Where-Object { $_.Alan -eq 'hizlanan.example' }).Sonuc | Should Be 'daha-hizli'
        ($f | Where-Object { $_.Alan -eq 'benzer.example' }).Sonuc | Should Be 'belirgin-degil'
        (Format-HizAbFarki ($f | Where-Object { $_.Alan -eq 'engel.example' })) | Should Match 'erişim açıldı'
    }

    It 'hizmet kurulu değilse veya duraklatılmışsa reddeder ve hizmete dokunmaz' {
        Mock Stop-Hizmet { throw 'Durdurmamalı.' }
        Mock Start-Service { throw 'Başlatmamalı.' }
        Mock Get-Hizmet { $null }
        { Invoke-HizAb -Hedefler @('x.example') -Tekrar 2 } | Should Throw 'kurulu değil'

        Mock Get-Hizmet { [pscustomobject]@{ Status = 'Stopped' } }
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = 'Stopped'; StartMode = 'Disabled' } }
        { Invoke-HizAb -Hedefler @('x.example') -Tekrar 2 } | Should Throw 'duraklatılmış'
        Assert-MockCalled Stop-Hizmet -Times 0 -Exactly -Scope It
        Assert-MockCalled Start-Service -Times 0 -Exactly -Scope It
    }

    It 'çalışan hizmette açık ve kapalı ölçüm yapar, sonunda hizmeti tekrar başlatır' {
        $script:HizmetDurum = 'Running'
        Mock Yaz { }
        Mock Start-Sleep { }
        Mock Get-Hizmet { [pscustomobject]@{ Status = $script:HizmetDurum } }
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = $script:HizmetDurum; StartMode = 'Auto' } }
        Mock Stop-Hizmet { $script:HizmetDurum = 'Stopped' }
        Mock Start-Service { $script:HizmetDurum = 'Running' }
        Mock Wait-HizmetDurumu { $true }
        Mock Invoke-Hiz {
            if ($script:HizmetDurum -eq 'Running') {
                return @([pscustomobject]@{ Alan = 'x.example'; Deneme = 2; Basarili = 2; IlkBayt = [pscustomobject]@{ Ortanca = 110.0 } })
            }
            return @([pscustomobject]@{ Alan = 'x.example'; Deneme = 2; Basarili = 0; IlkBayt = $null })
        }

        $r = Invoke-HizAb -Hedefler @('x.example') -Tekrar 2
        $r.BaslangicDurumu | Should Be 'Running'
        $r.Farklar[0].Sonuc | Should Be 'erisim-acildi'
        $script:HizmetDurum | Should Be 'Running'
        Assert-MockCalled Stop-Hizmet -Times 1 -Exactly -Scope It
        Assert-MockCalled Start-Service -Times 1 -Exactly -Scope It
    }

    It 'ölçüm sırasında hata olsa bile çalışan hizmeti finally bloğunda geri açar' {
        $script:HizmetDurum = 'Running'
        $script:Cagri = 0
        Mock Yaz { }
        Mock Start-Sleep { }
        Mock Get-Hizmet { [pscustomobject]@{ Status = $script:HizmetDurum } }
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = $script:HizmetDurum; StartMode = 'Auto' } }
        Mock Stop-Hizmet { $script:HizmetDurum = 'Stopped' }
        Mock Start-Service { $script:HizmetDurum = 'Running' }
        Mock Wait-HizmetDurumu { $true }
        Mock Invoke-Hiz {
            $script:Cagri++
            if ($script:Cagri -eq 2) { throw 'Ölçüm kesildi.' }
            return @([pscustomobject]@{ Alan = 'x.example'; Deneme = 2; Basarili = 2; IlkBayt = [pscustomobject]@{ Ortanca = 110.0 } })
        }

        { Invoke-HizAb -Hedefler @('x.example') -Tekrar 2 } | Should Throw 'Ölçüm kesildi.'
        $script:HizmetDurum | Should Be 'Running'
        Assert-MockCalled Start-Service -Times 1 -Exactly -Scope It
    }

    It 'durmuş hizmette kapalı ve açık ölçüm yapar, sonunda hizmeti tekrar durdurur' {
        $script:HizmetDurum = 'Stopped'
        Mock Yaz { }
        Mock Start-Sleep { }
        Mock Get-Hizmet { [pscustomobject]@{ Status = $script:HizmetDurum } }
        Mock Get-GdpiHizmetBilgisi { [pscustomobject]@{ State = $script:HizmetDurum; StartMode = 'Auto' } }
        Mock Stop-Hizmet { $script:HizmetDurum = 'Stopped' }
        Mock Start-Service { $script:HizmetDurum = 'Running' }
        Mock Wait-HizmetDurumu { $true }
        Mock Invoke-Hiz {
            if ($script:HizmetDurum -eq 'Running') {
                return @([pscustomobject]@{ Alan = 'x.example'; Deneme = 2; Basarili = 2; IlkBayt = [pscustomobject]@{ Ortanca = 100.0 } })
            }
            return @([pscustomobject]@{ Alan = 'x.example'; Deneme = 2; Basarili = 2; IlkBayt = [pscustomobject]@{ Ortanca = 220.0 } })
        }

        $r = Invoke-HizAb -Hedefler @('x.example') -Tekrar 2
        $r.BaslangicDurumu | Should Be 'Stopped'
        $r.Farklar[0].Sonuc | Should Be 'daha-hizli'
        $script:HizmetDurum | Should Be 'Stopped'
        Assert-MockCalled Start-Service -Times 1 -Exactly -Scope It
        Assert-MockCalled Stop-Hizmet -Times 1 -Exactly -Scope It
    }
}
