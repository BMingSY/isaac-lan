param(
    [ValidateSet('Install', 'Uninstall', 'Status')][string]$Mode = 'Install',
    [string]$GameDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$expectedBuild = '1.9.7.17.J460'
$ownedFiles = @('winmm.dll', 'isaac_lan_probe.dll')
$win32Errors = @{ AccessDenied = 5; SharingViolation = 32; LockViolation = 33; HandleDiskFull = 39; DiskFull = 112 }
$failureCode = 'GAME_PATH'
$hints = @{
    GAME_PATH = 'Select the game folder containing isaac-ng.exe (Steam > Manage > Browse local files).'
    PACKAGE_INVALID = 'Extract the entire release ZIP into a new folder and retry. Check security-software quarantine if a file is missing.'
    GAME_INCOMPATIBLE = "Use Windows Repentance+ $expectedBuild. In Steam, check the game version and verify installed files."
    CHECKER_FAILED = 'Run the installer from a fully extracted release ZIP. Check security-software blocks and keep the error details if the checker still cannot start.'
    GAME_RUNNING = 'Close Isaac, wait for it to exit, then retry. Do not replace DLLs while the game is running.'
    INSTALLATION_INVALID = 'Restore .isaac-lan-install and isaac-lan/installation.json from the same installation backup. Keep session data and logs; do not delete them to bypass this check.'
    FILE_CONFLICT = 'Back up the named file and identify its owner. Uninstall another extension with its own installer, or restore the matching Isaac LAN file from your backup, then retry.'
    PERMISSION_DENIED = 'Close programs using the named file, then check write permissions and security-software blocks. Retry as administrator only if this folder requires it.'
    FILE_IN_USE = 'Close Isaac and any program using the named file, then retry.'
    DISK_FULL = 'Free space on the game drive, then retry.'
    IO_ERROR = 'Check the named path, available disk space and drive access, then retry. Keep the full error if it persists.'
    ROLLBACK_FAILED = 'Do not start the game yet. Keep the recovery folder; use recovery.json to restore the listed backups to their original paths, then retry.'
}
function Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function WriteUtf8([string]$Path, [string]$Value) {
    [IO.File]::WriteAllText($Path, $Value, [Text.UTF8Encoding]::new($false))
}
function AssertRegular([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing file or not an ordinary file: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected an ordinary file: $Path"
    }
}
function Property($Object, [string]$Name) {
    if ($null -ne $Object) {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) {
            return $property.Value
        }
    }
}
function ReadJson([string]$Path) {
    AssertRegular $Path
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        if ([string]::IsNullOrWhiteSpace($content) -or !$content.TrimStart().StartsWith('{')) {
            throw 'Expected a JSON object.'
        }
        $value = $content | ConvertFrom-Json
        if ($value -isnot [Management.Automation.PSCustomObject]) {
            throw 'Expected a JSON object.'
        }
        return $value
    } catch {
        throw "Cannot read ${Path}: $($_.Exception.Message)"
    }
}
function AssertManifest($Value, [string[]]$Names) {
    $format = Property $Value 'format'
    if (($format -isnot [int] -and $format -isnot [long]) -or $format -ne 1) {
        throw 'Unsupported manifest format.'
    }
    $files = Property $Value 'files'
    foreach ($name in $Names) {
        $hash = Property $files $name
        if ($hash -isnot [string] -or $hash -cnotmatch '^[0-9a-f]{64}$') {
            throw "Missing or invalid SHA-256 entry: $name"
        }
    }
}
function FailureMessage($Failure, [string]$Code) {
    # Preserve the recovery instructions even when the original failure was I/O.
    if ($Code -ne 'ROLLBACK_FAILED') {
        $exception = $Failure.Exception
        while ($null -ne $exception) {
            $nativeCode = $exception.HResult -band 0xffff
            if ($exception -is [ComponentModel.Win32Exception]) {
                $nativeCode = $exception.NativeErrorCode
            }
            if ($exception -is [UnauthorizedAccessException] -or $nativeCode -eq $win32Errors.AccessDenied) {
                $Code = 'PERMISSION_DENIED'; break
            }
            if ($nativeCode -in @($win32Errors.SharingViolation, $win32Errors.LockViolation)) {
                $Code = 'FILE_IN_USE'; break
            }
            if ($nativeCode -in @($win32Errors.HandleDiskFull, $win32Errors.DiskFull)) {
                $Code = 'DISK_FULL'; break
            }
            $exception = $exception.InnerException
        }
    }
    return "Isaac LAN [${Code}]: $($Failure.Exception.Message)`nNext step: $($hints[$Code])"
}
try {
    if (!$GameDirectory) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = [Windows.Forms.OpenFileDialog]::new()
        $dialog.Title = 'Select The Binding of Isaac Repentance+ / isaac-ng.exe'
        $dialog.Filter = 'Isaac executable|isaac-ng.exe'
        try {
            if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
                exit 0
            }
            $GameDirectory = Split-Path -Parent $dialog.FileName
        } finally {
            $dialog.Dispose()
        }
    }
    if (!(Test-Path -LiteralPath $GameDirectory -PathType Container)) {
        throw "Game directory does not exist or is not a directory: $GameDirectory"
    }
    $GameDirectory = (Resolve-Path -LiteralPath $GameDirectory).ProviderPath
    $executable = Join-Path $GameDirectory 'isaac-ng.exe'
    AssertRegular $executable
    $marker = Join-Path $GameDirectory '.isaac-lan-install'
    $dataDirectory = Join-Path $GameDirectory 'isaac-lan'
    $record = Join-Path $dataDirectory 'installation.json'
    $installed = Test-Path -LiteralPath $marker
    $failureCode = 'INSTALLATION_INVALID'
    if (Test-Path -LiteralPath $dataDirectory) {
        $item = Get-Item -LiteralPath $dataDirectory
        if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Expected an ordinary directory: $dataDirectory"
        }
    }
    if (!$installed -and (Test-Path -LiteralPath $record)) {
        throw "Installation record exists without its marker: $record"
    }
    $previous = $null
    if ($installed) {
        AssertRegular $marker
        if ([IO.File]::ReadAllText($marker).Trim() -ne 'IsaacLAN/1') {
            throw "Unrecognized installation marker: $marker"
        }
        $previous = ReadJson $record
        AssertManifest $previous $ownedFiles
    }
    if ($Mode -ne 'Uninstall') {
        $failureCode = 'PACKAGE_INVALID'
        $payload = ReadJson (Join-Path $PSScriptRoot 'payload.json')
        AssertManifest $payload @('winmm.dll', 'isaac_lan_probe.dll', 'isaac_lan_check.exe')
        if ((Property $payload 'game_build') -ne $expectedBuild) {
            throw 'Invalid package game_build.'
        }
        foreach ($name in @('winmm.dll', 'isaac_lan_probe.dll', 'isaac_lan_check.exe')) {
            $source = Join-Path $PSScriptRoot $name
            AssertRegular $source
            if ((Hash $source) -ne $payload.files.$name) {
                throw "Package file failed verification: $name"
            }
        }
        # The checker parses the PE as data; it never starts the selected game.
        $failureCode = 'CHECKER_FAILED'
        $checkOutput = (& (Join-Path $PSScriptRoot 'isaac_lan_check.exe') $executable | Out-String).Trim()
        if ($LASTEXITCODE -notin @(0, 1)) {
            throw "Game checker exited with code ${LASTEXITCODE}: $checkOutput"
        }
        $compatible = $LASTEXITCODE -eq 0
        if ($Mode -eq 'Status') {
            [ordered]@{installed = $installed; gameCompatible = $compatible; gameBuild = $expectedBuild; detail = $checkOutput; directory = $GameDirectory } | ConvertTo-Json
            exit 0
        }
        if (!$compatible) {
            $failureCode = 'GAME_INCOMPATIBLE'
            throw $checkOutput
        }
    }
    $failureCode = 'GAME_RUNNING'
    foreach ($process in @(Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue)) {
        if ($process.Path -eq $executable) {
            throw 'Close this game instance before installing or uninstalling.'
        }
    }
    $failureCode = 'FILE_CONFLICT'
    foreach ($name in $ownedFiles) {
        $destination = Join-Path $GameDirectory $name
        if (Test-Path -LiteralPath $destination) {
            AssertRegular $destination
            if (!$installed -or !$previous.files.$name -or (Hash $destination) -ne $previous.files.$name) {
                throw "Existing $destination is not an unchanged Isaac LAN file. It was left untouched."
            }
        }
    }
    if ($Mode -eq 'Uninstall' -and !$installed) {
        Write-Output 'Isaac LAN is not installed.'; exit 0
    }
    # Stage and roll back on the same volume. Never replace another extension's
    # multimedia proxy, executable, mods, or game saves.
    $failureCode = 'IO_ERROR'
    $transaction = Join-Path $GameDirectory ('.isaac-lan-transaction-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $transaction | Out-Null
    $targets = @($ownedFiles | ForEach-Object { Join-Path $GameDirectory $_ }) + @($record, $marker)
    $backups = @{}
    $touched = @()
    $preserveRecovery = $false
    try {
        foreach ($target in $targets) {
            $backups[$target] = $null
            if (Test-Path -LiteralPath $target) {
                $backup = 'old-' + (Split-Path -Leaf $target)
                Copy-Item -LiteralPath $target -Destination (Join-Path $transaction $backup)
                $backups[$target] = $backup
            }
        }
        $recoveryFiles = @($targets | ForEach-Object { @{path = $_; backup = $backups[$_] } })
        WriteUtf8 (Join-Path $transaction 'recovery.json') (@{directory = $GameDirectory; files = $recoveryFiles } | ConvertTo-Json -Depth 5)
        if ($Mode -eq 'Install') {
            foreach ($name in $ownedFiles) {
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $transaction $name)
            }
            WriteUtf8 (Join-Path $transaction 'installation.json') ($payload | ConvertTo-Json -Depth 5)
            WriteUtf8 (Join-Path $transaction '.isaac-lan-install') "IsaacLAN/1`n"
        }
        try {
            if ($Mode -eq 'Install') {
                if (!(Test-Path -LiteralPath $dataDirectory)) {
                    New-Item -ItemType Directory -Path $dataDirectory | Out-Null
                }
            }
            foreach ($target in $targets) {
                $touched += $target
                if ($Mode -eq 'Install') {
                    Move-Item -LiteralPath (Join-Path $transaction (Split-Path -Leaf $target)) -Destination $target -Force
                } elseif (Test-Path -LiteralPath $target) {
                    Remove-Item -LiteralPath $target
                }
            }
        } catch {
            $original = $_
            $preserveRecovery = $true
            $failures = @()
            [array]::Reverse($touched)
            foreach ($target in $touched) {
                try {
                    if ($null -ne $backups[$target]) {
                        $backup = Join-Path $transaction $backups[$target]
                        if (Test-Path -LiteralPath $target) {
                            AssertRegular $target
                            if ((Hash $target) -eq (Hash $backup)) {
                                continue
                            }
                        }
                        Copy-Item -LiteralPath $backup -Destination $target -Force
                    } elseif (Test-Path -LiteralPath $target) {
                        Remove-Item -LiteralPath $target
                    }
                } catch {
                    $failures += "${target}: $($_.Exception.Message)"
                }
            }
            if ($failures.Count -gt 0) {
                $failureCode = 'ROLLBACK_FAILED'
                throw "Operation failed: $($original.Exception.Message)`nRecovery folder: $transaction`n$($failures -join "`n")"
            }
            $preserveRecovery = $false
            throw $original
        }
    } finally {
        if (!$preserveRecovery) {
            try {
                Remove-Item -LiteralPath $transaction -Recurse -Force
            } catch {
                [Console]::Error.WriteLine("Isaac LAN: Could not remove temporary folder ${transaction}: $($_.Exception.Message)")
            }
        }
    }
    Write-Output $(if ($Mode -eq 'Install') {
            'Installed. Start the game from Steam and select Online on the main menu.'
        } else {
            'Uninstalled. Session data and logs were preserved.'
        })
} catch {
    [Console]::Error.WriteLine((FailureMessage $_ $failureCode))
    exit 1
}
