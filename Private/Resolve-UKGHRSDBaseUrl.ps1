function Resolve-UKGHRSDBaseUrl {
    <#
    .SYNOPSIS
        Maps a friendly region/platform name to its HRSD API v2 base URL.

    .DESCRIPTION
        UKG HRSD (People-Doc) runs on several regional platforms, each with its
        own hostname. Rather than make callers paste full URLs, Connect-UKGHRSD
        accepts a -Region name and this helper translates it to the absolute
        base URL that all v2 client endpoints hang off of.

        Base URLs come straight from the "UKG HR Service Delivery REST API v2
        Overview" documentation.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('US', 'EU', 'ATL', 'TOR', 'StagingUS', 'StagingEU')]
        [string]$Region
    )

    # base path is always /api/v2/client for the client-scope endpoints.
    $map = @{
        'US'        = 'https://apis.us.people-doc.com'
        'EU'        = 'https://apis.eu.people-doc.com'
        'ATL'       = 'https://apis.hrsd.ultipro.com'    # UKG / Ultipro (US)
        'TOR'       = 'https://apis.hrsd.ultipro.ca'      # UKG / Ultipro (Canada)
        'StagingUS' = 'https://apis.staging.us.people-doc.com'
        'StagingEU' = 'https://apis.staging.eu.people-doc.com'
    }

    return $map[$Region]
}
