# GoodbyeDPI-TR

[![CI](https://github.com/Bluetwinklez/goodbyedpi-tr/actions/workflows/ci.yml/badge.svg)](https://github.com/Bluetwinklez/goodbyedpi-tr/actions/workflows/ci.yml)
[![Secret scanning](https://github.com/Bluetwinklez/goodbyedpi-tr/actions/workflows/secret-scan.yml/badge.svg)](https://github.com/Bluetwinklez/goodbyedpi-tr/actions/workflows/secret-scan.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> **[Türkçe Kılavuz (README.tr.md)](README.tr.md)** · **[Changelog](CHANGELOG.md)** · **[Security Policy](SECURITY.md)** · **[VM Test Checklist](docs/VM_TEST_CHECKLIST.md)**

A Windows installation, diagnostics, and service manager for [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI), designed for Turkish network conditions. It scopes DPI handling to listed domains, benchmarks DNS servers and safe profiles, runs a self-healing watchdog, and rolls back automatically on failure.

> **Not a VPN:** GoodbyeDPI-TR does not encrypt traffic or hide your IP address. It only addresses DNS and SNI-based filtering; it cannot bypass IP-based blocks. Results depend on your ISP, target site, and network setup.

---

## Quick Start

1. Download the latest release ZIP and `.zip.sha256` from [Releases](https://github.com/Bluetwinklez/goodbyedpi-tr/releases).
2. Verify the archive hash in PowerShell:
   ```powershell
   Get-FileHash -Algorithm SHA256 .\GoodbyeDPI-TR-vX.Y.Z.zip
   Get-Content .\GoodbyeDPI-TR-vX.Y.Z.zip.sha256
   ```
3. Extract the archive and double-click **`GoodbyeDPI-TR.cmd`** (requests administrator elevation).
4. Choose **1) Find working settings and install** from the menu.

After installation, the tool lives under `C:\Program Files\GoodbyeDPI-TR` with a Start Menu shortcut and an entry in Apps & Features; you can delete the extracted download folder.

---

## Commands

Command names remain Turkish. Most read-only commands work without elevation.

### Setup & Service Control

| Command | Elevation | Description |
|---|---|---|
| `.\gdpi-tr.ps1 bul` | Admin | Find the fastest safe profile and UDP DNS server |
| `.\gdpi-tr.ps1 kur` | Admin | Install or upgrade the Windows service and watchdog |
| `.\gdpi-tr.ps1 durum` | Admin | Show service, watchdog, profile, and live connectivity state |
| `.\gdpi-tr.ps1 durum -Json` | User | Structured status JSON without elevation or network tests |
| `.\gdpi-tr.ps1 duraklat` | Admin | Pause the service persistently across reboots (`Disabled`) |
| `.\gdpi-tr.ps1 devam` | Admin | Resume a paused service |
| `.\gdpi-tr.ps1 doktor` | Admin | Scan for conflicting VPNs, antivirus, or other DPI tools |
| `.\gdpi-tr.ps1 rapor` | User | Generate an offline, privacy-safe diagnostic JSON report |
| `.\gdpi-tr.ps1 kaldir` | Admin | Uninstall the service, watchdog, and app files safely |
| `.\gdpi-tr.ps1 kaldir -Eski` | Admin | Also remove a legacy `GoodbyeDPI` service |

### Speed & Connection Diagnostics (`hiz`)

All `hiz` modes support **`-Json`** for structured output (only `-AB` requires elevation):

| Command | Elevation | Description |
|---|---|---|
| `.\gdpi-tr.ps1 hiz [-Tekrar N]` | User | Measure DNS, TCP, TLS, server wait, and TTFB (median & p90) |
| `.\gdpi-tr.ps1 hiz -Kaydet` | User | Save a numeric summary locally and compare with the previous run |
| `.\gdpi-tr.ps1 hiz -Gecmis` | User | List saved local measurements (last 50 runs) |
| `.\gdpi-tr.ps1 hiz -DnsSirala` | User | Rank DNS candidates by direct UDP latency (read-only) |
| `.\gdpi-tr.ps1 hiz -Oneriler` | User | Check local speed limiters (link rate, VPN, power plan, proxy) |
| `.\gdpi-tr.ps1 hiz -AB` | Admin | Compare targets with service off vs on (locked, restores state) |
| `.\gdpi-tr.ps1 hiz -Indirme` | User | Opt-in throughput test (max 5 MB/run to `NUL`, optional `-IndirmeUrl`) |

### Domain Lists

| Command | Elevation | Description |
|---|---|---|
| `.\gdpi-tr.ps1 liste-guncelle` | Admin | Download, validate, and apply `turkiye.txt` with rollback |
| `.\gdpi-tr.ps1 alan-listele [-Json]` | User | List custom domains in `listeler/kullanici.txt` |
| `.\gdpi-tr.ps1 alan-ekle -Hedef example.com` | Admin | Add a custom domain and safely reload the running service |
| `.\gdpi-tr.ps1 alan-sil -Hedef example.com` | Admin | Remove a custom domain and safely reload the running service |

> **Interactive menu (`GoodbyeDPI-TR.cmd`):** Options **1–10** cover setup, status, doctor, list refresh, uninstall, pause (**8**), resume (**9**), and privacy report (**10**). Option **11** opens the **Speed & Diagnostics submenu**, and option **12** opens the **Custom Domain List submenu**.

---

## How It Works

### Scoped Filtering & Custom Domains
By default, GoodbyeDPI-TR only processes domains in `listeler/turkiye.txt` and `listeler/kullanici.txt` so banking, government, and gaming traffic stay unaffected. Manage custom domains with `alan-ekle` / `alan-sil` / `alan-listele` (or menu option **12**). Reinstalling always preserves your `kullanici.txt`. Avoid `-Genel` unless you understand its impact on unrelated traffic.

### Latency-Based DNS & Safe Profile Selection
- **DNS selection:** Measures each non-standard-port UDP DNS candidate directly (bypassing OS cache), rejects servers returning ISP block IPs, and picks the lowest median latency. An already saved server is kept unless another is faster by more than **20% + 15 ms**.
- **Profile selection:** After finding the first working profile, tests up to two additional safe profiles (never escalating to riskier `--set-ttl` profiles unnecessarily) and compares setup-to-first-byte latency. The safest working profile is kept unless another is faster by at least **30 ms and 20%**.

### Watchdog & Recovery
A `SYSTEM` scheduled task (`GoodbyeDPI-TR Bekci`) monitors the service at startup, every 15 minutes, and on network changes:
- **No network churn:** Skips changes when no network adapter is up, requires 3 consecutive UDP failures before switching DNS, and leaves the service running if a periodic profile re-check returns the same profile and DNS.
- **Persistent pause:** When paused (`duraklat` / menu **8**), the service stays `Disabled` across reboots and the watchdog skips all checks.
- **Transactional updates & `.bak` recovery:** Domain list updates and installs stage files first and roll back if the service fails to restart. JSON state writes keep the last valid object in a sibling `.bak` file.

### Speed Diagnostics Notes
- `hiz` measures connection stage timings, not ISP line speed, and cannot increase bandwidth. Only shifts of at least **30 ms and 20%** are labeled faster or slower; smaller changes are flagged as possible noise.
- `-Kaydet` writes numeric summaries only (no IPs or paths) to `%LOCALAPPDATA%\GoodbyeDPI-TR\olcumler.json`; this per-user file is never read by the `SYSTEM` watchdog.
- `hiz -AB` runs under the shared operation lock (`Invoke-KilitliIslem`), refuses if the service is missing or paused, and restores the original service state in `finally` even on interruption.
- `hiz -Indirme` is strictly opt-in, streams up to 5 MB per run to `NUL` (zero disk writes) with a 20 s timeout, and validates custom `-IndirmeUrl` inputs as strict `https://` URLs.

---

## Security & Safety

- **Verified upstream binaries:** Official `ValdikSS/GoodbyeDPI` archives and each extracted binary are verified against pinned SHA-256 hashes during installation.
- **Restricted installation path:** Configuration, binaries, and logs live under `C:\Program Files\GoodbyeDPI-TR` (administrator write-only), preventing standard users from tampering with `SYSTEM` tasks.
- **No foreign process interference:** `bul` and `kur` refuse to stop or delete other GoodbyeDPI installations automatically. `kaldir` removes only GoodbyeDPI-TR's own service/files and preserves shared `WinDivert` drivers when another registration exists.
- **Privacy-safe diagnostics (`rapor`):** Offline JSON report containing version, service/watchdog state, profile, DNS provider name, and domain count—never raw logs, usernames, full paths, IPs, or target domains.

See [SECURITY.md](SECURITY.md) and [SECURITY_AUDIT.md](SECURITY_AUDIT.md) for details.

---

## Requirements & Limitations

- Windows 10 (1803+) or Windows 11, x86 or x64 (built-in `curl.exe` required).
- **ARM64 is not supported** (upstream WinDivert has no ARM64 driver).
- Discord voice uses UDP, which GoodbyeDPI does not manipulate.
- Profiles with `-q` block QUIC (HTTP/3) system-wide; browsers fall back to TCP.
- Automated Pester tests mock Windows services and drivers; real Windows VM verification is tracked in [docs/VM_TEST_CHECKLIST.md](docs/VM_TEST_CHECKLIST.md).

---

## Development

```powershell
# Run unit tests
Invoke-Pester .\tests

# Run PSScriptAnalyzer with repository settings
Invoke-ScriptAnalyzer -Path .\gdpi-tr.ps1 -Settings .\.PSScriptAnalyzerSettings.psd1

# Run read-only VM verification evidence collector
.\scripts\vm-verify.ps1 -Asama sonrasi -CiktiDizini C:\vm-kanit
```

GitHub Actions runs Pester 4.10.1, PSScriptAnalyzer 1.23.0 (`Error` + `Warning`), release archive SHA-256 smoke tests, Gitleaks secret scanning, and release tag ↔ `$Script:Surum` verification.

## License

Scripts in this repository are licensed under the [MIT License](LICENSE). Upstream GoodbyeDPI (Apache-2.0) and WinDivert (LGPL-3.0 / GPL-2.0) carry their own licenses.
