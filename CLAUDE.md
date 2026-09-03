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

## Current state (v0.2.0 — prepared for first PSGallery release)

30 Pester tests passing on PS 7.5.1, zero PSScriptAnalyzer findings under the
PSGallery ruleset (gated by the build script). `-Region ATL` (UKG-Ultipro US)
verified end-to-end against a prod tenant on 2026-09-02, including the
form-data resolver. Other regions still inferred from swagger + patterns.

Built and working:
- `Connect-UKGHRSD` / `Disconnect-UKGHRSD` — OAuth 2.0 client_credentials with
  automatic token refresh. `-Disconnect-UKGHRSD -Revoke` hits the
  `/revoke_token` endpoint.
- `Get-UKGHRSDRequest` — list/search requests, plus two single-item lookups:
  `-Id <uuid>` (internal UUID) and `-RequestNumber <int>` (the
  human-readable number shown in the UKG portal, e.g. `6678`). `-Id` with an
  all-digit value throws with a `-RequestNumber` hint before making the API
  call, catching the most common first-time-user mistake.
- `Get-UKGHRSDRequestForm` — list/search forms, plus `-Id <slug>` and
  `-Name <display-name>` lookups. `-Name` uses the API's full-text search
  (`q=`) with a default `-LanguageCode` of `en-us`; narrows client-side to
  exact-name match.
- `Get-UKGHRSDRequestFormField` — enumerates a form's fields as curated
  `[pscustomobject]`s (`FormId`, `Slug`, `Label`, `TypeId`, `Required`,
  `Multiple`, `Description`, `Placeholder`, `Items`, `Defaults`,
  `Validations`, `Raw`). Three input modes: piped form, `-FormId` (slug),
  `-FormName` (display name). Handles both Formidable and FaaS field
  shapes; `.Raw` preserves the untouched field object.
- `Get-UKGHRSDRequestFormData` — THE key cmdlet: resolves a request's raw
  `form_data` (`{field_id, values}`) into readable Label/Value pairs by
  joining to the form definition (verified live on ATL 2026-09-03). This
  is what makes the offboarding output usable.
- Private: `Invoke-UKGHRSDRequest`, `Get-UKGHRSDAccessToken`,
  `Get-UKGHRSDErrorMessage` (handles both OAuth 2.0 token errors —
  `{error, error_description}` per RFC 6749 §5.2 — and the HRSD API error
  shape — `{message, errors[]}` — so a failed connect surfaces
  `invalid_client: Client authentication failed` instead of a bare 401),
  `Resolve-UKGHRSDBaseUrl`.
- Pester tests in `Tests/` (HTTP mocked; no live tenant needed).

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

## OPEN ITEMS — live-tenant verification status

1. ~~**`form_data.field_id` == form definition's field `slug`?**~~ **Verified
   live 2026-09-03** — end-to-end resolver run against ATL prod tenant returned
   correctly labeled output, confirming the slug join. The `field.id` fallback
   in `Get-UKGHRSDRequestFormData` remains as a defensive guard.

2. `-Region ATL` (UKG-branded / Ultipro platform) → `https://apis.hrsd.ultipro.com`
   verified live on 2026-09-02. `-Region US`, `EU`, `TOR`, `StagingUS`, `StagingEU`
   still pending — mappings came from the swagger + inferred patterns for the
   staging entries. Called out in the manifest `ReleaseNotes` for v0.2.0 so
   PSGallery users know which regions are proven vs inferred.

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
- A 1.0.0 release once every shipped region has been live-tenant validated
  (see OPEN ITEMS — five regions still inferred from the swagger).

The full Swagger 2.0 spec (`ukghrsd_full.yml`, ~30k lines) was used to build
this. It stays tracked in git for future dev work but is excluded from the
PSGallery package by the build script's explicit shipping list. If extending
the module, get schemas from that spec, not third-party mirrors.

## Build / test

- Requires PowerShell 5.1+ or 7+. Dev/validated on 7.5.1.
- Import: `Import-Module ./UKGHRSD.psd1 -Force`
- List cmdlets: `Get-Command -Module UKGHRSD`
- Manifest check: `Test-ModuleManifest ./UKGHRSD.psd1`
- Tests: `Invoke-Pester ./Tests` (Pester 5+ required; 6+ tolerated — the tests
  file has a top-level `Remove-Module`/`Import-Module` guard so Pester 6's
  stricter discovery-time InModuleScope check doesn't fail when a PSGallery
  copy of UKGHRSD is also loaded).
- Before publishing: `Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSGallery`
  and fix warnings — or just let the build script do it (see below).

## Publish (PSGallery)

**Always publish through `Build/Publish-UKGHRSDModule.ps1`.** Running
`Publish-Module` against the repo root ships CLAUDE.md, Tests/, and the
~30k-line `ukghrsd_full.yml` swagger — all dev-only noise. The script
stages a clean copy at `Build/staging/UKGHRSD/` containing only the shipping
surface — `.psd1` / `.psm1` / `LICENSE` / `README.md` / `Public/*.ps1` /
`Private/*.ps1` — validates the staged manifest, runs Pester + PSScriptAnalyzer
against that copy, and then either prints the `Publish-Module` command
(default, dry-run) or runs it (with `-Publish -NuGetApiKey ...`).

```powershell
# Dry-run: stages + validates, prints the Publish-Module command.
./Build/Publish-UKGHRSDModule.ps1

# Real publish (paste the PSGallery key, or pull from SecretManagement).
./Build/Publish-UKGHRSDModule.ps1 -Publish -NuGetApiKey '<key>'
```

The staging directory (`Build/staging/`) is gitignored. Any change to what
should ship (new folder, new top-level file) goes in the `$topLevelFiles` /
subfolder loop inside the script — keep the shipping list explicit, not
"copy everything except X".

## Housekeeping

- `UKGHRSD.psd1` `ProjectUri`/`LicenseUri` and the actual repo location both
  live at `SuperCoreSolutions/UKGHRSD` (LLC GitHub org, confirmed 2026-09-02).
- MIT `LICENSE` file present at repo root.
- `.gitignore` at repo root excludes `*.secret` / `*.env` (never commit
  credentials — use `Get-Credential` / env vars), plus `Build/staging/`,
  `*.nupkg`, and editor cruft.
