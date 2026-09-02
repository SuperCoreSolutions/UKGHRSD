function Get-UKGHRSDErrorMessage {
    <#
    .SYNOPSIS
        Turns a failed HRSD API call into a readable error string.

    .DESCRIPTION
        Two response schemas can come back from HRSD depending on which endpoint
        failed, both handled here:

          - HRSD API errors (data endpoints): { code, message, errors[] }
            where each validation error carries { field, code, message }.
          - OAuth 2.0 token endpoint errors: { error, error_description, error_uri }
            per RFC 6749 §5.2 — invalid_client, invalid_grant, invalid_scope, etc.

        Falls back to the raw response body, then to the exception message,
        when neither schema matches.

    .NOTES
        Internal helper. Not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $status = $null
    $bodyText = $null

    # PS 7's Invoke-RestMethod puts the response body on ErrorDetails.Message
    # regardless of whether Exception.Response is populated — check this first
    # so we don't drop the body when the exception type doesn't expose Response.
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $bodyText = $ErrorRecord.ErrorDetails.Message
    }

    $response = $ErrorRecord.Exception.Response
    if ($response) {
        # HTTP status differs slightly between PS 5.1 (StatusCode enum) and PS 7.
        try { $status = [int]$response.StatusCode } catch { }

        # PS 5.1 fallback: body isn't on ErrorDetails, read the response stream.
        if (-not $bodyText -and $response.GetResponseStream) {
            try {
                $stream = $response.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $bodyText = $reader.ReadToEnd()
                $reader.Dispose()
            }
            catch { }
        }
    }

    $detail = $null
    if ($bodyText) {
        try {
            $parsed = $bodyText | ConvertFrom-Json
            # OAuth 2.0 token-endpoint error shape (RFC 6749 §5.2).
            if ($parsed.error) {
                $detail = if ($parsed.error_description) {
                    "$($parsed.error): $($parsed.error_description)"
                } else {
                    [string]$parsed.error
                }
            }
            # HRSD API error shape.
            elseif ($parsed.message) {
                $detail = $parsed.message
                if ($parsed.errors) {
                    $fieldErrors = foreach ($e in $parsed.errors) {
                        "$($e.field): $($e.message)"
                    }
                    $detail = "$detail ($($fieldErrors -join '; '))"
                }
            }
            else {
                $detail = $bodyText
            }
        }
        catch {
            $detail = $bodyText
        }
    }

    $prefix = if ($status) { "UKG HRSD API error (HTTP $status)" } else { "UKG HRSD API error" }
    if ($detail) { return "${prefix}: $detail" }
    return "${prefix}: $($ErrorRecord.Exception.Message)"
}
