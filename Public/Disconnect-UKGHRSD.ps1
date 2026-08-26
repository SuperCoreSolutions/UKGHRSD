function Disconnect-UKGHRSD {
    <#
    .SYNOPSIS
        Clears the current UKG HRSD session.

    .DESCRIPTION
        Removes the stored session (token, credentials, base URL) from module
        state. Optionally revokes the access token server-side first via the
        HRSD /revoke_token endpoint, per the OAuth guide's revocation flow.

    .PARAMETER Revoke
        Also call the API to revoke the access token before clearing it locally.

    .EXAMPLE
        Disconnect-UKGHRSD

        Clears the local session without contacting the server.

    .EXAMPLE
        Disconnect-UKGHRSD -Revoke

        Revokes the token server-side, then clears the local session.
    #>
    [CmdletBinding()]
    param (
        [switch]$Revoke
    )

    if (-not $script:UKGHRSDSession) {
        Write-Verbose "No active UKG HRSD session to disconnect."
        return
    }

    if ($Revoke) {
        $revokeUri = "$($script:UKGHRSDSession.BaseUrl)/api/v2/client/revoke_token"
        $pair  = "{0}:{1}" -f $script:UKGHRSDSession.ApplicationId, $script:UKGHRSDSession.ApplicationSecret
        $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        try {
            Invoke-RestMethod -Method Post -Uri $revokeUri `
                -Headers @{ Authorization = "Basic $basic"; Accept = 'application/json' } `
                -Body @{ token = $script:UKGHRSDSession.AccessToken } `
                -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop | Out-Null
            Write-Verbose "Access token revoked server-side."
        }
        catch {
            Write-Warning "Token revocation failed: $($_.Exception.Message). Clearing local session anyway."
        }
    }

    $script:UKGHRSDSession = $null
    Write-Verbose "UKG HRSD session cleared."
}
