function Connect-UKGHRSD {
    <#
    .SYNOPSIS
        Establishes an authenticated session with the UKG HR Service Delivery API.

    .DESCRIPTION
        Requests an OAuth application access token (client_credentials flow) and
        stores it, along with the resolved base URL and credentials, in a
        script-scoped session. Subsequent Get-UKGHRSD* cmdlets use this session
        automatically and refresh the token as needed, so you never pass
        credentials on individual calls.

        Credentials (application_id, application_secret, client_id) are issued by
        your UKG HRSD Project Manager / IPM team.

    .PARAMETER Region
        The HRSD platform your tenant lives on. HRSD runs on two distinct
        platforms; picking the wrong one 401s even with valid credentials:

          ATL, TOR             - UKG-branded / post-acquisition tenants (US / CA).
                                 Base URLs: https://apis.hrsd.ultipro.com|ca
                                 Current default for most UKG customers.
          US, EU               - Legacy People-Doc-branded tenants (US / EU).
                                 Base URLs: https://apis.{us|eu}.people-doc.com
          StagingUS, StagingEU - People-Doc non-production.
                                 Base URLs: https://apis.staging.{us|eu}.people-doc.com

        Tell them apart by the domain your IPM contact gives you:
          apis.hrsd.ultipro.{com,ca}   -> ATL / TOR
          apis.*.people-doc.com        -> US / EU / Staging*
        When in doubt, ask IPM directly which platform provisioned the tenant.

    .PARAMETER Credential
        A PSCredential where UserName = application_id and Password = application_secret.

    .PARAMETER ClientId
        The client_id issued alongside your application credentials.

    .PARAMETER PassThru
        Return the session object (token redacted) instead of nothing.

    .EXAMPLE
        $cred = Get-Credential   # application_id / application_secret
        Connect-UKGHRSD -Region US -Credential $cred -ClientId 'your-client-id'

        Authenticates against the US platform and stores the session for reuse.

    .EXAMPLE
        Connect-UKGHRSD -Region ATL -Credential $cred -ClientId $cid -PassThru

        Connects to the UKG/Ultipro ATL platform and returns the (redacted) session.
    #>
    [CmdletBinding()]
    [OutputType([void], [pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('US', 'EU', 'ATL', 'TOR', 'StagingUS', 'StagingEU')]
        [string]$Region,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [switch]$PassThru
    )

    $baseUrl = Resolve-UKGHRSDBaseUrl -Region $Region

    $applicationId     = $Credential.UserName
    $applicationSecret = $Credential.GetNetworkCredential().Password

    Write-Verbose "Connecting to UKG HRSD ($Region) at $baseUrl"

    $token = Get-UKGHRSDAccessToken `
        -BaseUrl           $baseUrl `
        -ApplicationId     $applicationId `
        -ApplicationSecret $applicationSecret `
        -ClientId          $ClientId

    # Store everything needed to make calls and to refresh the token later.
    # Kept script-scoped (module-private) rather than global to avoid leaking
    # the token into the user's session state.
    $script:UKGHRSDSession = [pscustomobject]@{
        Region            = $Region
        BaseUrl           = $baseUrl
        ApplicationId     = $applicationId
        ApplicationSecret = $applicationSecret
        ClientId          = $ClientId
        AccessToken       = $token.AccessToken
        ExpiresAt         = $token.ExpiresAt
        ConnectedAt       = Get-Date
    }

    Write-Verbose "Connected. Token valid until $($token.ExpiresAt)."

    if ($PassThru) {
        # Return a redacted copy - never surface the raw token or secret.
        [pscustomobject]@{
            Region      = $script:UKGHRSDSession.Region
            BaseUrl     = $script:UKGHRSDSession.BaseUrl
            ClientId    = $script:UKGHRSDSession.ClientId
            ExpiresAt   = $script:UKGHRSDSession.ExpiresAt
            ConnectedAt = $script:UKGHRSDSession.ConnectedAt
        }
    }
}
