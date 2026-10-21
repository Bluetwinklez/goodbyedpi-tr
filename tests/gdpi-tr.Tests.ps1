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
        $dns = @{ V4 = '1.2.3.4'; V6 = '::1'; Port = 5353 }
        Get-GdpiArgumanlari -Profil '-5' -Dns $dns -Genel |
            Should Be '-5 --dns-addr 1.2.3.4 --dns-port 5353 --dnsv6-addr ::1 --dnsv6-port 5353'
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
    }
    It 'engel adresini tanır' {
        Test-EngelAdresi @('195.175.254.2') | Should Be $true
        Test-EngelAdresi @('162.159.135.232') | Should Be $false
    }
}

Describe 'Write-Liste' {
    It 'yorumları atar, tekrarları birleştirir, BOM yazmaz' {
        $kaynak = Join-Path $TestDrive 'k.txt'
        Set-Content $kaynak "# yorum`nDiscord.com  # satır sonu`n`ndiscord.com`nroblox.com" -Encoding UTF8
        $cikti = Write-Liste @($kaynak) @('ornek.com') (Join-Path $TestDrive 'o\liste.txt')
        $satirlar = Get-Content $cikti
        ($satirlar -join ',') | Should Be 'discord.com,roblox.com,ornek.com'
        ([IO.File]::ReadAllBytes($cikti)[0]) | Should Be ([byte][char]'d')
    }
}
