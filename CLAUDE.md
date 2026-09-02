# CLAUDE.md — UKGHRSD

Project context for Claude Code sessions. Read this first.

## What this is

A public PowerShell module wrapping the **UKG HR Service Delivery (HRSD)** REST
API v2 (People-Doc platform). Companion to the separate **UKGPro** module (UKG
Pro HCM). They are intentionally separate repos/modules — different platform,
auth, and base URL. Do not merge them.

Owner: Don Sheehan / Super Core Solutions LLC.
Primary use case driving design: **offboarding / IAM automation** — retrieving
manager-submitted offboarding requests and resolving the answers they entered
into custom form fields (e.g. "employee has a corporate credit card to
retrieve") into readable label/value output.

Distribution goal: GitHub source repo + publish to the PowerShell Gallery.

## Current state (v0.1.0)

Scaffolded, imports clean, manifest valid, core logic validated on
PowerShell 7.4.6. Read-only first pass (connect + Get- cmdlets); write cmdlets
come later.

Built and working:
- `Connect-UKGHRSD` / `Disconnect-UKGHRSD`
- `Get-UKGHRSDRequest` — list/search requests, or one by `-Id`
- `Get-UKGHRSDRequestForm` — form definitions (field labels/types)
- `Get-UKGHRSDRequestFormData` — THE key cmdlet: resolves a request's raw
  `form_data` (`{field_id, values}`) into readable Label/Value pairs by joining
  to the form definition. This is what makes the offboarding output usable.
- Private: `Invoke-UKGHRSDRequest`, `Get-UKGHRSDAccessToken`,
  `Get-UKGHRSDErrorMessage`, `Resolve-UKGHRSDBaseUrl`
- Pester tests in `Tests/` (HTTP mocked; no live tenant needed)

## Architecture / conventions (follow these when adding cmdlets)

- **One function per file.** Public cmdlets in `Public/`, internal helpers in
  `Private/`. `UKGHRSD.psm1` dot-sources both and exports only `Public/`.
- **Every new public cmdlet must be added to `FunctionsToExport` in
  `UKGHRSD.psd1`** — explicit list, not a wildcard.
- **All API calls route through `Invoke-UKGHRSDRequest`.** It owns the bearer
  token, auto-refresh, cursor pagination, and error handling. Don't call
  Invoke-WebRequest/RestMethod directly from a cmdlet.
- Session stored module-private in `$script:UKGHRSDSession`. Never global.
- Keep comment-based help on every public cmdlet.

## Auth model

OAuth 2.0 **client_credentials** flow:
- `Connect-UKGHRSD` takes a `-Region`, a `-Credential` (UserName =
  application_id, Password = application_secret), and `-ClientId`.
- `Get-UKGHRSDAccessToken` POSTs to `{base}/api/v2/client/tokens` with Basic
  auth (application_id:application_secret) + body
  `grant_type=client_credentials&scope=client&client_id=...`.
- Token stored with an absolute `ExpiresAt`. `Invoke-UKGHRSDRequest` refreshes
  it proactively (60s safety window) before calls. Bearer token on all requests.
- `Disconnect-UKGHRSD -Revoke` hits the revoke_token endpoint.

Region → base URL is in `Resolve-UKGHRSDBaseUrl` (US/EU People-Doc, ATL/TOR
UKG-Ultipro, plus staging). Credentials (application_id/secret, client_id) come
from the UKG IPM/Project Manager team.

## Pagination

Cursor-based via `Next-Cursor` response header (NOT page/per_Page — that's the
Pro module). `Invoke-UKGHRSDRequest` follows cursors automatically and
aggregates; `-MaxResults` caps totals, `-NoPaging` returns a single page.

## How the offboarding resolver works (the core value)

A request's manager-entered answers arrive as opaque `{field_id, values}` pairs
in `form_data`. `Get-UKGHRSDRequestFormData`:
1. Reads the request's `form_id`.
2. Fetches that form's definition (via `Get-UKGHRSDRequestForm`), cached per
   form_id so a batch of requests only fetches each form once.
3. Joins each answer's `field_id` to the field's `label` + `type` from
   `form_definition.fields`, keyed on the field `slug`.
Output: Label/Value objects (single values collapsed to scalars, multi-value
kept as arrays).

## OPEN ITEMS — verify against a live tenant before publishing

1. **`form_data.field_id` == form definition's field `slug`?** Held across the
   spec's examples but not verified against a real tenant response — linchpin
   of the whole custom-field feature. On the first live call, pull one real
   request + its form and confirm the join key. Code already falls back to
   field `id` if `slug` is absent; if the tenant keys on `id` instead, it's a
   small change in `Get-UKGHRSDRequestFormData`.

2. `-Region ATL` (UKG-branded / Ultipro platform) → `https://apis.hrsd.ultipro.com`
   verified live on 2026-09-02. `-Region US`, `EU`, `TOR`, `StagingUS`, `StagingEU`
   still pending — mappings came from the swagger + inferred patterns for the
   staging entries.

### Region-picking guidance (learned from the ATL debugging session)

HRSD runs on two distinct platforms and the module surfaces both. Users
consistently guess wrong on their first connect because the platform their
tenant lives on isn't obvious from the customer side — the classic failure
mode is a UKG-branded tenant assuming `-Region US` (People-Doc URL), getting
a 401, and thinking their credentials are bad.

  - UKG-branded / post-acquisition tenants (the current default for new UKG
    customers): `-Region ATL` (US) / `-Region TOR` (Canada). Base URL prefix:
    `apis.hrsd.ultipro`.
  - Legacy People-Doc-branded tenants: `-Region US` / `-Region EU`. Base URL
    prefix: `apis.*.people-doc.com`.

The URL prefix from the IPM contact is the definitive tell. README and
Connect-UKGHRSD comment-based help document this — if you add a new region,
mirror the guidance in both places.

## Roadmap (next work)

- Write cmdlets: `New-UKGHRSDRequest`, `Set-UKGHRSDRequest`, comments,
  attachments. `Invoke-UKGHRSDRequest` already supports Post/Patch + JSON body.
- Additional read cmdlets as needed: employees, documents, processes/tasks.
- Then PSGallery publish (after live-tenant validation + `PSScriptAnalyzer`).

The full Swagger 2.0 spec (`full.yml`, ~30k lines) was used to build this. If
extending, get schemas from that spec, not third-party mirrors.

## Build / test

- Requires PowerShell 5.1+ or 7+. Dev/validated on 7.4.6.
- Import: `Import-Module ./UKGHRSD.psd1 -Force`
- List cmdlets: `Get-Command -Module UKGHRSD`
- Manifest check: `Test-ModuleManifest ./UKGHRSD.psd1`
- Tests: `Invoke-Pester ./Tests` (install Pester 5+ first if needed)
- Before publishing: `Invoke-ScriptAnalyzer -Path . -Recurse` and fix warnings.

## Housekeeping

- `UKGHRSD.psd1` `ProjectUri`/`LicenseUri` and the actual repo location both
  live at `SuperCoreSolutions/UKGHRSD` (LLC GitHub org, confirmed 2026-09-02).
- MIT `LICENSE` file present at repo root.
- Never commit credentials. Use `Get-Credential` / env vars. **No `.gitignore`
  at repo root yet — add one that excludes `*.secret` / `*.env` before the
  first PSGallery publish.**
