param(
    [ValidateSet('Install','Uninstall','Status')][string]$Mode = 'Install',
    [string]$GameDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$expectedBuild = '1.9.7.17.J460'
$ownedFiles = @('winmm.dll','isaac_lan_probe.dll')
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function WriteUtf8([string]$Path,[string]$Value) {
    [IO.File]::WriteAllText($Path,$Value,[Text.UTF8Encoding]::new($false))
}
function AssertRegular([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected an ordinary file: $Path"
    }
}
try {
    if (!$GameDirectory) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = [Windows.Forms.OpenFileDialog]::new()
        $dialog.Title = 'Select The Binding of Isaac Repentance+ / isaac-ng.exe'
        $dialog.Filter = 'Isaac executable|isaac-ng.exe'
        if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { exit 0 }
        $GameDirectory = Split-Path -Parent $dialog.FileName
    }
    $GameDirectory = (Resolve-Path -LiteralPath $GameDirectory).Path
    $executable = Join-Path $GameDirectory 'isaac-ng.exe'
    AssertRegular $executable
    $marker = Join-Path $GameDirectory '.isaac-lan-install'
    $dataDirectory = Join-Path $GameDirectory 'isaac-lan'
    $record = Join-Path $dataDirectory 'installation.json'
    $installed = Test-Path -LiteralPath $marker
    if ((Test-Path -LiteralPath $dataDirectory) -and ((Get-Item -LiteralPath $dataDirectory).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The extension data directory must not be a link.'
    }
    if (!$installed -and (Test-Path -LiteralPath $record)) { throw 'An installation record exists without its marker. It was left untouched.' }
    $previous = $null
    if ($installed) {
        AssertRegular $marker
        if ([IO.File]::ReadAllText($marker).Trim() -ne 'IsaacLAN/1') { throw 'Unrecognized installation marker.' }
        AssertRegular $record
        $previous = Get-Content -LiteralPath $record -Raw | ConvertFrom-Json
        if ($previous.format -ne 1) { throw 'Unsupported installation record.' }
    }
    if ($Mode -ne 'Uninstall') {
        $payload = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payload.json') -Raw | ConvertFrom-Json
        if ($payload.format -ne 1 -or $payload.game_build -ne $expectedBuild) { throw 'Invalid package manifest.' }
        foreach ($name in @('winmm.dll','isaac_lan_probe.dll','isaac_lan_check.exe')) {
            $source = Join-Path $PSScriptRoot $name
            AssertRegular $source
            if ((Hash $source) -ne $payload.files.$name) { throw "Package file failed verification: $name" }
        }
        # The checker parses the PE as data; it never starts the selected game.
        $checkOutput = (& (Join-Path $PSScriptRoot 'isaac_lan_check.exe') $executable | Out-String).Trim()
        $compatible = $LASTEXITCODE -eq 0
        if ($Mode -eq 'Status') {
            [ordered]@{installed=$installed;gameCompatible=$compatible;gameBuild=$expectedBuild;detail=$checkOutput;directory=$GameDirectory} | ConvertTo-Json
            exit 0
        }
        if (!$compatible) { throw $checkOutput }
    }
    foreach ($process in @(Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue)) {
        if ($process.Path -eq $executable) { throw 'Close this game instance before installing or uninstalling.' }
    }
    foreach ($name in $ownedFiles) {
        $destination = Join-Path $GameDirectory $name
        if (Test-Path -LiteralPath $destination) {
            AssertRegular $destination
            if (!$installed -or !$previous.files.$name -or (Hash $destination) -ne $previous.files.$name) {
                throw "Existing $name is not an unchanged Isaac LAN file. It was left untouched."
            }
        } elseif ($installed) { throw "Installed file is missing: $name" }
    }
    if ($Mode -eq 'Uninstall' -and !$installed) { Write-Output 'Isaac LAN is not installed.'; exit 0 }
    # Stage and roll back on the same volume. Never replace another extension's
    # multimedia proxy, executable, mods, or game saves.
    $transaction = Join-Path $GameDirectory ('.isaac-lan-transaction-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $transaction | Out-Null
    $touched = @()
    try {
        foreach ($name in $ownedFiles) {
            $destination = Join-Path $GameDirectory $name
            if ($installed) { Copy-Item -LiteralPath $destination -Destination (Join-Path $transaction ('old-' + $name)) }
            if ($Mode -eq 'Install') {
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $transaction $name)
            }
        }
        if ($installed) {
            Copy-Item -LiteralPath $marker -Destination (Join-Path $transaction 'marker')
            Copy-Item -LiteralPath $record -Destination (Join-Path $transaction 'record')
        }
        foreach ($name in $ownedFiles) {
            $touched += $name
            $destination = Join-Path $GameDirectory $name
            if ($Mode -eq 'Install') { Move-Item -LiteralPath (Join-Path $transaction $name) -Destination $destination -Force }
            else { Remove-Item -LiteralPath $destination }
        }
        if ($Mode -eq 'Install') {
            New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
            WriteUtf8 $record ($payload | ConvertTo-Json -Depth 5)
            WriteUtf8 $marker "IsaacLAN/1`n"
        } else {
            Remove-Item -LiteralPath $marker
            Remove-Item -LiteralPath $record
        }
    } catch {
        foreach ($name in $touched) {
            $destination = Join-Path $GameDirectory $name
            if ($installed) { Copy-Item -LiteralPath (Join-Path $transaction ('old-' + $name)) -Destination $destination -Force }
            elseif (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination }
        }
        if ($installed -and (Test-Path -LiteralPath (Join-Path $transaction 'marker')) -and (Test-Path -LiteralPath (Join-Path $transaction 'record'))) {
            Copy-Item -LiteralPath (Join-Path $transaction 'marker') -Destination $marker -Force
            Copy-Item -LiteralPath (Join-Path $transaction 'record') -Destination $record -Force
        } elseif (!$installed) {
            foreach ($path in @($marker,$record)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path } }
        }
        throw
    } finally { Remove-Item -LiteralPath $transaction -Recurse -Force }
    Write-Output $(if ($Mode -eq 'Install') {'Installed. Start the game from Steam and select Online on the main menu.'} else {'Uninstalled. Session data and logs were preserved.'})
} catch {
    Write-Error $_
    exit 1
}
