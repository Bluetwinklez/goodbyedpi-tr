# GoodbyeDPI-TR

A Windows installation and management wrapper for [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI), intended for Turkish network conditions. It selects connection profiles, manages the Windows service and checks connectivity after changes.

This is not a VPN: it does not encrypt traffic or hide your IP address. Results depend on the ISP, destination and network configuration.

## Install and use

Download a ZIP from [Releases](https://github.com/Bluetwinklez/goodbyedpi-tr/releases), extract it and open `GoodbyeDPI-TR.cmd`. Installation requires administrator privileges because it changes a system service and network settings.

The command names remain Turkish:

```powershell
.\gdpi-tr.ps1 bul             # Find a working profile and DNS server
.\gdpi-tr.ps1 kur             # Install the service
.\gdpi-tr.ps1 durum           # Show current state
.\gdpi-tr.ps1 durum -Json     # Read structured status without elevation or network tests
.\gdpi-tr.ps1 hiz -Tekrar 5   # Measure connection stage timings (no elevation, changes nothing)
.\gdpi-tr.ps1 hiz -Kaydet     # ...and save the result, comparing it with the previous saved run
.\gdpi-tr.ps1 hiz -Gecmis     # List saved measurements
.\gdpi-tr.ps1 hiz -DnsSirala  # Rank the DNS server candidates by latency (changes nothing)
.\gdpi-tr.ps1 hiz -Oneriler   # List system settings that may limit speed (read-only)
.\gdpi-tr.ps1 hiz -AB         # Compare the same targets with the service off and on (needs elevation)
.\gdpi-tr.ps1 hiz -Indirme    # Opt-in download throughput test (up to 5 MB/run to NUL; optional -IndirmeUrl)
.\gdpi-tr.ps1 alan-listele    # List custom domains in kullanici.txt (no elevation; supports -Json)
.\gdpi-tr.ps1 alan-ekle -Hedef example.com  # Add a custom domain and refresh the active list
.\gdpi-tr.ps1 alan-sil -Hedef example.com   # Remove a custom domain and refresh the active list
.\gdpi-tr.ps1 duraklat        # Pause the service across reboots
.\gdpi-tr.ps1 devam           # Resume the service
.\gdpi-tr.ps1 liste-guncelle  # Refresh domain lists
.\gdpi-tr.ps1 doktor          # Diagnose conflicts
.\gdpi-tr.ps1 kaldir          # Remove the service and installed files
```

By default, processing is limited to listed domains. Before the first installation, add custom domains one per line in `listeler/kullanici.txt`. For an existing installation, edit the copy under the installation directory as administrator, then reinstall. Reinstalling preserves that installed copy. Avoid the broad `-Genel` option unless you understand its effect on unrelated traffic.

If an older GoodbyeDPI service is installed, remove it using its own uninstaller before installing GoodbyeDPI-TR. If a separate GoodbyeDPI process is running, close it before running profile detection.

## Operation and recovery

The installer downloads upstream binaries and verifies their hashes. A scheduled watchdog checks connectivity, attempts supported recovery and stops the service if it disrupts general access. Configuration and logs are under `C:\Program Files\GoodbyeDPI-TR\veri`. The installation directory is restricted to administrators.

`hiz` is not a line-speed test and cannot raise your bandwidth. For each target (the listed defaults plus two control sites) it makes `-Tekrar` HTTPS requests and reports the median and p90 of DNS, TCP, TLS, server wait and time to first byte. A throughput figure appears only when the sample is large enough to be meaningful. A DNS time of 0 ms usually means the system resolver answered from its cache. The TCP time can be blank when the resolver answered after the connection had already started; the other timings stay valid. The command contacts those sites directly and stores nothing unless you pass `-Kaydet`. With `-Kaydet` it appends a numeric summary (medians, p90, success counts, service state and profile name, no IPs or paths) to `%LOCALAPPDATA%\GoodbyeDPI-TR\olcumler.json`, keeps the latest 50 runs, and compares the first-byte time with the previous saved run. Only changes of at least 30 ms and 20% are called faster or slower; smaller differences are reported as possible noise. This file is per user and is never read by the watchdog. `durum -Json` reports the latest saved run as `SonOlcum`.

When the profile search picks a DNS server it now measures every candidate directly over UDP (no OS cache involved), requires the first query for each target to be answered, at least half of all queries to be answered and none to return a blocking address, and chooses the lowest median latency instead of the first one that works. A server that was already saved is kept unless it is slower than the best by more than 20% plus 15 ms, so small differences do not make it change. `hiz -DnsSirala` shows the same ranking without changing anything.

The watchdog only replaces the DNS server after three unanswered tries (one lost UDP packet is not a failure), and when its periodic profile search ends up with the same profile and DNS as the current ones it leaves the service running instead of restarting it.

`hiz -Oneriler` reads, without changing anything or needing elevation, a few things that commonly limit real-world speed and are outside this tool: an Ethernet link negotiated at 100 Mbps or half duplex, a slow Wi-Fi link rate, several active adapters, an active VPN/tunnel adapter, the Power saver plan and a system proxy. It prints possible causes only; finding nothing does not mean the connection is healthy, and no setting is ever changed.

When a DPI block has to be bypassed, the profile search no longer stops at the first profile that works. After the first working profile it also tries at most two more, never the riskier `--set-ttl` ones, and measures the time from connection setup to the first byte (DNS excluded) under each. The safest working profile is kept unless another one is faster by at least 30 ms and 20%; a profile that is already saved is kept unless it is that much slower. If a profile's speed could not be measured reliably, the safest working profile is used. Profile search needs administrator rights and the WinDivert driver, so this part is covered by automated tests with mocks and still needs a check on a real Windows machine.

Use menu option **8** to pause and **9** to resume. Windows keeps the service disabled across reboots while paused, and the watchdog skips its checks.

JSON state writes preserve the previous valid object in a sibling `.bak` file. If the current file is damaged, reads use that backup and display a warning. Review the recovered settings before applying a profile. Keep backups with the same access restrictions as the original files.

Use `kaldir` to uninstall; deleting the original download folder does not remove the running service. The installer and profile probe **refuse to stop or delete other GoodbyeDPI installations automatically**: if another instance is detected, stop or uninstall it yourself first. Uninstall removes this app's service and files but leaves shared WinDivert drivers intact so other networking tools are not disrupted. Inspect local logs before sharing them because they can describe your network and visited test destinations.

Uninstall preserves shared WinDivert registrations and retains the installed `bin` folder while a WinDivert driver is registered. It also leaves the older ProgramData data directory in place. If Windows is still deleting the service, close the Services console or reboot, then run uninstall again.

## Requirements and limitations

- Windows 10 version 1803 or newer, supported x86/x64 hardware and administrator access.
- ARM64 is not supported by the upstream driver used here.
- Discord voice uses UDP, which this DPI manipulation does not address.
- Some profiles disable QUIC across the system; network compatibility requires real-device checks.
- Automated script tests cannot establish that any profile works on your ISP.

## Development

Windows CI runs Pester 4.10.1 and PSScriptAnalyzer. See the workflow for the exact commands. The [Turkish guide](README.tr.md) retains detailed network behavior and historical manual measurements.

The wrapper is MIT licensed. Upstream GoodbyeDPI and WinDivert have their own licenses.

[Security policy](SECURITY.md) · [Repository security audit](SECURITY_AUDIT.md)

## Privacy-safe diagnostics

Run `./gdpi-tr.ps1 rapor` (no administrator privileges required) or choose menu option 10. A local `GoodbyeDPI-TR-rapor-*.json` file is written to the current user's temporary directory.

The read-only report contains the application version, service/watchdog status, selected profile, DNS provider name and active domain count. It **never includes raw logs, usernames, full filesystem paths, IP addresses or target domains**. No telemetry is uploaded, no connectivity checks are performed and no services are modified. Always review the JSON before sharing.

## Safer domain-list updates

The `liste-guncelle` command first validates the downloaded source, generates the merged list in a temporary file, and backs up both active files before applying them. If a running GoodbyeDPI-TR service fails to restart, both files are restored and an error is shown. The watchdog treats only successful updates as completed; on failure it retries after one hour instead of waiting a full day. Existing user domain lists are preserved. Manual validation on a Windows VM is still recommended before deploying a new release.

## Release archive integrity

Releases include the Turkish README, English README and security policy alongside the launcher and domain lists. Each versioned ZIP has a companion `.zip.sha256` manifest containing its SHA-256 digest.

Verify a downloaded release with PowerShell: `Get-FileHash -Algorithm SHA256 .\GoodbyeDPI-TR-vX.Y.Z.zip`. Compare the output to the corresponding `.zip.sha256` asset. Download and verify only official project releases.
