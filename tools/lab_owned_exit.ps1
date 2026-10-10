param([Parameter(Mandatory = $true)][int]$GameProcessId, [Parameter(Mandatory = $true)][string]$ExpectedExecutable)
$ErrorActionPreference = 'Stop'
$process = Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue
if (-not $process) {
    Write-Output "owned_close pid=$GameProcessId already_exited=1"; exit
}
$expected = [IO.Path]::GetFullPath($ExpectedExecutable)
$lab = Split-Path (Split-Path $expected -Parent) -Parent
if (-not (Test-Path -LiteralPath (Join-Path $lab '.isaac-lan-lab')) -or $process.Path -ne $expected) {
    throw 'Owned isolated process path and marker required.'
}
$start = $process.StartTime
[void]$process.CloseMainWindow()
$forced = 0
if (-not $process.WaitForExit(45000)) {
    $remaining = Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue
    if ($remaining) {
        if ($remaining.Path -ne $expected -or $remaining.StartTime -ne $start) {
            throw 'Owned process identity changed.'
        }
        $remaining.Kill()
        if (-not $remaining.WaitForExit(5000)) {
            throw 'Owned process did not close.'
        }
        $forced = 1
    }
}
Write-Output "owned_close pid=$GameProcessId forced=$forced"
