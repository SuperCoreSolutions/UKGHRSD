function Get-UKGHRSDRequestFormField {
    <#
    .SYNOPSIS
        Lists the fields of a request form as a curated, Format-Table-friendly
        object per field.

    .DESCRIPTION
        Reaching into (Get-UKGHRSDRequestForm ...).form_definition.fields works
        but is awkward and returns the raw shape (Formidable or FaaS) with noise
        that most callers don't need (accesses, autofill_* metadata, internal
        ids). This cmdlet handles both shapes and emits a flattened object per
        field with the useful properties promoted to the top level.

        Pick the form the same three ways you pick one via
        Get-UKGHRSDRequestForm: by slug (-FormId), by display name (-FormName),
        or by piping a form object (-Form).

        The original field object is preserved on a .Raw property for the edge
        cases where callers need accesses, autofill_*, or FaaS-specific fields.

    .PARAMETER Form
        A form object as returned by Get-UKGHRSDRequestForm. Accepts pipeline
        input, so you can chain: Get-UKGHRSDRequestForm -Name X | Get-UKGHRSDRequestFormField.
        Skips the extra API call the -FormId/-FormName paths make.

    .PARAMETER FormId
        Retrieve the form by its internal slug (e.g. 'time-off-accruals'),
        then enumerate its fields. Internally calls Get-UKGHRSDRequestForm -Id.

    .PARAMETER FormName
        Retrieve the form by its human-readable display name (case-insensitive
        exact match, e.g. 'Time Off & Accruals'), then enumerate its fields.
        Internally calls Get-UKGHRSDRequestForm -Name -LanguageCode.

    .PARAMETER LanguageCode
        Language for the -FormName lookup. Defaults to 'en-us'. Pass explicitly
        if your tenant's forms are indexed in a different language.

    .PARAMETER RawFaasFormat
        Passed through to Get-UKGHRSDRequestForm. When set, the .Raw property
        on each output object is in FaaS format (with 'name' / 'content' keys)
        instead of the default Formidable format ('label' / 'description').
        The curated top-level properties (Label, Description, etc.) handle
        both shapes either way.

    .PARAMETER Required
        Emit only fields where required = $true. Cheap client-side filter.

    .EXAMPLE
        Get-UKGHRSDRequestFormField -FormName 'Time Off & Accruals'

        Fetches the form by display name (defaults to LanguageCode 'en-us') and
        lists its fields.

    .EXAMPLE
        Get-UKGHRSDRequestForm -Name 'Time Off & Accruals' |
            Get-UKGHRSDRequestFormField |
            Format-Table Slug, Label, TypeId, Required -AutoSize

        Piped form object -- no extra API call inside the cmdlet.

    .EXAMPLE
        Get-UKGHRSDRequestFormField -FormId 'time-off-accruals' -Required

        Only the required fields on a form fetched by slug.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByObject')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        [pscustomobject]$Form,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [Alias('form_id')]
        [string]$FormId,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [Alias('Name', 'title')]
        [string]$FormName,

        [Parameter(ParameterSetName = 'ByName')]
        [string]$LanguageCode,

        [Parameter()]
        [switch]$RawFaasFormat,

        [Parameter()]
        [switch]$Required
    )

    process {
        # Resolve the form.
        switch ($PSCmdlet.ParameterSetName) {
            'ById' {
                $Form = Get-UKGHRSDRequestForm -Id $FormId -RawFaasFormat:$RawFaasFormat
            }
            'ByName' {
                $lang = if ($LanguageCode) { $LanguageCode } else { 'en-us' }
                $Form = Get-UKGHRSDRequestForm -Name $FormName -LanguageCode $lang -RawFaasFormat:$RawFaasFormat
            }
            # 'ByObject': $Form already bound from pipeline / parameter.
        }

        if (-not $Form) { return }

        # Defensive: a form may not surface form_definition (e.g. permissions
        # scoped it out) or may surface it empty. Warn and move on rather than
        # throw -- the caller might be piping many forms.
        $fields = $Form.form_definition.fields
        if (-not $fields) {
            Write-Warning "Form '$($Form.id)' has no form_definition.fields to enumerate."
            return
        }

        foreach ($f in $fields) {
            if ($Required -and -not $f.required) { continue }

            # Slug is the join key for form_data (matches field_id there).
            # Same fallback as Get-UKGHRSDRequestFormData: field.id when slug is absent.
            $slug = if ($f.slug) { $f.slug } elseif ($f.id) { $f.id } else { $null }

            # Label: 'label' in Formidable, 'name' in FaaS. Title/help_text
            # fields use 'content' as the visible text in both formats.
            $label = if ($f.label)   { $f.label }
                     elseif ($f.name) { $f.name }
                     else             { $null }

            # Multiple: 'multiple' in Formidable, 'multiple_selection' in FaaS.
            $multiple = if ($null -ne $f.multiple)             { [bool]$f.multiple }
                        elseif ($null -ne $f.multiple_selection) { [bool]$f.multiple_selection }
                        else                                     { $false }

            # Description: prefer 'description'; for title/help_text/instruction
            # fields the visible text sits on 'content' instead.
            $description = if ($f.description) { $f.description } else { $f.content }

            [pscustomobject]@{
                FormId      = $Form.id
                Slug        = $slug
                Label       = $label
                TypeId      = $f.type_id
                Required    = [bool]$f.required
                Multiple    = $multiple
                Description = $description
                Placeholder = $f.placeholder
                Items       = $f.items
                Defaults    = $f.defaults
                Validations = $f.validations
                Raw         = $f
            }
        }
    }
}
