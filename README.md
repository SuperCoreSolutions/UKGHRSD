# UKGHRSD

A PowerShell module for the **UKG HR Service Delivery (HRSD)** REST API v2 (People-Doc / Ultipro platforms).

Its first focus is reading **People Assist requests** — for example, manager-submitted **offboarding** requests — and resolving the answers managers enter into custom form fields (e.g. *"employee has a corporate credit card that must be retrieved"*) into readable label/value output.

> Status: early scaffold (v0.1.0). Read-only (`Connect` + `Get`) cmdlets first; write cmdlets (`Set-`/`New-`) to follow.

## Install

```powershell
# From PowerShell Gallery (once published)
Install-Module UKGHRSD

# Or from source
git clone https://github.com/SuperCoreSolutions/UKGHRSD.git
Import-Module ./UKGHRSD/UKGHRSD.psd1
```

Requires PowerShell 5.1+ (Windows PowerShell) or 7+ (Core).

## Authentication

Credentials (`application_id`, `application_secret`, `client_id`) are issued by your UKG HRSD Project Manager / IPM team. The module uses the OAuth `client_credentials` flow and stores the token in a module-private session, refreshing it automatically before expiry.

```powershell
# UserName = application_id, Password = application_secret
$cred = Get-Credential
Connect-UKGHRSD -Region US -Credential $cred -ClientId 'your-client-id'
```

`-Region` values: `US`, `EU` (People-Doc prod), `ATL`, `TOR` (UKG/Ultipro prod), `StagingUS`, `StagingEU`.

## Cmdlets

| Cmdlet | Purpose |
|---|---|
| `Connect-UKGHRSD` | Authenticate and open a session |
| `Disconnect-UKGHRSD` | Clear the session (optionally revoke the token) |
| `Get-UKGHRSDRequest` | List/search requests, or get one by `-Id` |
| `Get-UKGHRSDRequestForm` | Get form definitions (field labels/types) |
| `Get-UKGHRSDRequestFormData` | Resolve a request's answers into label/value pairs |

## Example: offboarding readout

```powershell
Connect-UKGHRSD -Region US -Credential $cred -ClientId $cid

# Open/pending offboarding requests, with employee details expanded
Get-UKGHRSDRequest -FormId 'offboarding' -Status opened,pending -Embed employee |
    Get-UKGHRSDRequestFormData |
    Format-Table RequestNumber, Label, Value -AutoSize

# Pull just the corporate-credit-card answers
Get-UKGHRSDRequest -FormId 'offboarding' -Status opened |
    Get-UKGHRSDRequestFormData |
    Where-Object Label -match 'credit card'
```

## How custom-field resolution works

A request's raw answers arrive as opaque `{ field_id, values }` pairs in its `form_data`. `Get-UKGHRSDRequestFormData` fetches the request's **form definition** (once per form, cached) and joins each answer to its field's **label** and **type**, so you get readable output instead of GUIDs. Single-value answers collapse to a scalar; multi-value answers (checkboxes) stay as arrays.

## Testing

```powershell
Invoke-Pester ./Tests
```

Tests mock the HTTP layer, so they run with no network and no live tenant.

## Roadmap

- Write cmdlets: `New-UKGHRSDRequest`, `Set-UKGHRSDRequest`, comments/attachments.
- Additional read cmdlets: employees, documents, processes/tasks.

## License

MIT © Super Core Solutions LLC
