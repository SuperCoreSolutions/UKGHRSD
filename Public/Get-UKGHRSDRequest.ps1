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
        Retrieve a single request by its unique ID.

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

        Retrieves a single request by ID.

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
            $q = @{}
            if ($Embed) { $q['embed'] = $Embed }
            Invoke-UKGHRSDRequest -Method Get -Path "/requests/$Id" -Query $q -NoPaging
            return
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
