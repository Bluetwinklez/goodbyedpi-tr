<#
.SYNOPSIS
  Builds a reproducible release layout and SHA-256 checksum for GoodbyeDPI-TR.
.DESCRIPTION
  Packages source scripts and documentation only. Upstream binaries are
  downloaded and hash-checked by gdpi-tr.ps1 during installation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version,
    [string]$OutputDirectory = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ad = "GoodbyeDPI-TR-$Version"
$hedef = [IO.Path]::GetFullPath($OutputDirectory)
$zip = Join-Path $hedef "$ad.zip"
$shaYolu = Join-Path $hedef "$ad.zip.sha256"
$gecici = Join-Path ([IO.Path]::GetTempPath()) ("gdpi-paket-" + [guid]::NewGuid().ToString('N'))
$paket = Join-Path $gecici $ad

$dosyalar = @('GoodbyeDPI-TR.cmd', 'gdpi-tr.ps1', 'README.md', 'README.tr.md', 'SECURITY.md', 'LICENSE')
foreach ($dosya in $dosyalar) {
    if (-not (Test-Path (Join-Path $root $dosya) -PathType Leaf)) {
        throw "Paket için gerekli dosya eksik: $dosya"
    }
}
$listeDizini = Join-Path $root 'listeler'
if (-not (Test-Path (Join-Path $listeDizini 'turkiye.txt') -PathType Leaf)) {
    throw 'Paket için listeler/turkiye.txt bulunamadı.'
}

try {
    New-Item -ItemType Directory -Path $hedef, $paket -Force | Out-Null
    foreach ($dosya in $dosyalar) {
        Copy-Item -LiteralPath (Join-Path $root $dosya) -Destination $paket -Force
    }
    Copy-Item -LiteralPath $listeDizini -Destination $paket -Recurse -Force
    Compress-Archive -LiteralPath $paket -DestinationPath $zip -CompressionLevel Optimal -Force
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $ad.zip" | Set-Content -LiteralPath $shaYolu -Encoding ASCII
    Write-Output $zip
    Write-Output $shaYolu
} finally {
    if (Test-Path $gecici) { Remove-Item -LiteralPath $gecici -Recurse -Force -ErrorAction SilentlyContinue }
}
