@{
    # Script module associated with this manifest.
    RootModule        = 'UKGHRSD.psm1'

    # Version number of this module. Bump per release (SemVer) before publishing.
    ModuleVersion     = '0.2.0'

    # Supported PowerShell editions. Desktop = Windows PowerShell 5.1, Core = PS 7+.
    CompatiblePSEditions = @('Desktop', 'Core')

    # Unique identifier for this module. Generate once, then never change it.
    GUID              = '096278f7-a217-473a-8a77-4fdcf14ffe7e'

    Author            = 'Don Sheehan'
    CompanyName       = 'Super Core Solutions LLC'
    Copyright         = '(c) Super Core Solutions LLC. All rights reserved.'

    Description       = 'PowerShell wrapper for the UKG HR Service Delivery (HRSD) REST API v2. Retrieve People Assist requests (e.g. manager-submitted offboarding requests) and resolve their form/custom-field values into readable output.'

    PowerShellVersion = '5.1'

    # Functions to export. Listed explicitly (rather than '*') so the manifest is
    # the source of truth for the public surface and PSGallery shows them cleanly.
    FunctionsToExport = @(
        'Connect-UKGHRSD'
        'Disconnect-UKGHRSD'
        'Get-UKGHRSDRequest'
        'Get-UKGHRSDRequestForm'
        'Get-UKGHRSDRequestFormField'
        'Get-UKGHRSDRequestFormData'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('UKG', 'HRSD', 'HR-Service-Delivery', 'PeopleDoc', 'Offboarding', 'REST', 'IAM')
            LicenseUri   = 'https://github.com/SuperCoreSolutions/UKGHRSD/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/SuperCoreSolutions/UKGHRSD'
            ReleaseNotes = @'
v0.2.0 - First PowerShell Gallery release.

Cmdlets: Connect-UKGHRSD / Disconnect-UKGHRSD (OAuth 2.0
client_credentials with automatic token refresh, six regions across
UKG-Ultipro ATL/TOR and legacy People-Doc US/EU/StagingUS/StagingEU),
Get-UKGHRSDRequest (list/search plus -Id UUID and -RequestNumber
portal-number lookups), Get-UKGHRSDRequestForm (list/search plus -Id
slug and -Name display-name lookups), Get-UKGHRSDRequestFormField
(curated field enumeration -- promotes Slug / Label / TypeId /
Required from the nested Formidable-or-FaaS shape, hides accesses
and autofill noise), Get-UKGHRSDRequestFormData (resolves opaque
form_data {field_id, values} pairs into readable Label/Value output
-- the core value proposition for offboarding workflows).

Cursor-based pagination on list endpoints (Next-Cursor header).
OAuth 2.0 error bodies (invalid_client, invalid_grant, etc.) are
surfaced in exception messages instead of being swallowed to a bare
401. Region-picking guidance in help text and README to steer users
between the UKG-branded (apis.hrsd.ultipro.*) and People-Doc-branded
(apis.*.people-doc.com) platforms.

Live-verified: -Region ATL on 2026-09-02, plus end-to-end
form-data resolver against an ATL prod tenant. Other regions (US,
EU, TOR, StagingUS, StagingEU) inferred from the OpenAPI spec.
'@
        }
    }
}
