param([switch]$Check)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module PSScriptAnalyzer -RequiredVersion 1.24.0
$root = Split-Path -Parent $PSScriptRoot
$settings = @{
    IncludeRules = @('PSUseConsistentIndentation', 'PSUseConsistentWhitespace', 'PSAlignAssignmentStatement', 'PSPlaceOpenBrace', 'PSPlaceCloseBrace')
    Rules = @{
        PSUseConsistentIndentation = @{ Enable = $true; Kind = 'space'; IndentationSize = 4 }
        PSUseConsistentWhitespace = @{ Enable = $true; CheckOpenBrace = $true; CheckInnerBrace = $true; CheckOperator = $true; CheckSeparator = $true }
        PSAlignAssignmentStatement = @{ Enable = $true; CheckHashtable = $false }
        PSPlaceOpenBrace = @{ Enable = $true; OnSameLine = $true; NewLineAfter = $true; IgnoreOneLineBlock = $false }
        PSPlaceCloseBrace = @{ Enable = $true; NewLineAfter = $false; IgnoreOneLineBlock = $false; NoEmptyLineBefore = $true }
    }
}
$failed = $false
Push-Location $root
try {
    $files = foreach ($directory in @('src', 'tests', 'tools', 'package')) {
        Get-ChildItem -LiteralPath (Join-Path $root $directory) -Filter '*.ps1' -File -Recurse
    }
    foreach ($file in $files) {
        $path = $file.FullName
        $original = [IO.File]::ReadAllText($path)
        $tokens = $null
        $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($original, [ref]$tokens, [ref]$errors)
        if ($errors.Count -ne 0) {
            throw "PowerShell parse failed: $file : $errors"
        }
        $formatted = (Invoke-Formatter -ScriptDefinition $original -Settings $settings).Replace("`r`n", "`n").TrimEnd() + "`n"
        $formatted = [regex]::Replace($formatted, '(?m)[ \t]+$', '')
        if ($original -cne $formatted) {
            if ($Check) {
                Write-Output "Needs formatting: $file"; $failed = $true
            } else {
                [IO.File]::WriteAllText($path, $formatted, [Text.UTF8Encoding]::new($false))
            }
        }
    }
} finally {
    Pop-Location
}
exit ([int]$failed)
