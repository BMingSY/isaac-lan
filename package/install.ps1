param(
    [ValidateSet('Install', 'Uninstall', 'Status')][string]$Mode = 'Install',
    [string]$GameDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ownedFiles = @('winmm.dll', 'isaac_lan_probe.dll')
$win32Errors = @{ AccessDenied = 5; SharingViolation = 32; LockViolation = 33; HandleDiskFull = 39; FileExists = 80; DiskFull = 112; AlreadyExists = 183 }
$failureCode = 'GAME_PATH'
$installationLock = $null
$lockHeld = $false
$hints = @{
    GAME_PATH = 'Select the game folder containing isaac-ng.exe (Steam > Manage > Browse local files).'
    PACKAGE_INVALID = 'Extract the entire release ZIP into a new folder and retry. Check security-software quarantine if a file is missing.'
    GAME_INCOMPATIBLE = "Use the Windows game version specified in this package manifest. In Steam, check the game version and verify installed files."
    CHECKER_FAILED = 'Run the installer from a fully extracted release ZIP. Check security-software blocks and keep the error details if the checker still cannot start.'
    GAME_RUNNING = 'Close Isaac, wait for it to exit, then retry. Do not replace DLLs while the game is running.'
    INSTALLATION_INVALID = 'Check the named installation path. Use an extracted Isaac LAN package to repair missing installation records.'
    FILE_CONFLICT = 'Back up the named file and identify its owner. Uninstall another extension with its own installer, or restore the matching Isaac LAN file from your backup, then retry.'
    PERMISSION_DENIED = 'Close programs using the named file, then check write permissions and security-software blocks. Retry as administrator only if this folder requires it.'
    FILE_IN_USE = 'Close Isaac and any program using the named file, then retry.'
    FILE_EXISTS = 'The destination already exists. Close programs using the named file and retry. If it still fails, keep the full error; do not delete the file to bypass this check.'
    DISK_FULL = 'Free space on the game drive, then retry.'
    IO_ERROR = 'Check the named path, available disk space and drive access, then retry. Keep the full error if it persists.'
    ROLLBACK_FAILED = 'Do not start the game yet. Keep the recovery folder; use recovery.json to restore the listed backups to their original paths, then retry.'
}
function Hash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try {
            return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
        } finally {
            $algorithm.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
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
function AssertDirectory([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected an ordinary directory: $Path"
    }
}
function RemoveEmptyDirectories($Paths) {
    foreach ($path in ($Paths | Sort-Object Length -Descending)) {
        try {
            if ([IO.Directory]::Exists($path) -and ![IO.Directory]::GetFileSystemEntries($path).Count) {
                [IO.Directory]::Delete($path)
            }
        } catch {
            [Console]::Error.WriteLine("Isaac LAN: Could not remove empty directory ${path}: $($_.Exception.Message)")
        }
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
function AssertManifest($Value, [string[]]$Names, [int]$ExpectedFormat = 1) {
    $format = Property $Value 'format'
    if (($format -isnot [int] -and $format -isnot [long]) -or $format -ne $ExpectedFormat) {
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
function BackendFile([string]$Backend) {
    return "isaac-lan/backends/$Backend/isaac_lan_probe.dll"
}
function InstalledFiles($Record) {
    if ((Property $Record 'format') -eq 2) {
        $backends = Property $Record 'backends'
        if ($backends -isnot [Management.Automation.PSCustomObject] -or !@($backends.PSObject.Properties).Count) {
            throw 'Invalid installed backend list.'
        }
        $names = @('winmm.dll')
        foreach ($item in $backends.PSObject.Properties) {
            if ($item.Name -cnotmatch '^j[0-9]+$' -or $item.Value -isnot [string] -or !$item.Value) {
                throw 'Invalid installed backend.'
            }
            $names += BackendFile $item.Name
        }
        AssertManifest $Record $names 2
        if (@($Record.files.PSObject.Properties).Count -ne $names.Count) {
            throw 'Unexpected installed file.'
        }
    } else {
        $names = $ownedFiles
        AssertManifest $Record $names
    }
    return $names
}
function ReadPayload([string]$Directory, $Manifest, [string]$Backend) {
    $names = $ownedFiles
    if ($Mode -ne 'Uninstall') {
        $names += 'isaac_lan_check.exe'
    }
    AssertManifest $Manifest $names
    foreach ($name in $names) {
        $source = if ($name -eq 'winmm.dll') {
            Join-Path $PSScriptRoot $name
        } else {
            Join-Path $Directory $name
        }
        AssertRegular $source
        if ((Hash $source) -ne $Manifest.files.$name) {
            throw "Package file failed verification: $name"
        }
    }
    if ([string]::IsNullOrWhiteSpace((Property $Manifest 'game_build')) -or
        ($Backend -and $Backend -cne (Property $Manifest 'backend'))) {
        throw 'Invalid package game build or backend.'
    }
    return $Manifest
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
            if ($nativeCode -in @($win32Errors.FileExists, $win32Errors.AlreadyExists)) {
                $Code = 'FILE_EXISTS'; break
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
        if ($Mode -eq 'Uninstall') {
            $dialog = [Windows.Forms.FolderBrowserDialog]::new()
            $dialog.Description = 'Select the Isaac game folder'
            $dialog.ShowNewFolderButton = $false
        } else {
            $dialog = [Windows.Forms.OpenFileDialog]::new()
            $dialog.Title = 'Select The Binding of Isaac / isaac-ng.exe'
            $dialog.Filter = 'Isaac executable|isaac-ng.exe'
        }
        try {
            if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
                exit 0
            }
            $GameDirectory = if ($Mode -eq 'Uninstall') {
                $dialog.SelectedPath
            } else {
                Split-Path -Parent $dialog.FileName
            }
        } finally {
            $dialog.Dispose()
        }
    }
    if ((Split-Path -Leaf $GameDirectory) -eq 'isaac-ng.exe' -and (Test-Path -LiteralPath $GameDirectory -PathType Leaf)) {
        $GameDirectory = Split-Path -Parent (Resolve-Path -LiteralPath $GameDirectory).ProviderPath
    }
    if (!(Test-Path -LiteralPath $GameDirectory -PathType Container)) {
        throw "Game directory does not exist or is not a directory: $GameDirectory"
    }
    $GameDirectory = (Resolve-Path -LiteralPath $GameDirectory).ProviderPath
    $executable = Join-Path $GameDirectory 'isaac-ng.exe'
    $marker = Join-Path $GameDirectory '.isaac-lan-install'
    $dataDirectory = Join-Path $GameDirectory 'isaac-lan'
    $record = Join-Path $dataDirectory 'installation.json'
    if ($Mode -ne 'Uninstall') {
        AssertRegular $executable
    }
    $failureCode = 'FILE_IN_USE'
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $key = [BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($GameDirectory.TrimEnd('\').ToUpperInvariant())))
    } finally {
        $algorithm.Dispose()
    }
    $installationLock = [Threading.Mutex]::new($false, "Local\IsaacLAN-Install-$key")
    try {
        $lockHeld = $installationLock.WaitOne(0)
    } catch [Threading.AbandonedMutexException] {
        $lockHeld = $true
    }
    if (!$lockHeld) {
        throw 'Another installer is using this game directory.'
    }
    $failureCode = 'INSTALLATION_INVALID'
    if (Test-Path -LiteralPath $dataDirectory) {
        AssertDirectory $dataDirectory
    }
    $hasMarker = Test-Path -LiteralPath $marker
    $hasRecord = Test-Path -LiteralPath $record
    $installed = $hasMarker -or $hasRecord
    if ($Mode -eq 'Uninstall' -and !$installed) {
        $possibleFiles = @('winmm.dll', 'isaac_lan_probe.dll', 'isaac-lan/backends')
        if (!($possibleFiles | Where-Object { Test-Path -LiteralPath (Join-Path $GameDirectory $_) })) {
            Write-Output 'Isaac LAN is not installed.'
            exit 0
        }
    }
    $backupModified = $false
    $previous = $null
    $previousFiles = [ordered]@{}
    $validMarker = $false
    if ($hasMarker) {
        AssertRegular $marker
        $validMarker = [IO.File]::ReadAllText($marker).Trim() -ceq 'IsaacLAN/1'
    }
    if ($hasRecord) {
        AssertRegular $record
        try {
            $previous = ReadJson $record
            foreach ($name in @(InstalledFiles $previous)) {
                $previousFiles[$name] = $previous.files.$name
            }
        } catch {
            if (!$validMarker) {
                throw
            }
            $backupModified = $true
        }
    }
    if ($hasMarker -and !$validMarker) {
        if (!$previousFiles.Count) {
            throw "Unrecognized installation marker: $marker"
        }
        $backupModified = $true
    }
    $sources = [ordered]@{}
    if ($Mode -ne 'Uninstall' -or (!$previousFiles.Count -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'payload.json')))) {
        $failureCode = 'PACKAGE_INVALID'
        $index = ReadJson (Join-Path $PSScriptRoot 'payload.json')
        $bundled = (Property $index 'format') -eq 3
        $expectedBuild = $null
        $payload = $null
        $details = @()
        if ($bundled) {
            $backends = $index.backends
            if ($backends -isnot [array] -or !$backends.Count -or
                @($backends | Select-Object -Unique).Count -ne $backends.Count) {
                throw 'Invalid package backend list.'
            }
            $parent = Join-Path $PSScriptRoot 'backends'
            AssertDirectory $parent
        } else {
            $backends = @('')
        }
        foreach ($backend in $backends) {
            $failureCode = 'PACKAGE_INVALID'
            $directory = $PSScriptRoot
            $manifest = $index
            if ($bundled) {
                if ($backend -isnot [string] -or $backend -cnotmatch '^j[0-9]+$') {
                    throw 'Invalid package backend.'
                }
                $directory = Join-Path $parent $backend
                AssertDirectory $directory
                $manifest = ReadJson (Join-Path $directory 'payload.json')
            }
            $candidate = ReadPayload $directory $manifest $backend
            if ($bundled) {
                if ($candidate.extension_version -isnot [string] -or !$candidate.extension_version -or ($candidate.loader_abi -isnot [int] -and $candidate.loader_abi -isnot [long])) {
                    throw 'Invalid extension version or loader ABI.'
                }
                if (!$payload) {
                    $payload = [ordered]@{format = 2; extension_version = $candidate.extension_version; loader_abi = $candidate.loader_abi; backends = [ordered]@{}; files = [ordered]@{'winmm.dll' = $candidate.files.'winmm.dll' } }
                    $sources['winmm.dll'] = Join-Path $PSScriptRoot 'winmm.dll'
                }
                if ($payload.extension_version -cne $candidate.extension_version -or $payload.loader_abi -ne $candidate.loader_abi) {
                    throw 'Backend extension versions or loader ABIs differ.'
                }
                $name = BackendFile $backend
                $payload.backends[$backend] = $candidate.game_build
                $payload.files[$name] = $candidate.files.'isaac_lan_probe.dll'
                $sources[$name] = Join-Path $directory 'isaac_lan_probe.dll'
            } else {
                $payload = $candidate
                foreach ($name in $ownedFiles) {
                    $sources[$name] = Join-Path $directory $name
                }
            }
            if ($Mode -eq 'Uninstall') {
                continue
            }
            # Each native checker reads the selected PE without starting the game.
            $failureCode = 'CHECKER_FAILED'
            $checkOutput = (& (Join-Path $directory 'isaac_lan_check.exe') $executable | Out-String).Trim()
            if ($LASTEXITCODE -notin @(0, 1)) {
                throw "Game checker exited with code ${LASTEXITCODE}: $checkOutput"
            }
            if ($LASTEXITCODE -eq 0) {
                if ($expectedBuild) {
                    $failureCode = 'PACKAGE_INVALID'
                    throw 'Multiple game backends match this executable.'
                }
                $expectedBuild = $candidate.game_build
                $detail = $checkOutput
            }
            $details += "$($candidate.game_build): $checkOutput"
        }
        $compatible = $null -ne $expectedBuild
        if (!$compatible) {
            $detail = $details -join "`n"
        }
        if ($Mode -eq 'Status') {
            [ordered]@{installed = $installed; gameCompatible = $compatible; gameBuild = $expectedBuild; detail = $detail; directory = $GameDirectory } | ConvertTo-Json
            exit 0
        }
        if (!$compatible -and $Mode -ne 'Uninstall') {
            $failureCode = 'GAME_INCOMPATIBLE'
            throw $detail
        }
    }
    $failureCode = 'FILE_CONFLICT'
    $names = @(@($sources.Keys) + @($previousFiles.Keys) | Select-Object -Unique)
    if ($Mode -eq 'Uninstall' -and !$previousFiles.Count) {
        $candidates = $ownedFiles
        $backendRoot = Join-Path $dataDirectory 'backends'
        if (Test-Path -LiteralPath $backendRoot -PathType Container) {
            $backendDirectory = Get-Item -LiteralPath $backendRoot -Force
            if (!($backendDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                foreach ($child in Get-ChildItem -LiteralPath $backendRoot -Directory) {
                    if ($child.Name -cmatch '^j[0-9]+$') {
                        $candidates += BackendFile $child.Name
                    }
                }
            }
        }
        $names = @(@($names) + $candidates | Select-Object -Unique)
    }
    $current = $Mode -eq 'Install' -and $validMarker -and $previousFiles.Count -gt 0 -and
    ($previous | ConvertTo-Json -Compress -Depth 5) -ceq ($payload | ConvertTo-Json -Compress -Depth 5)
    $parents = @{}
    $targets = [ordered]@{}
    $preserved = @()
    foreach ($name in $names) {
        $destination = [IO.Path]::GetFullPath((Join-Path $GameDirectory $name))
        $ancestors = @()
        for ($parent = Split-Path -Parent $destination; $parent -ne $GameDirectory; $parent = Split-Path -Parent $parent) {
            $ancestors += $parent
        }
        [array]::Reverse($ancestors)
        try {
            foreach ($parent in $ancestors) {
                if (Test-Path -LiteralPath $parent) {
                    AssertDirectory $parent
                }
            }
            if (Test-Path -LiteralPath $destination) {
                AssertRegular $destination
            }
        } catch {
            if ($Mode -ne 'Uninstall') {
                throw
            }
            $preserved += $name
            continue
        }
        if (Test-Path -LiteralPath $destination) {
            $actual = Hash $destination
            $fromPackage = $sources.Contains($name) -and $actual -eq $payload.files.$name
            $current = $current -and $fromPackage
            if (!$fromPackage -and $actual -ne $previousFiles[$name]) {
                if ($Mode -eq 'Uninstall' -or !$sources.Contains($name)) {
                    $preserved += $name
                    continue
                }
                if (!$installed -or $name -eq 'winmm.dll') {
                    throw "Another file uses $destination. It was left untouched."
                }
                $backupModified = $true
            }
        } elseif ($Mode -eq 'Uninstall') {
            continue
        } else {
            $current = $false
        }
        foreach ($parent in $ancestors) {
            $parents[$parent] = $parents[$parent] -or ($Mode -eq 'Install' -and $sources.Contains($name))
        }
        $targets[$destination] = $name.Replace('/', '_')
    }
    if ($preserved.Count) {
        Write-Output ("Preserved existing files: " + ($preserved -join ', '))
    }
    if ($Mode -eq 'Uninstall' -and !$installed -and !$targets.Count) {
        Write-Output 'Isaac LAN is not installed.'
        exit 0
    }
    if ($current) {
        Write-Output 'Isaac LAN is already installed.'; exit 0
    }
    $failureCode = 'GAME_RUNNING'
    foreach ($process in @(Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue)) {
        if ($process.Path -eq $executable) {
            throw 'Close this game instance before installing or uninstalling.'
        }
    }
    # Stage and roll back on the same volume. Never replace another extension's
    # multimedia proxy, executable, mods, or game saves.
    $failureCode = 'IO_ERROR'
    $transaction = Join-Path $GameDirectory ('.isaac-lan-transaction-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $transaction | Out-Null
    $targets[$record] = 'installation.json'
    $targets[$marker] = '.isaac-lan-install'
    $created = @()
    $backups = @{}
    $touched = @()
    $preserveRecovery = $false
    try {
        foreach ($target in $targets.Keys) {
            $backups[$target] = $null
            if (Test-Path -LiteralPath $target) {
                $backup = 'old-' + $targets[$target]
                Copy-Item -LiteralPath $target -Destination (Join-Path $transaction $backup)
                $backups[$target] = $backup
            }
        }
        $recoveryFiles = @($targets.Keys | ForEach-Object { @{path = $_; backup = $backups[$_] } })
        WriteUtf8 (Join-Path $transaction 'recovery.json') (@{directory = $GameDirectory; files = $recoveryFiles } | ConvertTo-Json -Depth 5)
        if ($Mode -eq 'Install') {
            foreach ($name in $sources.Keys) {
                $staged = Join-Path $transaction $name.Replace('/', '_')
                Copy-Item -LiteralPath $sources[$name] -Destination $staged
                if ((Hash $staged) -ne $payload.files.$name) {
                    $failureCode = 'PACKAGE_INVALID'
                    throw "Package file changed while staging: $name"
                }
            }
            WriteUtf8 (Join-Path $transaction 'installation.json') ($payload | ConvertTo-Json -Depth 5)
            WriteUtf8 (Join-Path $transaction '.isaac-lan-install') "IsaacLAN/1`n"
        }
        try {
            if ($Mode -eq 'Install') {
                $parents[$dataDirectory] = $true
                foreach ($parent in ($parents.Keys | Sort-Object Length)) {
                    if ($parents[$parent] -and !(Test-Path -LiteralPath $parent)) {
                        [IO.Directory]::CreateDirectory($parent) | Out-Null
                        $created += $parent
                    }
                }
            }
            foreach ($target in $targets.Keys) {
                $touched += $target
                $staged = Join-Path $transaction $targets[$target]
                if (Test-Path -LiteralPath $staged) {
                    Move-Item -LiteralPath $staged -Destination $target -Force
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
            RemoveEmptyDirectories $created
            if ($failures.Count -gt 0) {
                $failureCode = 'ROLLBACK_FAILED'
                throw "Operation failed: $($original.Exception.Message)`nRecovery folder: $transaction`n$($failures -join "`n")"
            }
            $preserveRecovery = $false
            throw $original
        }
        $preserveRecovery = $backupModified
    } finally {
        if (!$preserveRecovery) {
            try {
                Remove-Item -LiteralPath $transaction -Recurse -Force
            } catch {
                [Console]::Error.WriteLine("Isaac LAN: Could not remove temporary folder ${transaction}: $($_.Exception.Message)")
            }
        }
    }
    if ($backupModified) {
        Write-Output "Previous files backed up in $transaction"
    }
    RemoveEmptyDirectories @($parents.Keys | Where-Object { $_ -ne $dataDirectory })
    Write-Output $(if ($Mode -eq 'Install') {
            'Installed. Start the game from Steam.'
        } else {
            'Uninstalled. Session data and logs were preserved.'
        })
    exit 0
} catch {
    [Console]::Error.WriteLine((FailureMessage $_ $failureCode))
    exit 1
} finally {
    if ($lockHeld) {
        $installationLock.ReleaseMutex()
    }
    if ($installationLock) {
        $installationLock.Dispose()
    }
}
