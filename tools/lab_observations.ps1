function Get-LabObservationLayout([System.Diagnostics.Process]$GameProcess) {
    if ($GameProcess.Path -notmatch '^D:\\isaac-lan-lab\\[^\\]+\\game\\isaac-ng\.exe$') {
        throw 'An isolated game is required.'
    }
    $lab = Split-Path (Split-Path $GameProcess.Path -Parent) -Parent
    if (-not (Test-Path -LiteralPath (Join-Path $lab '.isaac-lan-lab') -PathType Leaf)) {
        throw 'A marked isolated game is required.'
    }
    $gameProfile = Get-Content -Raw -LiteralPath (Join-Path $lab 'game-profile.json') | ConvertFrom-Json
    foreach ($edition in 'repentance', 'repentance_plus') {
        $directory = Join-Path $PSScriptRoot "../src/engine/versions/$edition"
        $profile = Get-Content -Raw -LiteralPath (Join-Path $directory 'profile.json') | ConvertFrom-Json
        if ($gameProfile.game_build -ceq $profile.game_build) {
            return Import-PowerShellDataFile -LiteralPath (Join-Path $directory 'lab_observations.psd1')
        }
    }
    throw 'Unsupported isolated game layout.'
}
