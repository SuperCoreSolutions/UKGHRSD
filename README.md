# UKGHRSD

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A PowerShell module wrapping the **UKG HR Service Delivery (HRSD)** REST API v2 (People-Doc / Ultipro platforms). Provides typed `Get-` cmdlets for reading **People Assist requests** — for example, manager-submitted **offboarding** requests — with a shared OAuth `client_credentials` auth layer, cursor-based pagination, and a **form-data resolver** that turns opaque `{ field_id, values }` answers into readable `Label` / `Value` pairs so callers work with real field names instead of GUIDs.

Common use cases include offboarding automation, HR-request reporting, and pulling manager-entered custom-form answers into downstream workflows — but nothing in the module is tied to any single workflow. Any script that needs to read HRSD data can use it.

Companion to the separate [UKGPro](../UKGPro) module (which covers UKG Pro HCM). The two are intentionally separate: different platform, authentication, and base URL.

> Status: v0.2.0 — prepared for first PowerShell Gallery release. Read-only surface: `Connect`/`Disconnect` + four `Get-` cmdlets (including the form-data resolver). Write cmdlets (`Set-`/`New-`) planned for a later release; `-Region ATL` (UKG-Ultipro US) is the only region live-verified so far.

## Install

Not yet on PowerShell Gallery. Install from source:

```powershell
git clone https://github.com/SuperCoreSolutions/UKGHRSD.git
Import-Module ./UKGHRSD/UKGHRSD.psd1
```

Requires PowerShell 5.1+ or 7+.

## Authentication

HRSD uses the OAuth 2.0 `client_credentials` flow. Credentials (`application_id`, `application_secret`, `client_id`) are issued by your UKG HRSD Project Manager / IPM team.

`Connect-UKGHRSD` requests an application access token once and stores it in a module-private session, refreshing it proactively before expiry. Subsequent `Get-UKGHRSD*` cmdlets attach the token automatically — you never pass credentials on individual calls.

```powershell
# UserName = application_id, Password = application_secret
$cred = Get-Credential
Connect-UKGHRSD -Region ATL -Credential $cred -ClientId 'your-client-id'
```

### Picking the right `-Region`

HRSD runs on two distinct platforms. Which one your tenant lives on determines the base URL, and picking the wrong region will fail authentication with a `401` even when the credentials are correct.

| Region | Base URL | When to use it |
|---|---|---|
| `ATL` | `https://apis.hrsd.ultipro.com` | UKG-branded / post-acquisition tenants (US) — the current default for most UKG customers |
| `TOR` | `https://apis.hrsd.ultipro.ca` | UKG-branded tenants (Canada) |
| `US` | `https://apis.us.people-doc.com` | Legacy People-Doc-branded tenants (US) |
| `EU` | `https://apis.eu.people-doc.com` | Legacy People-Doc-branded tenants (EU) |
| `StagingUS` | `https://apis.staging.us.people-doc.com` | People-Doc non-production |
| `StagingEU` | `https://apis.staging.eu.people-doc.com` | People-Doc non-production |

**How to tell which one you have:** the domain the URL your IPM contact gives you starts with — `apis.hrsd.ultipro.{com,ca}` → `ATL`/`TOR`, `apis.*.people-doc.com` → `US`/`EU`/`Staging*`. When in doubt, ask IPM directly; they know which platform provisioned the tenant. If your IPM points you at a URL that doesn't match any of the entries above, open an issue and we'll add a region mapping.

## Cmdlets

| Cmdlet | Purpose |
|---|---|
| [`Connect-UKGHRSD`](#connect-ukghrsd) | Open an authenticated session (OAuth `client_credentials`) |
| [`Disconnect-UKGHRSD`](#disconnect-ukghrsd) | Clear the session, optionally revoke the token server-side |
| [`Get-UKGHRSDRequest`](#get-ukghrsdrequest) | List/search requests, or fetch one by internal UUID / portal number |
| [`Get-UKGHRSDRequestForm`](#get-ukghrsdrequestform) | Retrieve request form definitions (field labels/types); fetch one by `-Id` (slug) or `-Name` (display name, e.g. "Time Off & Accruals") |
| [`Get-UKGHRSDRequestFormField`](#get-ukghrsdrequestformfield) | List the fields of a form as curated `Slug` / `Label` / `TypeId` / `Required` objects — handy for scripting form submissions |
| [`Get-UKGHRSDRequestFormData`](#get-ukghrsdrequestformdata) | Resolve a request's answers into readable label/value pairs |

Every cmdlet also carries full comment-based help — `Get-Help <Cmdlet> -Full` in PowerShell shows synopsis, per-parameter descriptions, and worked examples.

### Connect-UKGHRSD

Opens an authenticated session and stores the access token in a module-private variable so subsequent `Get-UKGHRSD*` cmdlets can reuse it. Refreshes the token proactively before expiry.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Region` | `string` | yes | Platform region: `ATL`, `TOR`, `US`, `EU`, `StagingUS`, `StagingEU`. See [Picking the right `-Region`](#picking-the-right--region) above. |
| `-Credential` | `PSCredential` | yes | `UserName` = `application_id`, `Password` = `application_secret`. Use `Get-Credential`. |
| `-ClientId` | `string` | yes | The `client_id` issued alongside your application credentials. |
| `-PassThru` | `switch` | no | Return a redacted session summary (region, base URL, expiry). The access token and secrets are never included. |

### Disconnect-UKGHRSD

Clears the module-private session. Optionally revokes the token server-side via HRSD's `/revoke_token` endpoint before clearing.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Revoke` | `switch` | no | Call the API to revoke the access token before clearing local state. Without it, the session is only cleared locally — the token remains valid on the server until it expires. |

### Get-UKGHRSDRequest

Wraps `GET /requests` (list & search) and `GET /requests/{id}` (detail). Three parameter sets: list (default, with filters), single by internal UUID (`-Id`), and single by portal number (`-RequestNumber`).

**List-mode filters** (all optional, applied server-side; results paginate automatically unless `-MaxResults` caps them):

| Parameter | Type | Description |
|---|---|---|
| `-Status` | `created` \| `opened` \| `pending` \| `closed` \| `archived` (array) | Filter by one or more statuses. |
| `-FormId` | `string[]` | Filter by the form slug(s) used to create the request. |
| `-EmployeeId` | `string` | Filter by the UUID of the employee the request was created for. |
| `-EmployeeExternalId` | `string` | Filter by your own external employee id. |
| `-CreatorId` | `string` | Filter by the UUID of the creator (HR user, manager, or employee). |
| `-Priority` | `'1'` \| `'2'` \| `'3'` (array) | Filter by priority: 1 (low), 2 (normal), 3 (urgent). |
| `-Query` | `string` | Full-text search across subject, body, custom counter (request number), and matricules. Aliased as `-q`. |
| `-CreatedSince` / `-CreatedUntil` | `datetime` | Filter by created-at date range (either end optional). |
| `-UpdatedSince` / `-UpdatedUntil` | `datetime` | Filter by updated-at date range. |
| `-Sort` | e.g. `-updated_at`, `+created_at` | Sort order. `+` ascending, `-` descending. Supported fields: `request_number`, `name`, `status`, `priority`, `created_at`, `updated_at`. |
| `-MaxResults` | `int` | Cap total records across all pages. `0` = no cap. Default: `0`. |

**Single-request lookup** (mutually exclusive with each other and with the list filters):

| Parameter | Type | Description |
|---|---|---|
| `-Id` | `string` | Retrieve one request by its internal UUID (the `id` field). See the [`-Id` vs `-RequestNumber` note](#get-ukghrsdrequest-notes) below. |
| `-RequestNumber` | `int` | Retrieve one request by the human-readable number shown in the UKG admin portal (e.g. `6678`). |

**Common to all parameter sets:**

| Parameter | Type | Description |
|---|---|---|
| `-Embed` | `creator` \| `employee` \| `closed_by` \| `feedback` (array) | Expand related users inline instead of returning bare IDs (`creator_id` → `creator`, etc). `feedback` is only meaningful with `-Id`. |

<a id="get-ukghrsdrequest-notes"></a>
**Note on `-Id` vs `-RequestNumber`:** the number displayed in the UKG portal (e.g. `6678`) is `request_number`; the API's `/requests/{id}` detail endpoint takes a separate internal UUID (`id`). Pass the UUID to `-Id`; pass the portal number to `-RequestNumber`. If you pass an all-digit value to `-Id`, the cmdlet throws with a hint to use `-RequestNumber` instead — no wasted API call. The `-RequestNumber` path issues the API's full-text search (`q=<n>`) and narrows client-side to items where `request_number` matches exactly, because `q=` is fuzzy and can also match subjects/bodies that contain the digits.

### Get-UKGHRSDRequestForm

Wraps `GET /request_forms` (list & search) and `GET /request_forms/{id}` (detail). A form's `form_definition.fields` array is what [`Get-UKGHRSDRequestFormData`](#get-ukghrsdrequestformdata) joins to when turning raw answers into labeled output.

**List-mode filters:**

| Parameter | Type | Description |
|---|---|---|
| `-CategoryId` | `string` | Filter forms by category slug. |
| `-IsDefault` | `bool` | Filter by the `is_default` attribute. Serialized as lowercase (`true` / `false`). |
| `-Featured` | `bool` | Filter by the `featured` attribute. Serialized as lowercase. |
| `-LanguageCode` | `string` | Filter forms by language. Required when using `-Query`. |
| `-Query` | `string` | Full-text search on forms. Requires `-LanguageCode`. Aliased as `-q`. |
| `-EmployeeId` | `string` | Filter to forms visible to a specific employee. |
| `-Sort` | `+title` \| `-title` \| `+last_hits` \| `-last_hits` | Sort order. |
| `-MaxResults` | `int` | Cap total records across all pages. `0` = no cap. Default: `0`. |

**Single-form lookup** (mutually exclusive with each other and with list filters):

| Parameter | Type | Description |
|---|---|---|
| `-Id` | `string` | Retrieve one form by its internal slug (e.g. `offboarding`, `time-off-accruals`). |
| `-Name` | `string` | Retrieve one form by its display name (case-insensitive exact match, e.g. `'Time Off & Accruals'`). See the [`-Id` vs `-Name` note](#get-ukghrsdrequestform-notes) below. |

**Common:**

| Parameter | Type | Description |
|---|---|---|
| `-RawFaasFormat` | `switch` | Return `form_definition` in its original FaaS format (adds `f=1` to the query). Without this switch, the API converts FaaS forms to the newer Formidable format. |

<a id="get-ukghrsdrequestform-notes"></a>
**Note on `-Id` vs `-Name`:** `-Id` takes the internal slug (`time-off-accruals`) and hits `/request_forms/{id}` directly. `-Name` takes the display name (`'Time Off & Accruals'`) — the API has no dedicated name filter, so under the hood the cmdlet runs a full-text search (`q=<name>`) and narrows client-side to the record whose `name` matches exactly. Because the API requires `language_code` alongside `q=`, `-Name` defaults it to `en-us`; pass `-LanguageCode` explicitly if your tenant's forms are indexed in a different language. Throws with a helpful message if 0 or >1 exact matches come back.

### Get-UKGHRSDRequestFormField

Lists the fields of a request form as a curated object per field. Wraps the awkward `(Get-UKGHRSDRequestForm -Name '...').form_definition.fields` pattern into a first-class cmdlet, flattens the useful properties out of the nested Formidable/FaaS shape, and hides the noise (`accesses`, `autofill_*`, internal ids). Handy for scripting form submissions — you can see at a glance which fields exist, which are required, and what choices dropdowns/radios have.

**Output object shape:** `FormId`, `Slug`, `Label`, `TypeId`, `Required`, `Multiple`, `Description`, `Placeholder`, `Items`, `Defaults`, `Validations`, `Raw` (see note below).

**Input** (mutually exclusive):

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Form` | `pscustomobject` | yes (ByObject set) | A form object as returned by `Get-UKGHRSDRequestForm`. Accepts pipeline input. Skips the extra API call the other paths make. |
| `-FormId` | `string` | yes (ById set) | Retrieve the form by internal slug (e.g. `time-off-accruals`), then enumerate fields. |
| `-FormName` | `string` | yes (ByName set) | Retrieve the form by display name (e.g. `'Time Off & Accruals'`), then enumerate fields. Aliased as `-Name`. |

**Common:**

| Parameter | Type | Description |
|---|---|---|
| `-LanguageCode` | `string` | Only valid with `-FormName`. Defaults to `en-us`. |
| `-RawFaasFormat` | `switch` | Passed through to `Get-UKGHRSDRequestForm`. The curated top-level properties handle both formats; only the `.Raw` property changes shape. |
| `-Required` | `switch` | Emit only fields where `required = $true`. |

**Note on the `.Raw` property:** each emitted object carries the original field dictionary on `.Raw` — so if you need access to `accesses`, `autofill_*`, FaaS-specific keys, or anything the curated shape drops, it's still there. Example: `(Get-UKGHRSDRequestFormField -FormName 'Time Off & Accruals')[0].Raw.accesses`.

### Get-UKGHRSDRequestFormData

Joins a request's raw `form_data` (`{field_id, values}` pairs) to its form's field definitions to produce readable `Label` / `Value` output. Form definitions are cached per `form_id` for the duration of the call, so resolving a batch of requests that share a form fetches each form definition once.

**Output object shape:** `RequestId`, `RequestNumber`, `FormId`, `FieldId`, `Label`, `TypeId`, `Value` (single-value answers collapsed to a scalar; multi-value answers kept as an array).

**Input:** accepts either a request object (piped from `Get-UKGHRSDRequest`) or a `-RequestId` to fetch first.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Request` | `pscustomobject` | yes (ByObject set) | A request object as returned by `Get-UKGHRSDRequest`. Accepts pipeline input. |
| `-RequestId` | `string` | yes (ById set) | Internal UUID of the request to fetch and resolve. Use this when you have the ID but not the object. |
| `-IncludeEmpty` | `switch` | no | Also emit fields that exist on the form but have no answer on this request (`Value` will be an empty array). |

## Examples

```powershell
# --- Session ---

$cred = Get-Credential   # application_id / application_secret
Connect-UKGHRSD -Region ATL -Credential $cred -ClientId $cid

# --- Requests ---

# One request by the number shown in the UKG portal
Get-UKGHRSDRequest -RequestNumber 6678

# One request by internal UUID
Get-UKGHRSDRequest -Id '0a2f5401-5e63-4f8e-9da0-eceabc557905'

# Open/pending offboarding requests with employee details expanded
Get-UKGHRSDRequest -FormId 'offboarding' -Status opened,pending -Embed employee

# Full-text search
Get-UKGHRSDRequest -Query 'laptop return'

# Incremental sync: requests updated in the last day
Get-UKGHRSDRequest -UpdatedSince (Get-Date).AddDays(-1)

# --- Forms ---

# One form definition by slug
Get-UKGHRSDRequestForm -Id 'offboarding'

# Same form, by the display name shown in the UKG admin portal
Get-UKGHRSDRequestForm -Name 'Time Off & Accruals'

# All forms in a category
Get-UKGHRSDRequestForm -CategoryId 'hr-lifecycle'

# List the fields of a form (see what you have to fill in)
Get-UKGHRSDRequestForm -Name 'Time Off & Accruals' |
    Get-UKGHRSDRequestFormField |
    Format-Table Slug, Label, TypeId, Required -AutoSize

# Only the required fields
Get-UKGHRSDRequestFormField -FormName 'Time Off & Accruals' -Required

# --- Form-data resolution (the core value) ---

# Open offboarding requests → readable label/value output
Get-UKGHRSDRequest -FormId 'offboarding' -Status opened,pending |
    Get-UKGHRSDRequestFormData |
    Format-Table RequestNumber, Label, Value -AutoSize

# Pull only the corporate-credit-card answers across every open offboarding
Get-UKGHRSDRequest -FormId 'offboarding' -Status opened |
    Get-UKGHRSDRequestFormData |
    Where-Object Label -match 'credit card'

# Resolve a single request when you only have the ID
Get-UKGHRSDRequestFormData -RequestId '0a2f5401-...' |
    Select-Object Label, Value

# --- Cleanup ---

# Clear the local session (server-side token stays valid until it expires)
Disconnect-UKGHRSD

# Revoke the token server-side too
Disconnect-UKGHRSD -Revoke
```

## How custom-field resolution works

A request's manager-entered answers arrive as opaque `{ field_id, values }` pairs in its `form_data`. `Get-UKGHRSDRequestFormData` fetches the request's **form definition** (once per form, cached for the duration of the call) and joins each answer to its field's **label** and **type**, so you get readable output instead of GUIDs. Single-value answers collapse to a scalar; multi-value answers (checkboxes, multi-select) stay as arrays. Fields on the form that had no answer on this request are omitted by default — pass `-IncludeEmpty` to include them.

## Pagination

Cursor-based via HRSD's `Next-Cursor` response header — different from the page/per_Page pattern used by UKG Pro. `Invoke-UKGHRSDRequest` (the private wrapper every cmdlet routes through) follows cursors automatically and aggregates results. `-MaxResults` on any list cmdlet caps totals across all pages.

## Testing

```powershell
Invoke-Pester ./Tests
```

Tests mock the HTTP layer, so they run with no network and no live tenant.

## Roadmap

- **Write cmdlets:** `New-UKGHRSDRequest`, `Set-UKGHRSDRequest`, comments, attachments. `Invoke-UKGHRSDRequest` already supports POST/PATCH with a JSON body.
- **Additional read cmdlets:** employees, documents, processes/tasks — as offboarding workflows demand them.
- **Live-tenant validation** of the remaining regions (`ATL` verified 2026-09-02; `US`, `EU`, `TOR`, `StagingUS`, `StagingEU` still inferred from swagger + patterns).
- **First-class PowerShell Gallery release** once the read surface is broad enough to be useful out-of-the-box and every shipped cmdlet has been live-tenant validated.

## License

MIT © Super Core Solutions LLC
