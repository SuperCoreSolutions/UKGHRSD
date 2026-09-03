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
        Retrieve a single request form by its internal ID (slug — e.g.
        `time-off-accruals`). To look one up by the human-readable name
        shown in the UKG admin portal (e.g. "Time Off & Accruals"), use
        -Name instead.

    .PARAMETER Name
        Retrieve a single request form by its display name (case-insensitive
        exact match against the `name` field). The API has no dedicated
        filter for this, so the module runs a full-text query (`q=<n>`)
        against /request_forms and returns the item whose `name` matches
        exactly. Throws if 0 or >1 exact matches come back. `-LanguageCode`
        is required by the API when using `q=`; the -Name path defaults it
        to `en-us` — pass -LanguageCode explicitly if your tenant's forms
        are indexed in a different language.

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

        Retrieves the offboarding form definition by slug, including its field list.

    .EXAMPLE
        Get-UKGHRSDRequestForm -Name 'Time Off & Accruals'

        Retrieves the form whose display name matches exactly, using the
        API's full-text search with language_code=en-us by default.

    .EXAMPLE
        Get-UKGHRSDRequestForm -Name 'ConfÃ©s payÃ©s' -LanguageCode 'fr-fr'

        Same lookup on a non-English tenant.

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

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [Alias('title')]
        [string]$Name,

        [Parameter(ParameterSetName = 'List')]
        [string]$CategoryId,

        [Parameter(ParameterSetName = 'List')]
        [bool]$IsDefault,

        [Parameter(ParameterSetName = 'List')]
        [bool]$Featured,

        [Parameter(ParameterSetName = 'List')]
        [Parameter(ParameterSetName = 'ByName')]
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

        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            # /request_forms has no dedicated name filter, only full-text q,
            # which UKG additionally requires be paired with language_code.
            # Default to en-us so the common case is a one-liner; overridable
            # via -LanguageCode for non-English tenants. Then narrow client-side
            # to items whose display name matches exactly (case-insensitive) --
            # q is fuzzy and can return unrelated forms whose keywords or
            # descriptions happen to contain the same words.
            $lang = if ($LanguageCode) { $LanguageCode } else { 'en-us' }
            $q = @{
                q             = $Name
                language_code = $lang
            }
            if ($RawFaasFormat) { $q['f'] = '1' }

            $candidates = @(Invoke-UKGHRSDRequest -Method Get -Path '/request_forms' -Query $q)
            $exact      = @($candidates | Where-Object { $_.name -eq $Name })

            if ($exact.Count -eq 0) {
                throw "No request form found with name = '$Name' (searched in language '$lang'). If your tenant's forms are indexed in a different language, pass -LanguageCode explicitly."
            }
            if ($exact.Count -gt 1) {
                throw "Multiple request forms ($($exact.Count)) matched name = '$Name'. Inspect the raw results with: Get-UKGHRSDRequestForm -Query '$Name' -LanguageCode '$lang'"
            }
            return $exact[0]
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
