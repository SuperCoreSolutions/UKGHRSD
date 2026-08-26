function Invoke-UKGHRSDRequest {
    <#
    .SYNOPSIS
        Central REST wrapper for all HRSD API calls.

    .DESCRIPTION
        Every public cmdlet routes through here so that authentication, token
        refresh, error handling, and cursor pagination live in exactly one place.

        Responsibilities:
          - Verify there is an active session (Connect-UKGHRSD was called).
          - Refresh the access token proactively if it is at/near expiry.
          - Attach the Bearer token and standard headers.
          - Follow Next-Cursor pagination automatically for GET list calls,
            aggregating results, with an optional -MaxResults cap.

    .NOTES
        Internal helper. Not exported.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Get', 'Post', 'Patch', 'Delete', 'Head', 'Put')]
        [string]$Method,

        # Relative path under the client base path, e.g. '/requests' or "/requests/$id".
        [Parameter(Mandatory)]
        [string]$Path,

        # Query string parameters as a hashtable; array values are joined CSV-style.
        [hashtable]$Query,

        # Request body (for later Post/Patch cmdlets). Serialized to JSON.
        [object]$Body,

        # Cap total records returned across all pages. 0 = no cap (all pages).
        [int]$MaxResults = 0,

        # When set, do not auto-follow pagination; return a single page only.
        [switch]$NoPaging
    )

    # --- 1. Ensure we have a live session -------------------------------------
    if (-not $script:UKGHRSDSession) {
        throw "Not connected. Run Connect-UKGHRSD first."
    }

    # --- 2. Refresh token if expired / within the safety window ---------------
    # Refresh a minute early so a call never fails mid-flight on a stale token.
    $safetyWindow = [TimeSpan]::FromSeconds(60)
    if ((Get-Date) -ge ($script:UKGHRSDSession.ExpiresAt - $safetyWindow)) {
        Write-Verbose "Access token expired or near expiry; refreshing."
        $fresh = Get-UKGHRSDAccessToken `
            -BaseUrl           $script:UKGHRSDSession.BaseUrl `
            -ApplicationId     $script:UKGHRSDSession.ApplicationId `
            -ApplicationSecret $script:UKGHRSDSession.ApplicationSecret `
            -ClientId          $script:UKGHRSDSession.ClientId
        $script:UKGHRSDSession.AccessToken = $fresh.AccessToken
        $script:UKGHRSDSession.ExpiresAt   = $fresh.ExpiresAt
    }

    $headers = @{
        Authorization = "Bearer $($script:UKGHRSDSession.AccessToken)"
        Accept        = 'application/json'
    }

    $baseClientUri = "$($script:UKGHRSDSession.BaseUrl)/api/v2/client"

    # --- 3. Build the initial query string ------------------------------------
    $queryString = $null
    if ($Query -and $Query.Count -gt 0) {
        $pairs = foreach ($key in $Query.Keys) {
            $value = $Query[$key]
            if ($null -eq $value) { continue }
            # Arrays are sent CSV-style (collectionFormat: csv in the spec).
            if ($value -is [System.Array]) {
                $value = ($value -join ',')
            }
            '{0}={1}' -f [uri]::EscapeDataString($key), [uri]::EscapeDataString([string]$value)
        }
        $queryString = ($pairs -join '&')
    }

    $uri = "$baseClientUri$Path"
    if ($queryString) { $uri = "$uri`?$queryString" }

    $invokeParams = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $headers
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $invokeParams.Body        = ($Body | ConvertTo-Json -Depth 20)
        $invokeParams.ContentType = 'application/json'
    }

    $results = [System.Collections.Generic.List[object]]::new()

    # --- 4. Page loop ---------------------------------------------------------
    # HRSD returns pagination cursors in response headers (Next-Cursor), so we
    # use Invoke-WebRequest to see headers, then parse the JSON body ourselves.
    while ($true) {
        try {
            $raw = Invoke-WebRequest @invokeParams -UseBasicParsing
        }
        catch {
            throw (Get-UKGHRSDErrorMessage -ErrorRecord $_)
        }

        # Parse body (list endpoints return a JSON array; detail endpoints an object).
        $payload = $null
        if ($raw.Content) {
            $payload = $raw.Content | ConvertFrom-Json
        }

        if ($payload -is [System.Array]) {
            foreach ($item in $payload) { [void]$results.Add($item) }
        }
        elseif ($null -ne $payload) {
            [void]$results.Add($payload)
        }

        # Stop if caller asked for a single page or capped results are reached.
        if ($NoPaging) { break }
        if ($MaxResults -gt 0 -and $results.Count -ge $MaxResults) { break }

        # Follow Next-Cursor if present; otherwise we're done.
        $nextCursor = $raw.Headers['Next-Cursor']
        if (-not $nextCursor) { break }

        # Rebuild the URI with the new cursor, preserving other query params.
        $cursorQuery = if ($queryString) { "$queryString&cursor=$([uri]::EscapeDataString([string]$nextCursor))" }
                       else { "cursor=$([uri]::EscapeDataString([string]$nextCursor))" }
        $invokeParams.Uri = "$baseClientUri$Path`?$cursorQuery"
    }

    if ($MaxResults -gt 0 -and $results.Count -gt $MaxResults) {
        return $results[0..($MaxResults - 1)]
    }
    return $results
}
