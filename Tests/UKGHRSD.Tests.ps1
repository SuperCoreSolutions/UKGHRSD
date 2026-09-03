#Requires -Modules Pester

<#
    Pester tests for UKGHRSD.

    These are structural/unit tests that mock the HTTP layer so they run with no
    network and no real UKG tenant. As Set-/POST cmdlets are added, extend the
    "form_data resolution" and add write-path tests here.

    Run:  Invoke-Pester ./Tests
#>

# Top-level import so InModuleScope resolves during Pester's discovery phase
# (Pester 6+ enforces this); also evict any already-loaded copy of the module
# so we don't get "Multiple script or manifest modules named 'UKGHRSD' are
# currently loaded" if the user has an installed copy alongside the source.
Get-Module UKGHRSD -All | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'UKGHRSD.psd1') -Force

BeforeAll {
    $ModuleRoot = Split-Path -Parent $PSScriptRoot
    Get-Module UKGHRSD -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $ModuleRoot 'UKGHRSD.psd1') -Force
}

Describe 'Module surface' {
    It 'exports exactly the expected public functions' {
        $expected = @(
            'Connect-UKGHRSD'
            'Disconnect-UKGHRSD'
            'Get-UKGHRSDRequest'
            'Get-UKGHRSDRequestForm'
            'Get-UKGHRSDRequestFormData'
        )
        $actual = (Get-Command -Module UKGHRSD).Name | Sort-Object
        $actual | Should -Be ($expected | Sort-Object)
    }

    It 'has a valid manifest' {
        { Test-ModuleManifest (Join-Path (Split-Path -Parent $PSScriptRoot) 'UKGHRSD.psd1') } |
            Should -Not -Throw
    }
}

Describe 'Resolve-UKGHRSDBaseUrl' {
    InModuleScope UKGHRSD {
        It 'maps <Region> to <Expected>' -TestCases @(
            @{ Region = 'US';  Expected = 'https://apis.us.people-doc.com' }
            @{ Region = 'EU';  Expected = 'https://apis.eu.people-doc.com' }
            @{ Region = 'ATL'; Expected = 'https://apis.hrsd.ultipro.com' }
            @{ Region = 'TOR'; Expected = 'https://apis.hrsd.ultipro.ca' }
        ) {
            param($Region, $Expected)
            Resolve-UKGHRSDBaseUrl -Region $Region | Should -Be $Expected
        }
    }
}

Describe 'Get-UKGHRSDRequest without a session' {
    It 'throws a connect-first error' {
        Disconnect-UKGHRSD -ErrorAction SilentlyContinue
        { Get-UKGHRSDRequest -Id 'abc' } | Should -Throw '*Connect-UKGHRSD*'
    }
}

Describe 'Get-UKGHRSDErrorMessage' {
    InModuleScope UKGHRSD {
        It 'formats an OAuth 2.0 token-endpoint error with error_description' {
            $body = '{"error":"invalid_client","error_description":"Client authentication failed"}'
            $err  = [System.Management.Automation.ErrorRecord]::new(
                [Exception]::new('The remote server returned an error: (401) Unauthorized.'),
                'FakeId', 'ProtocolError', $null)
            $err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($body)

            $msg = Get-UKGHRSDErrorMessage -ErrorRecord $err
            $msg | Should -Match 'invalid_client: Client authentication failed'
        }

        It 'formats a bare OAuth error (no error_description)' {
            $body = '{"error":"invalid_grant"}'
            $err  = [System.Management.Automation.ErrorRecord]::new(
                [Exception]::new('bad'), 'FakeId', 'ProtocolError', $null)
            $err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($body)

            (Get-UKGHRSDErrorMessage -ErrorRecord $err) | Should -Match 'invalid_grant'
        }

        It 'still formats the HRSD API {message, errors} shape' {
            $body = '{"message":"Validation failed","errors":[{"field":"start_date","message":"required"}]}'
            $err  = [System.Management.Automation.ErrorRecord]::new(
                [Exception]::new('400 Bad Request'), 'FakeId', 'ProtocolError', $null)
            $err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($body)

            $msg = Get-UKGHRSDErrorMessage -ErrorRecord $err
            $msg | Should -Match 'Validation failed'
            $msg | Should -Match 'start_date: required'
        }
    }
}

Describe 'Get-UKGHRSDAccessToken error handling' {
    InModuleScope UKGHRSD {
        It 'wraps failure with token URL, helper output, and a verify hint' {
            # We assert the WIRING: Get-UKGHRSDAccessToken must call
            # Get-UKGHRSDErrorMessage and include its output plus the URL plus
            # the actionable "Verify..." tail in the thrown message. The helper
            # itself is covered by the Describe above.
            Mock Invoke-RestMethod { throw 'network fail' }
            Mock Get-UKGHRSDErrorMessage { return 'invalid_client: Client authentication failed' }

            $thrown = $null
            try {
                Get-UKGHRSDAccessToken -BaseUrl 'https://apis.staging.us.people-doc.com' `
                    -ApplicationId 'app' -ApplicationSecret 'sec' -ClientId 'cid'
            } catch { $thrown = $_.Exception.Message }

            $thrown | Should -Match 'apis\.staging\.us\.people-doc\.com/api/v2/client/tokens'
            $thrown | Should -Match 'invalid_client: Client authentication failed'
            $thrown | Should -Match 'Verify -Region, -ClientId'
            Should -Invoke Get-UKGHRSDErrorMessage -Times 1 -Exactly
        }
    }
}

Describe 'Get-UKGHRSDRequest -Id vs -RequestNumber' {
    InModuleScope UKGHRSD {
        BeforeEach {
            # Session must exist so the connect-first check doesn't fire.
            $script:UKGHRSDSession = [pscustomobject]@{
                BaseUrl     = 'https://apis.hrsd.ultipro.com'
                AccessToken = 'fake-token'
                ExpiresAt   = (Get-Date).AddHours(1)
            }
            $script:calls = New-Object 'System.Collections.Generic.List[hashtable]'
        }

        It '-Id with an all-digit value throws with a -RequestNumber hint and makes no API call' {
            Mock Invoke-UKGHRSDRequest { $script:calls.Add(@{ Path = $Path }) }

            { Get-UKGHRSDRequest -Id '6678' } |
                Should -Throw "*looks like a request number*Get-UKGHRSDRequest -RequestNumber 6678*"

            $script:calls.Count | Should -Be 0
        }

        It '-Id with a UUID hits /requests/{uuid} normally' {
            Mock Invoke-UKGHRSDRequest {
                $script:calls.Add(@{ Path = $Path; Query = $Query })
                [pscustomobject]@{ id = $Path.Split('/')[-1]; request_number = 6678 }
            }

            Get-UKGHRSDRequest -Id '0a2f5401-5e63-4f8e-9da0-eceabc557905' | Out-Null

            $script:calls.Count       | Should -Be 1
            $script:calls[0].Path     | Should -Be '/requests/0a2f5401-5e63-4f8e-9da0-eceabc557905'
        }

        It '-RequestNumber issues a q= search and returns the exact match when there is one' {
            Mock Invoke-UKGHRSDRequest {
                $script:calls.Add(@{ Path = $Path; Query = $Query })
                @(
                    [pscustomobject]@{ id = 'uuid-a'; request_number = 6678; subject = 'Report Request' }
                )
            }

            $r = Get-UKGHRSDRequest -RequestNumber 6678

            $script:calls.Count       | Should -Be 1
            $script:calls[0].Path     | Should -Be '/requests'
            $script:calls[0].Query.q  | Should -Be '6678'
            $r.id                     | Should -Be 'uuid-a'
            $r.request_number         | Should -Be 6678
        }

        It '-RequestNumber narrows fuzzy q matches to the exact request_number' {
            # q is full-text and can return items whose subject/body just
            # contains the number. Assert we filter to the exact match.
            Mock Invoke-UKGHRSDRequest {
                @(
                    [pscustomobject]@{ id = 'uuid-a'; request_number = 6678; subject = 'The one we want' }
                    [pscustomobject]@{ id = 'uuid-b'; request_number = 9999; subject = 'Ticket 6678 mentioned in body' }
                )
            }

            $r = Get-UKGHRSDRequest -RequestNumber 6678

            $r.id             | Should -Be 'uuid-a'
            $r.request_number | Should -Be 6678
        }

        It '-RequestNumber throws when no exact match is found' {
            Mock Invoke-UKGHRSDRequest { @() }

            { Get-UKGHRSDRequest -RequestNumber 6678 } |
                Should -Throw '*No request found with request_number = 6678*'
        }

        It '-Id and -RequestNumber are mutually exclusive via parameter sets' {
            Mock Invoke-UKGHRSDRequest { }
            { Get-UKGHRSDRequest -Id 'uuid' -RequestNumber 6678 } |
                Should -Throw '*Parameter set cannot be resolved*'
        }
    }
}

Describe 'form_data resolution' {
    InModuleScope UKGHRSD {
        It 'joins field_id answers to their form labels' {
            # Arrange: a fake request and its form definition.
            $fakeRequest = [pscustomobject]@{
                id             = 'req-1'
                request_number = '1001'
                form_id        = 'offboarding'
                form_data      = @(
                    [pscustomobject]@{ field_id = 'has-cc'; values = @('Yes') }
                    [pscustomobject]@{ field_id = 'laptop'; values = @('MacBook Pro') }
                )
            }
            $fakeForm = [pscustomobject]@{
                form_definition = [pscustomobject]@{
                    fields = @(
                        [pscustomobject]@{ slug = 'has-cc'; label = 'Has corporate credit card'; type_id = 'radios' }
                        [pscustomobject]@{ slug = 'laptop'; label = 'Assigned laptop';            type_id = 'text'   }
                    )
                }
            }

            Mock Get-UKGHRSDRequestForm { $fakeForm }

            # Act
            $resolved = $fakeRequest | Get-UKGHRSDRequestFormData

            # Assert
            $cc = $resolved | Where-Object FieldId -eq 'has-cc'
            $cc.Label | Should -Be 'Has corporate credit card'
            $cc.Value | Should -Be 'Yes'

            $laptop = $resolved | Where-Object FieldId -eq 'laptop'
            $laptop.Label | Should -Be 'Assigned laptop'
        }
    }
}
