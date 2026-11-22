function Get-LabObservationLayout([System.Diagnostics.Process]$GameProcess) {
    if ($GameProcess.Path -notmatch '^D:\\isaac-lan-lab\\[^\\]+\\game\\isaac-ng\.exe$') {
        throw 'An isolated game is required.'
    }
    $lab = Split-Path (Split-Path $GameProcess.Path -Parent) -Parent
    if (-not (Test-Path -LiteralPath (Join-Path $lab '.isaac-lan-lab') -PathType Leaf)) {
        throw 'A marked isolated game is required.'
    }
    $gameProfile = Get-Content -Raw -LiteralPath (Join-Path $lab 'game-profile.json') | ConvertFrom-Json
    $backend = switch ($gameProfile.game_build) {
        '1.7.9b.J835' {
            'j835'
        }
        '1.9.7.19.J511' {
            'j511'
        }
        default {
            throw 'Unsupported isolated game layout.'
        }
    }
    return Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot "../src/engine/versions/$backend/lab_observations.psd1")
}
