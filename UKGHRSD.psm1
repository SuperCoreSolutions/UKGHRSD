#Requires -Version 5.1

<#
    UKGHRSD root module.
    Dot-sources every .ps1 under Private/ and Public/, then exports only the
    Public functions. Keeping one function per file makes the module easy to
    navigate on GitHub and lets Pester target functions individually.
#>

# Resolve the folders relative to this file so the module works regardless of
# where it is installed (dev checkout, PSGallery install path, etc.).
$Private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$Public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($Private + $Public)) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($file.FullName): $_"
    }
}

# Only Public functions are part of the supported surface area.
Export-ModuleMember -Function $Public.BaseName
