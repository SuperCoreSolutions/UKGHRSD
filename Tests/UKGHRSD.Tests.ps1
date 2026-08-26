#Requires -Modules Pester

<#
    Pester tests for UKGHRSD.

    These are structural/unit tests that mock the HTTP layer so they run with no
    network and no real UKG tenant. As Set-/POST cmdlets are added, extend the
    "form_data resolution" and add write-path tests here.

    Run:  Invoke-Pester ./Tests
#>

BeforeAll {
    $ModuleRoot = Split-Path -Parent $PSScriptRoot
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
