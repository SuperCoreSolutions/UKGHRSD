function Get-UKGHRSDAccessToken {
    <#
    .SYNOPSIS
        Requests an OAuth application access_token from the HRSD /tokens endpoint.

    .DESCRIPTION
        Implements the client_credentials flow documented in the HRSD OAuth guide:
        POST {BaseUrl}/api/v2/client/tokens
          - Basic auth with ApplicationId:ApplicationSecret
          - body: grant_type=client_credentials&scope=client&client_id=<ClientId>

        Returns a PSCustomObject with the token and its computed expiry so the
        caller (Connect-UKGHRSD) can store it and refresh proactively before it
        expires, as UKG recommends.

    .NOTES
        Internal helper. Not exported. The returned token is an *application*
        token for server-to-server use only and must never be surfaced to an
        end-user device.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [string]$ApplicationId,

        [Parameter(Mandatory)]
        [string]$ApplicationSecret,

        [Parameter(Mandatory)]
        [string]$ClientId
    )

    $tokenUri = "$BaseUrl/api/v2/client/tokens"

    # Build the Basic auth header from application_id:application_secret.
    $pair    = "{0}:{1}" -f $ApplicationId, $ApplicationSecret
    $basic   = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    $headers = @{
        Authorization = "Basic $basic"
        Accept        = 'application/json'
    }

    # client_credentials grant. scope is 'client' for the client-scope API.
    $body = @{
        grant_type = 'client_credentials'
        scope      = 'client'
        client_id  = $ClientId
    }

    Write-Verbose "Requesting access token from $tokenUri"

    try {
        # Capture the moment just before the call so expiry math stays conservative.
        $requestedAt = Get-Date
        $response = Invoke-RestMethod -Method Post -Uri $tokenUri `
            -Headers $headers -Body $body `
            -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
    }
    catch {
        # Surface UKG's response body (OAuth 2.0 error / description) rather
        # than the bare HTTP status — the difference between invalid_client,
        # invalid_grant, and a wrong base URL is impossible to debug otherwise.
        $detail = Get-UKGHRSDErrorMessage -ErrorRecord $_
        throw "UKG HRSD token request to $tokenUri failed. $detail`nVerify -Region, -ClientId, and the application_id / application_secret with your UKG IPM contact (credentials are per-environment; staging and production credentials are not interchangeable)."
    }

    if (-not $response.access_token) {
        throw "UKG HRSD token endpoint returned no access_token. Response: $($response | ConvertTo-Json -Compress)"
    }

    [pscustomobject]@{
        AccessToken = $response.access_token
        TokenType   = $response.token_type
        ExpiresIn   = $response.expires_in
        # Store an absolute expiry so refresh logic doesn't have to track durations.
        ExpiresAt   = $requestedAt.AddSeconds([int]$response.expires_in)
    }
}
