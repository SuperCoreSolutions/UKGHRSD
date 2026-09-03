function Get-UKGHRSDRequest {
    <#
    .SYNOPSIS
        Retrieves People Assist requests (e.g. manager-submitted offboarding requests).

    .DESCRIPTION
        Wraps GET /requests (list & search) and GET /requests/{id} (detail).

        Called with -Id, returns a single request. Otherwise lists requests with
        optional server-side filters, following pagination automatically.

        The manager-entered answers live on each request's form_data array as
        { field_id, values } pairs. To turn those into readable label/value pairs
        (e.g. "Corporate credit card = Yes"), pipe the result into
        Get-UKGHRSDRequestFormData.

    .PARAMETER Id
        Retrieve a single request by its internal UUID (the `id` field on a
        request object — not the human-readable number displayed in the UKG
        admin portal). To look one up by the portal number, use
        -RequestNumber instead.

    .PARAMETER RequestNumber
        Retrieve a single request by the human-readable number shown in the
        UKG admin portal (e.g. 6678). The API has no dedicated filter for
        this field, so the module runs a full-text query (`q=<n>`) against
        /requests and returns the item whose `request_number` matches
        exactly. Throws if 0 or >1 exact matches come back.

    .PARAMETER Status
        Filter by one or more statuses: created, opened, pending, closed, archived.

    .PARAMETER FormId
        Filter by the form slug(s) used to create the request (e.g. your offboarding form).

    .PARAMETER EmployeeId
        Filter by the UUID of the employee the request was created for.

    .PARAMETER EmployeeExternalId
        Filter by your own external employee id.

    .PARAMETER CreatorId
        Filter by the UUID of the creator (HR user, manager, or employee).

    .PARAMETER Priority
        Filter by priority: 1 (low), 2 (normal), 3 (urgent).

    .PARAMETER Query
        Full-text search across subject, body, custom counter, and matricules.

    .PARAMETER CreatedSince
        Only requests created on/after this date.

    .PARAMETER CreatedUntil
        Only requests created on/before this date.

    .PARAMETER UpdatedSince
        Only requests updated on/after this date.

    .PARAMETER UpdatedUntil
        Only requests updated on/before this date.

    .PARAMETER Embed
        Expand related users inline instead of returning bare IDs:
        creator, employee, closed_by.

    .PARAMETER Sort
        Sort order, e.g. '-updated_at' (default server sort), '+created_at', etc.

    .PARAMETER MaxResults
        Cap the total number of records returned across all pages. 0 = all.

    .EXAMPLE
        Get-UKGHRSDRequest -FormId 'offboarding' -Status opened,pending -Embed employee

        Lists open/pending offboarding requests with employee details expanded.

    .EXAMPLE
        Get-UKGHRSDRequest -Id '0a2f5401-5e63-4f8e-9da0-eceabc557905'

        Retrieves a single request by its internal UUID.

    .EXAMPLE
        Get-UKGHRSDRequest -RequestNumber 6678

        Retrieves a single request by the portal-visible number.

    .EXAMPLE
        Get-UKGHRSDRequest -Status opened -CreatedSince (Get-Date).AddDays(-7)

        Lists requests opened in the last week.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [Alias('request_id')]
        [string]$Id,

        [Parameter(Mandatory, ParameterSetName = 'ByRequestNumber', ValueFromPipelineByPropertyName)]
        [Alias('request_number')]
        [int]$RequestNumber,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('created', 'opened', 'pending', 'closed', 'archived')]
        [string[]]$Status,

        [Parameter(ParameterSetName = 'List')]
        [string[]]$FormId,

        [Parameter(ParameterSetName = 'List')]
        [string]$EmployeeId,

        [Parameter(ParameterSetName = 'List')]
        [string]$EmployeeExternalId,

        [Parameter(ParameterSetName = 'List')]
        [string]$CreatorId,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('1', '2', '3')]
        [string[]]$Priority,

        [Parameter(ParameterSetName = 'List')]
        [Alias('q')]
        [string]$Query,

        [Parameter(ParameterSetName = 'List')]
        [datetime]$CreatedSince,

        [Parameter(ParameterSetName = 'List')]
        [datetime]$CreatedUntil,

        [Parameter(ParameterSetName = 'List')]
        [datetime]$UpdatedSince,

        [Parameter(ParameterSetName = 'List')]
        [datetime]$UpdatedUntil,

        [Parameter()]
        [ValidateSet('creator', 'employee', 'closed_by', 'feedback')]
        [string[]]$Embed,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet(
            '+request_number', '-request_number', '+name', '-name',
            '+status', '-status', '+priority', '-priority',
            '+created_at', '-created_at', '+updated_at', '-updated_at'
        )]
        [string]$Sort,

        [Parameter(ParameterSetName = 'List')]
        [int]$MaxResults = 0
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            # The API's /requests/{id} takes the internal UUID. A caller who
            # passes the portal-visible number (all digits) gets a bare 404
            # from UKG that doesn't point at the right cmdlet -- catch that
            # here and steer them to -RequestNumber.
            if ($Id -match '^\d+$') {
                throw "-Id '$Id' looks like a request number, not a UUID. The API's /requests/{id} endpoint takes the internal UUID ('id' field on a request object). To look up by the number shown in the UKG portal, use: Get-UKGHRSDRequest -RequestNumber $Id"
            }
            $q = @{}
            if ($Embed) { $q['embed'] = $Embed }
            Invoke-UKGHRSDRequest -Method Get -Path "/requests/$Id" -Query $q -NoPaging
            return
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByRequestNumber') {
            # /requests has no request_number filter, only full-text q. Query
            # then narrow client-side to an exact numeric match -- q is fuzzy
            # and can match subjects/bodies that happen to contain the number.
            $q = @{ q = [string]$RequestNumber }
            if ($Embed) { $q['embed'] = $Embed }
            $candidates = @(Invoke-UKGHRSDRequest -Method Get -Path '/requests' -Query $q)
            $exact      = @($candidates | Where-Object { $_.request_number -eq $RequestNumber })

            if ($exact.Count -eq 0) {
                throw "No request found with request_number = $RequestNumber."
            }
            if ($exact.Count -gt 1) {
                throw "Multiple requests ($($exact.Count)) matched request_number = $RequestNumber. This shouldn't happen and likely indicates duplicate data on the tenant side; inspect the raw results with Get-UKGHRSDRequest -Query '$RequestNumber'."
            }
            return $exact[0]
        }

        # List: assemble query params only for those the caller supplied.
        $q = @{}
        if ($Status)             { $q['status']              = $Status }
        if ($FormId)             { $q['form_id']             = $FormId }
        if ($EmployeeId)         { $q['employee_id']         = $EmployeeId }
        if ($EmployeeExternalId) { $q['employee_external_id'] = $EmployeeExternalId }
        if ($CreatorId)          { $q['creator_id']          = $CreatorId }
        if ($Priority)           { $q['priority']            = $Priority }
        if ($Query)              { $q['q']                   = $Query }
        if ($Embed)              { $q['embed']               = $Embed }
        if ($Sort)               { $q['sort']                = $Sort }

        # Dates use ISO 8601 date format (YYYY-MM-DD) per the API.
        if ($PSBoundParameters.ContainsKey('CreatedSince')) { $q['created_at_since'] = $CreatedSince.ToString('yyyy-MM-dd') }
        if ($PSBoundParameters.ContainsKey('CreatedUntil')) { $q['created_at_until'] = $CreatedUntil.ToString('yyyy-MM-dd') }
        if ($PSBoundParameters.ContainsKey('UpdatedSince')) { $q['updated_at_since'] = $UpdatedSince.ToString('yyyy-MM-dd') }
        if ($PSBoundParameters.ContainsKey('UpdatedUntil')) { $q['updated_at_until'] = $UpdatedUntil.ToString('yyyy-MM-dd') }

        Invoke-UKGHRSDRequest -Method Get -Path '/requests' -Query $q -MaxResults $MaxResults
    }
}
