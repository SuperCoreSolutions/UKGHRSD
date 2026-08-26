function Get-UKGHRSDErrorMessage {
    <#
    .SYNOPSIS
        Turns a failed HRSD API call into a readable error string.

    .DESCRIPTION
        The HRSD API returns errors as JSON with keys { code, message, errors[] },
        where each validation error carries { field, code, message }. This helper
        digs the response body out of the terminating error record and formats a
        single useful message, falling back to the raw exception when the body
        isn't parseable.

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

    $response = $ErrorRecord.Exception.Response
    if ($response) {
        # HTTP status differs slightly between PS 5.1 (StatusCode enum) and PS 7.
        try { $status = [int]$response.StatusCode } catch { }

        # PS 7 exposes the body on the exception; PS 5.1 needs a stream read.
        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            $bodyText = $ErrorRecord.ErrorDetails.Message
        }
        elseif ($response.GetResponseStream) {
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
            $detail = $parsed.message
            if ($parsed.errors) {
                $fieldErrors = foreach ($e in $parsed.errors) {
                    "$($e.field): $($e.message)"
                }
                $detail = "$detail ($($fieldErrors -join '; '))"
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
