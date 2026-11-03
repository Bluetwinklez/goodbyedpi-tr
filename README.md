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
.\gdpi-tr.ps1 liste-guncelle  # Refresh domain lists
.\gdpi-tr.ps1 doktor          # Diagnose conflicts
.\gdpi-tr.ps1 kaldir          # Remove the service and installed files
```

By default, processing is limited to listed domains. Add custom domains one per line in `listeler/kullanici.txt`, then reinstall. Avoid the broad `-Genel` option unless you understand its effect on unrelated traffic.

## Operation and recovery

The installer downloads upstream binaries and verifies their hashes. A scheduled watchdog checks connectivity, attempts supported recovery and stops the service if it disrupts general access. Configuration and logs are under `C:\Program Files\GoodbyeDPI-TR\veri`. The installation directory is restricted to administrators.

Use `kaldir` to uninstall; deleting the original download folder does not remove the running service. Inspect local logs before sharing them because they can describe your network and visited test destinations.

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
