function Get-UKGHRSDRequestFormData {
    <#
    .SYNOPSIS
        Resolves a request's form answers into readable label/value pairs.

    .DESCRIPTION
        A request's manager-entered answers arrive as raw { field_id, values }
        pairs in its form_data. On their own these are opaque. This cmdlet joins
        each answer to its field definition (from the request's form) so you get
        back the human-readable field label alongside the value.

        For an offboarding workflow this is what turns:
            field_id = 'a1b2...'  ->  values = @('Yes')
        into:
            Label = 'Has corporate credit card'  ->  Value = 'Yes'

        Accepts either a request object (from Get-UKGHRSDRequest) or a -RequestId.
        Form definitions are looked up once per form and cached for the duration
        of the call, so resolving many requests that share a form stays cheap.

    .PARAMETER Request
        A request object (as returned by Get-UKGHRSDRequest). Accepts pipeline input.

    .PARAMETER RequestId
        A request ID to fetch and resolve, if you don't already have the object.

    .PARAMETER IncludeEmpty
        Include fields that exist on the form but have no answer on this request.

    .EXAMPLE
        Get-UKGHRSDRequest -FormId 'offboarding' -Status opened |
            Get-UKGHRSDRequestFormData

        Lists each open offboarding request's answers as label/value pairs.

    .EXAMPLE
        Get-UKGHRSDRequestFormData -RequestId '0a2f5401-...' |
            Where-Object Label -match 'credit card'

        Pulls just the corporate-credit-card answer for one request.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByObject')]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        [pscustomobject]$Request,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$RequestId,

        [switch]$IncludeEmpty
    )

    begin {
        # Cache form definitions across piped requests: form_id -> field map.
        # Each field map is slug/id -> [pscustomobject]@{ Label; TypeId }.
        $formFieldCache = @{}

        function Get-FormFieldMap {
            param([string]$FormId)

            if ($formFieldCache.ContainsKey($FormId)) {
                return $formFieldCache[$FormId]
            }

            $map = @{}
            try {
                $form = Get-UKGHRSDRequestForm -Id $FormId
            }
            catch {
                Write-Warning "Could not retrieve form '$FormId': $($_.Exception.Message)"
                $formFieldCache[$FormId] = $map
                return $map
            }

            # form_definition.fields carries slug + label + type_id (Formidable format).
            $fields = $form.form_definition.fields
            foreach ($field in $fields) {
                # Key on slug (matches field_id in form_data). Fall back to id if present.
                $key = if ($field.slug) { $field.slug } elseif ($field.id) { $field.id } else { $null }
                if ($null -ne $key) {
                    $map[$key] = [pscustomobject]@{
                        Label  = $field.label
                        TypeId = $field.type_id
                    }
                }
            }

            $formFieldCache[$FormId] = $map
            return $map
        }
    }

    process {
        # Resolve the request object if only an ID was given.
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $Request = Get-UKGHRSDRequest -Id $RequestId
        }

        if (-not $Request) { return }

        $formId = $Request.form_id
        if (-not $formId) {
            Write-Warning "Request '$($Request.id)' has no form_id; cannot resolve field labels."
            return
        }

        $fieldMap = Get-FormFieldMap -FormId $formId

        # Index the request's answers by field_id for quick lookup.
        $answers = @{}
        foreach ($fd in @($Request.form_data)) {
            if ($fd.field_id) { $answers[$fd.field_id] = $fd.values }
        }

        # Decide which fields to emit: those with answers, plus (optionally) empties.
        $fieldIds = if ($IncludeEmpty) {
            @($fieldMap.Keys + $answers.Keys | Select-Object -Unique)
        } else {
            @($answers.Keys)
        }

        foreach ($fid in $fieldIds) {
            $values = if ($answers.ContainsKey($fid)) { $answers[$fid] } else { @() }
            $meta   = $fieldMap[$fid]   # may be $null if the field isn't in the form def

            [pscustomobject]@{
                RequestId     = $Request.id
                RequestNumber = $Request.request_number
                FormId        = $formId
                FieldId       = $fid
                Label         = if ($meta) { $meta.Label } else { $null }
                TypeId        = if ($meta) { $meta.TypeId } else { $null }
                # Collapse single-value arrays to a scalar for readability;
                # multi-value answers stay as an array.
                Value         = if (@($values).Count -eq 1) { @($values)[0] } else { $values }
            }
        }
    }
}
