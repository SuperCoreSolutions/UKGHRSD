#Requires -Version 5.1
<#
.SYNOPSIS
    Build a clean PSGallery-ready package of the UKGHRSD module and (optionally)
    publish it.

.DESCRIPTION
    Publish-Module packages EVERYTHING under -Path, so publishing straight from
    the repo root also ships CLAUDE.md, Tests/, the ~30k-line ukghrsd_full.yml
    swagger spec, and any other dev-only files. This script stages a minimal
    copy in Build/staging/UKGHRSD/ and publishes that directory instead,
    producing a clean listing on PowerShell Gallery.

    Steps, in order:
      1. Validate the source manifest.
      2. Run Pester tests against the source tree (unless -SkipTests).
      3. Wipe + rebuild the staging directory with only shipping files:
             UKGHRSD.psd1, UKGHRSD.psm1, LICENSE, README.md,
             Public/*.ps1, Private/*.ps1
         (CLAUDE.md, Tests/, .git, .gitignore, Build/, ukghrsd_full.yml are
         intentionally excluded.)
      4. Validate the staged manifest.
      5. Run PSScriptAnalyzer with the PSGallery ruleset against the staged
         copy (unless -SkipAnalyzer). Any finding aborts the build.
      6. Print the ready-to-copy Publish-Module command, OR — when -Publish
         is passed with -NuGetApiKey — run it directly.

.PARAMETER OutputPath
    Where to build the staged module. Defaults to Build/staging/ next to this
    script. The UKGHRSD subfolder inside is what gets published.

.PARAMETER SkipTests
    Skip the Pester run. Useful for a quick dry-run when tests were just run.

.PARAMETER SkipAnalyzer
    Skip PSScriptAnalyzer. Not recommended for a real publish.

.PARAMETER Publish
    Actually push to PSGallery after staging + validating. Requires
    -NuGetApiKey. Without this switch, the script only stages + validates
    and prints the exact Publish-Module command.

.PARAMETER NuGetApiKey
    PSGallery API key. Required when -Publish is used. Treat as a secret;
    prefer pulling from SecretManagement or an env var over pasting inline.

.EXAMPLE
    ./Build/Publish-UKGHRSDModule.ps1
    Dry run: stages, validates, and prints the Publish-Module command.

.EXAMPLE
    ./Build/Publish-UKGHRSDModule.ps1 -Publish -NuGetApiKey $env:PSGALLERY_KEY
    Full run: stages, validates, and publishes to PSGallery.

.EXAMPLE
    ./Build/Publish-UKGHRSDModule.ps1 -SkipTests -SkipAnalyzer
    Fastest stage-only check — smoke test the packaging, no gates.
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$SkipTests,
    [switch]$SkipAnalyzer,
    [switch]$Publish,
    [string]$NuGetApiKey
)

$ErrorActionPreference = 'Stop'

$ModuleName = 'UKGHRSD'
$RepoRoot   = Split-Path -Parent $PSScriptRoot
$SourceRoot = $RepoRoot
$SourceManifest = Join-Path $SourceRoot "$ModuleName.psd1"

if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot 'staging'
}
$StagedModule = Join-Path $OutputPath $ModuleName

# --- Sanity: source manifest exists ---------------------------------------
if (-not (Test-Path $SourceManifest)) {
    throw "Source manifest not found at $SourceManifest. Is this script still in Build/ next to the module root?"
}

Write-Host "==> Validating source manifest" -ForegroundColor Cyan
$sourceManifestData = Test-ModuleManifest -Path $SourceManifest
Write-Host "    $ModuleName $($sourceManifestData.Version) — $($sourceManifestData.ExportedFunctions.Count) functions"

# --- Publish gate: keys required BEFORE we do expensive work --------------
if ($Publish -and -not $NuGetApiKey) {
    throw "-Publish requires -NuGetApiKey."
}

# --- Optional: Pester ------------------------------------------------------
if (-not $SkipTests) {
    $testsPath = Join-Path $SourceRoot 'Tests'
    if (Test-Path $testsPath) {
        Write-Host "==> Running Pester tests" -ForegroundColor Cyan
        if (-not (Get-Module -ListAvailable Pester | Where-Object Version -ge '5.0')) {
            throw "Pester 5+ required. Install with: Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck"
        }
        Import-Module Pester -MinimumVersion 5.0 -Force
        $result = Invoke-Pester -Path $testsPath -Output Detailed -PassThru
        if ($result.Result -ne 'Passed') {
            throw "Pester run did not pass (Result=$($result.Result); Failed=$($result.FailedCount); FailedContainers=$($result.FailedContainersCount)). Fix before publishing."
        }
    }
    else {
        Write-Warning "No Tests/ folder found — skipping Pester."
    }
}
else {
    Write-Host "==> Skipping Pester (-SkipTests)" -ForegroundColor Yellow
}

# --- Stage: clean + copy shipping files -----------------------------------
Write-Host "==> Staging module at $StagedModule" -ForegroundColor Cyan

if (Test-Path $StagedModule) {
    Remove-Item -Recurse -Force $StagedModule
}
New-Item -ItemType Directory -Path $StagedModule -Force | Out-Null

$topLevelFiles = @(
    "$ModuleName.psd1"
    "$ModuleName.psm1"
    'LICENSE'
    'README.md'
)
foreach ($f in $topLevelFiles) {
    $src = Join-Path $SourceRoot $f
    if (-not (Test-Path $src)) {
        throw "Required shipping file missing from source: $f"
    }
    Copy-Item -Path $src -Destination $StagedModule
}

foreach ($sub in 'Public', 'Private') {
    $srcDir = Join-Path $SourceRoot $sub
    if (-not (Test-Path $srcDir)) {
        throw "Required source folder missing: $sub"
    }
    $destDir = Join-Path $StagedModule $sub
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Copy-Item -Path (Join-Path $srcDir '*.ps1') -Destination $destDir
}

$stagedCount = (Get-ChildItem -Recurse -File $StagedModule).Count
Write-Host "    Staged $stagedCount file(s)."

# --- Validate the staged manifest -----------------------------------------
Write-Host "==> Validating staged manifest" -ForegroundColor Cyan
$stagedManifest = Join-Path $StagedModule "$ModuleName.psd1"
$stagedData = Test-ModuleManifest -Path $stagedManifest
if ($stagedData.Version -ne $sourceManifestData.Version) {
    throw "Staged manifest version ($($stagedData.Version)) doesn't match source ($($sourceManifestData.Version)). Staging drift."
}

# --- Optional: PSScriptAnalyzer against the STAGED copy -------------------
if (-not $SkipAnalyzer) {
    Write-Host "==> Running PSScriptAnalyzer (PSGallery ruleset) against staged copy" -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
        throw "PSScriptAnalyzer required. Install with: Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"
    }
    Import-Module PSScriptAnalyzer -Force
    $findings = Invoke-ScriptAnalyzer -Path $StagedModule -Recurse -Settings PSGallery
    if ($findings) {
        $findings | Format-Table -AutoSize | Out-String | Write-Host
        throw "PSScriptAnalyzer reported $($findings.Count) finding(s). Fix before publishing."
    }
    Write-Host "    Analyzer clean."
}
else {
    Write-Host "==> Skipping PSScriptAnalyzer (-SkipAnalyzer)" -ForegroundColor Yellow
}

# --- Publish or print the command -----------------------------------------
Write-Host ""
Write-Host "Staged module ready at: $StagedModule" -ForegroundColor Green
Write-Host "Version:                $($stagedData.Version)"
Write-Host "Functions exported:     $($stagedData.ExportedFunctions.Count)"
Write-Host ""

if ($Publish) {
    Write-Host "==> Publishing to PowerShell Gallery" -ForegroundColor Cyan
    Publish-Module -Path $StagedModule -NuGetApiKey $NuGetApiKey -Verbose
    Write-Host ""
    Write-Host "Published. Verify at: https://www.powershellgallery.com/packages/$ModuleName/$($stagedData.Version)" -ForegroundColor Green
}
else {
    Write-Host "Dry run complete. To publish, run:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    Publish-Module -Path '$StagedModule' -NuGetApiKey '<your-key>' -Verbose"
    Write-Host ""
    Write-Host "  ...or re-run this script with -Publish -NuGetApiKey '<your-key>'."
}
