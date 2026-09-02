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

## OPEN ITEM — verify against a live tenant before publishing

**The resolver assumes `form_data.field_id` matches the form definition's field
`slug`.** This held across the spec's examples but was NOT verified against a
real tenant response — it's the linchpin of the whole custom-field feature. On
the first live call, pull one real request + its form and confirm the join key.
The code already falls back to field `id` if `slug` is absent; if the tenant
keys on `id` instead, it's a small change in `Get-UKGHRSDRequestFormData`.

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
