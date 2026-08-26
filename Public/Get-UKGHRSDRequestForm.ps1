function Get-UKGHRSDRequestForm {
    <#
    .SYNOPSIS
        Retrieves request form definitions.

    .DESCRIPTION
        Wraps GET /request_forms (list & search) and GET /request_forms/{id} (detail).

        A request form's definition contains the field list (each with a slug,
        label, and type) that gives meaning to the field_id values found in a
        request's form_data. Get-UKGHRSDRequestFormData uses this mapping to turn
        raw answers into readable label/value output.

    .PARAMETER Id
        Retrieve a single request form by its ID (slug).

    .PARAMETER CategoryId
        Filter forms by category slug.

    .PARAMETER IsDefault
        Filter by the is_default attribute.

    .PARAMETER Featured
        Filter by the featured attribute.

    .PARAMETER LanguageCode
        Filter forms by language (required when using -Query).

    .PARAMETER Query
        Full-text search on forms. Requires -LanguageCode.

    .PARAMETER EmployeeId
        Filter to forms visible to a specific employee.

    .PARAMETER Sort
        Sort order: '+title', '-title', '+last_hits', '-last_hits'.

    .PARAMETER RawFaasFormat
        Return form_definition in original FaaS format (adds f=1). By default the
        API converts FaaS forms to Formidable format.

    .PARAMETER MaxResults
        Cap total records across pages. 0 = all.

    .EXAMPLE
        Get-UKGHRSDRequestForm -Id 'offboarding'

        Retrieves the offboarding form definition, including its field list.

    .EXAMPLE
        Get-UKGHRSDRequestForm -CategoryId 'hr-lifecycle'

        Lists all forms in the given category.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
        [Alias('form_id')]
        [string]$Id,

        [Parameter(ParameterSetName = 'List')]
        [string]$CategoryId,

        [Parameter(ParameterSetName = 'List')]
        [bool]$IsDefault,

        [Parameter(ParameterSetName = 'List')]
        [bool]$Featured,

        [Parameter(ParameterSetName = 'List')]
        [string]$LanguageCode,

        [Parameter(ParameterSetName = 'List')]
        [Alias('q')]
        [string]$Query,

        [Parameter(ParameterSetName = 'List')]
        [string]$EmployeeId,

        [Parameter(ParameterSetName = 'List')]
        [ValidateSet('+title', '-title', '+last_hits', '-last_hits')]
        [string]$Sort,

        [Parameter()]
        [switch]$RawFaasFormat,

        [Parameter(ParameterSetName = 'List')]
        [int]$MaxResults = 0
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $q = @{}
            if ($RawFaasFormat) { $q['f'] = '1' }
            Invoke-UKGHRSDRequest -Method Get -Path "/request_forms/$Id" -Query $q -NoPaging
            return
        }

        if ($Query -and -not $LanguageCode) {
            throw "A -LanguageCode is required when using -Query (full-text search on forms)."
        }

        $q = @{}
        if ($CategoryId)                              { $q['category_id']  = $CategoryId }
        if ($PSBoundParameters.ContainsKey('IsDefault')) { $q['is_default'] = $IsDefault.ToString().ToLower() }
        if ($PSBoundParameters.ContainsKey('Featured'))  { $q['featured']   = $Featured.ToString().ToLower() }
        if ($LanguageCode)                            { $q['language_code'] = $LanguageCode }
        if ($Query)                                   { $q['q']            = $Query }
        if ($EmployeeId)                              { $q['employee_id']  = $EmployeeId }
        if ($Sort)                                    { $q['sort']         = $Sort }
        if ($RawFaasFormat)                           { $q['f']            = '1' }

        Invoke-UKGHRSDRequest -Method Get -Path '/request_forms' -Query $q -MaxResults $MaxResults
    }
}
