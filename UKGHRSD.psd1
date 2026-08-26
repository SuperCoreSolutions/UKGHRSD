@{
    # Script module associated with this manifest.
    RootModule        = 'UKGHRSD.psm1'

    # Version number of this module. Bump per release (SemVer) before publishing.
    ModuleVersion     = '0.1.0'

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
            ReleaseNotes = 'Initial scaffold: OAuth connect/disconnect and read-only (Get) cmdlets for requests and request forms.'
        }
    }
}
