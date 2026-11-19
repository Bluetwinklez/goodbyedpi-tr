# Repository security and maintenance audit

Date: 2026-11-03. Repository: `Bluetwinklez/goodbyedpi-tr`.

## Scope and method

PowerShell service-management source, domain lists and Windows test/release workflows.

Fetched the repository and scanned all locally fetched Git refs/history with Gitleaks 8.30.1 in fully redacted mode. Reviewed tracked sensitive-file patterns and personal-email candidates. Dependency audits describe the installed/resolved graph on this date; they are not a penetration test or a guarantee that no undiscovered vulnerability exists. Uploaded binaries, remote service configuration and files outside accessible Git refs are outside this scan.

## Changes

Replaced the main overview with English installation, recovery, requirements and limitations; retained the Turkish guide.

All maintained repositories receive an English security policy/audit entry point, a pinned and checksum-verified secret-scan workflow, credential ignore patterns and immutable action references. Existing publishing jobs retain their declared permissions. Known false positives, if any, are exempted only by exact historic finding fingerprints; no entire directory or credential rule is disabled.

## Credential and personal-data findings

No Gitleaks matches were found in fetched Git history.

No working private credential was confirmed in this review. No credential values are included in this report. If a real credential is discovered later, revoke it at its provider; deleting source cannot revoke a key or remove forks, caches or clones. Existing GitHub encrypted secrets were neither read nor copied. No live-account credential testing was attempted.

## Validation

Workflow syntax validated. Existing Windows CI contains Pester and PSScriptAnalyzer checks.

GitHub Actions YAML was checked with Actionlint. Local log files are kept outside the repositories; do not confuse historical README test counts with new results.

## Remaining limits

No local Windows service, driver installation or ISP connectivity test was performed in this Linux audit.

Main READMEs and new maintenance documents are English. Historical Turkish records and existing application translations remain; this maintenance does not claim a full UI translation. Changes are published in reviewable branches/PRs, not as an untested release.

## Suggested GitHub About description

Windows installer and service manager for GoodbyeDPI with connectivity checks and recovery for Turkish networks.

The current GitHub integration rejected repository metadata edits with HTTP 403. This prepared description can be applied when repository administration access is available; it has not been represented as an applied settings change.

## 19 November 2026 — Shared service and driver safety

A source review found that the profile probe stopped foreign GoodbyeDPI processes/services, installation removed the legacy service without an explicit opt-in, and uninstall could delete shared WinDivert services based only on a short process-name allowlist. These actions risk disrupting unrelated networking tools. The hardening branch now fails safely when another instance conflicts, requires an explicit legacy-service removal choice, and never uninstalls shared WinDivert drivers automatically. Added Pester regression tests for no foreign-process termination during probe and no legacy-service removal during installation. Hardware/driver behavior still requires an administrator-led Windows test.

## 19 November 2026 — Privacy-safe read-only diagnostics

Added an offline JSON diagnostic report accessible without administrator privileges. It exposes only service/watchdog status, profile and DNS provider names, application version and domain count, deliberately excluding raw logs, usernames, full paths, IP addresses and target domains. It does not perform network requests or modify Windows services. Added Pester coverage for privacy and malformed configuration. Report content should still be reviewed before public disclosure.
