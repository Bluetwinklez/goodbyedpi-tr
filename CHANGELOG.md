# Changelog

Bu dosya GoodbyeDPI-TR sürüm değişikliklerini özetler.

## [Unreleased] (v1.2.0 aday değişiklikleri — VM sürüm kapısı bekleniyor)

### Added
- **`hiz` ölçüm paketi:**
  - `hiz`: DNS, TCP, TLS, sunucu bekleme ve ilk bayt sürelerini ortanca/p90 olarak ölçer (yönetici gerekmez).
  - `hiz -Kaydet` / `hiz -Gecmis`: kullanıcı bazlı ölçüm geçmişi (`%LOCALAPPDATA%\GoodbyeDPI-TR\olcumler.json`, son 50 kayıt) ve 30 ms + %20 eşikli karşılaştırma.
  - `hiz -DnsSirala`: DNS adaylarını doğrudan UDP gecikmesine göre sıralar (salt okunur).
  - `hiz -Oneriler`: hızı sınırlayabilecek sistem ayarlarını salt okunur listeler.
  - `hiz -AB`: hizmet kapalı ve açıkken aynı hedefleri karşılaştırır (yönetici, ortak işlem kilidi ve `finally` geri yükleme ile).
  - `hiz -Indirme` / `-IndirmeUrl`: isteğe bağlı gerçek indirme verimi testi (deneme başına en çok 5 MB, 20 sn zaman aşımı, diske yazmaz).
- **Teşhis ve durum:**
  - `durum -Json`: yönetici izni ve ağ testi olmadan yapılandırılmış JSON durum çıktısı.
  - `rapor`: özel bilgi (IP, kullanıcı adı, tam yol, ham günlük) içermeyen çevrimdışı JSON teşhis raporu.
  - `duraklat` / `devam`: yeniden başlatma sonrası da korunan kalıcı duraklatma.
- **VM sürüm kapısı ve CI:**
  - `docs/VM_TEST_CHECKLIST.md` ve salt okunur kanıt betiği `scripts/vm-verify.ps1` (ACL, hizmet SDDL, reparse/junction, rapor gizlilik, 24 saat bekçi günlüğü analizi).
  - `.PSScriptAnalyzerSettings.psd1` ile sabitlenmiş `PSScriptAnalyzer 1.23.0` (`Error` + `Warning`, boş `catch` dahil) ve release etiketi ↔ `$Script:Surum` tutarlılık kontrolü.
  - Doğrulanabilir SHA-256 release ZIP paketi (`scripts/package-release.ps1`).

### Changed
- Profil seçimi ilk çalışan profilde durmak yerine güvenli adaylar arasında ölçülen hıza göre seçim yapar (`--set-ttl` profilleri yalnızca gerekirse denenir).
- DNS seçimi doğrudan UDP gecikme ölçümü ve histerezis (%20 + 15 ms) kullanır.
- Bekçi görevi DNS denetimini üç kez dener, profil/DNS değişmediyse hizmeti gereksiz yeniden başlatmaz ve başarısız liste güncellemesini 1 saat sonra yeniden dener.

### Security & Reliability
- Atomik JSON yazma + `.bak` yedekleme, bekçi durum şema doğrulaması ve ortak işlem kilidi (`Invoke-KilitliIslem`).
- Kurulum, yükseltme, görev/kısayol kaydı ve liste güncellemelerinde tam rollback.
- Yabancı GoodbyeDPI işlemlerini durdurmama ve paylaşılan WinDivert sürücüsünü kaldırmama koruması.
- Boş `catch` blokları temizlendi ve `PSAvoidUsingEmptyCatchBlock` CI'da etkinleştirildi.

## [1.1.1] - 2026-10-21

### Fixed
- Bekçi görevi bağlantı koparken hizmeti gereksiz yere durdurmuyor.

## [1.1.0] - 2026-10-21

### Added
- İlk genel sürüm: liste tabanlı GoodbyeDPI kurulumu, otomatik profil/DNS bulma, bekçi görevi, güvenli kaldırma ve SHA-256 ikili doğrulaması.
