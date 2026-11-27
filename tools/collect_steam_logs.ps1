param(
    [string]$MyGamesDirectory,
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $MyGamesDirectory) {
    $MyGamesDirectory = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games'
}
if (-not $OutputDirectory) {
    $downloads = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads')
    $OutputDirectory = if ($downloads) {
        $downloads.Self.Path
    } else {
        Join-Path $env:USERPROFILE 'Downloads'
    }
}
$utf8 = [Text.UTF8Encoding]::new($false)
$notes = [Collections.Generic.List[string]]::new()
$events = [Collections.Generic.List[object]]::new()
$routes = [Collections.Generic.List[object]]::new()
$timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssZ')
$token = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$notes.Add("Collected (UTC): $timestamp")
$notes.Add('Scope: two latest Isaac LAN launches; startup and up to three latest runs per launch. Times in the event log and CSV include their source time zone.')
$notes.Add('An absent sample or a negative reading means unavailable. Delivery quality is Steam in-order delivery quality (0..1). A link identifies a connection within one local launch.')
# Keep both startup milestones and the most recent failure, even in verbose logs.
function Read-LogWindow([string]$Path, [string]$Label) {
    $stream = $null
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            return
        }
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.File]::Open($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        $reader = [IO.BinaryReader]::new($stream)
        $half = 512KB
        $length = $stream.Length
        if ($length -le 2 * $half) {
            $text = $utf8.GetString($reader.ReadBytes([int]$length))
        } else {
            $notes.Add("Windowed: $Label ($length bytes; first and last 512 KiB examined)")
            $head = $utf8.GetString($reader.ReadBytes($half))
            $null = $stream.Seek($length - $half, [IO.SeekOrigin]::Begin)
            $tail = $utf8.GetString($reader.ReadBytes($half))
            $i = $head.LastIndexOf([char]10)
            $j = $tail.IndexOf([char]10)
            $text = $head.Substring(0, $i + 1)
            if ($j -ge 0) {
                $text += $tail.Substring($j + 1)
            }
        }
        if ($text) {
            $text.TrimStart([char]0xfeff) -split '\r?\n'
        }
    } catch {
        $notes.Add("Could not read: $Label ($($_.Exception.GetType().Name))")
    } finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Protect-Message([string]$Text) {
    $value = $Text
    if ($env:USERPROFILE) {
        $value = $value -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%'
    }
    $value = $value -replace '(?i)[a-z]:[/\\]+Users[/\\]+[^/\\\r\n]+', '%USERPROFILE%'
    $value = $value -replace '(?i)(userdata[/\\]+)\d+', '$1<account>'
    $value = $value -replace '(?<![a-zA-Z0-9])\d{17,20}(?![a-zA-Z0-9])', '<id>'
    return $value.Substring(0, [Math]::Min(700, $value.Length))
}

$record = [regex]'^\[(?<time>\d{4}-\d\d-\d\d [^]]+)\] \[(?:DEBUG|INFO|WARN|ERROR)\] \[pid=\d+\]\s+(?<message>.+)$'
$sample = [regex]'\bsteam_route=(?<route>direct|relay|SDR) pop=(?<pop>[-a-zA-Z0-9]+) rtt_ms=(?<rtt>-?\d+) max_jitter_us=(?<jitter>-?\d+) delivery_quality=(?<quality>-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)(?: link=(?<link>\d+))?(?=\s+steam_route=|\s*$)'
$eventPrefix = '^(?:steam_lobby|steam_p2p|game_compatibility|game_lua|frontend_bridge|native_online_entry|state_authority|network_failure|network_return|network_departure|network_peer_removed|network_rejoin_rejected|network_end|network_engine_start|network_stall|native_exception|floor_save|session_save)(?:=| |$)'
function Read-LanLog($Launch, [string]$Run, [string]$Path) {
    $label = "$($Launch.Edition)/$($Launch.Name)/$Run"
    foreach ($line in (Read-LogWindow $Path $label)) {
        $entry = $record.Match($line)
        if (-not $entry.Success) {
            continue
        }
        $time = $entry.Groups['time'].Value
        $message = $entry.Groups['message'].Value
        if ($message.StartsWith('steam_route=')) {
            foreach ($row in $sample.Matches($message)) {
                $g = $row.Groups
                $rtt = 0
                $jitter = 0
                if (-not [int]::TryParse($g['rtt'].Value, [ref]$rtt) -or -not [int]::TryParse($g['jitter'].Value, [ref]$jitter)) {
                    continue
                }
                $routes.Add([pscustomobject][ordered]@{
                        Time = $time; Edition = $Launch.Edition; Launch = $Launch.Name; Run = $Run
                        Link = $g['link'].Value; Route = $g['route'].Value; POP = $g['pop'].Value
                        RTT_ms = $rtt; MaxJitter_us = $jitter
                        DeliveryQuality = $g['quality'].Value
                    })
            }
        } elseif ($message -match $eventPrefix) {
            $when = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParseExact($time, 'yyyy-MM-dd HH:mm:ss.fffzzz', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$when)) {
                $events.Add([pscustomobject]@{ UtcTicks = $when.UtcTicks; Sequence = $events.Count; Text = "[$time] [$label] $(Protect-Message $message)" })
            }
        }
    }
}

$editions = [ordered]@{ repentance = 'Binding of Isaac Repentance'; repentance_plus = 'Binding of Isaac Repentance+' }
$candidates = foreach ($edition in $editions.Keys) {
    $manifest = Join-Path $PSScriptRoot "backends/$edition/payload.json"
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        try {
            $payload = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
            $probeHash = $payload.files.'isaac_lan_probe.dll'
            if ($probeHash -match '^[0-9a-f]{64}$' -and $payload.extension_version -match '^\d+\.\d+\.\d+$') {
                $notes.Add("Installer copy ($edition): v$($payload.extension_version), probe SHA-256 $probeHash")
            }
        } catch {
            $notes.Add("Unreadable installer manifest ($edition)")
        }
    }
    $profile = Join-Path $MyGamesDirectory $editions[$edition]
    $logRoot = Join-Path $profile 'isaac-lan\logs'
    if (Test-Path -LiteralPath $logRoot -PathType Container) {
        Get-ChildItem -LiteralPath $logRoot -Directory | Where-Object {
            $_.Name -match '^\d{8}-\d{6}-\d{3}-p\d+(?:-\d+)?$' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
        } | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Path = $_.FullName; Edition = $edition } }
    }
    $gameLog = Join-Path $profile 'log.txt'
    if (Test-Path -LiteralPath $gameLog -PathType Leaf) {
        foreach ($line in (Read-LogWindow $gameLog "$edition/log.txt")) {
            if ($line -match '^\[INFO\] - (Binding of Isaac: Repentance[+]?\s+v[.A-Za-z0-9+-]+)\s*$') {
                $notes.Add("Game log ($edition): $($Matches[1])")
            }
        }
    }
}
$selected = @($candidates | Sort-Object Name -Descending | Select-Object -First 2 | Sort-Object Name)
foreach ($launch in $selected) {
    $notes.Add("Launch: $($launch.Edition)/$($launch.Name)")
    Read-LanLog $launch 'startup' (Join-Path $launch.Path 'startup.log')
    $runs = Get-ChildItem -LiteralPath $launch.Path -Directory | Where-Object {
        $_.Name -cmatch '^\d{3,}-[A-Z0-9]{8}-(host|client|solo)$' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
    } | Sort-Object Name -Descending | Select-Object -First 3 | Sort-Object Name
    foreach ($run in $runs) {
        Read-LanLog $launch $run.Name (Join-Path $run.FullName 'runtime.log')
    }
}
if (-not $selected.Count) {
    $notes.Add('No Isaac LAN launch logs were found under Documents\My Games for either supported edition.')
}
$notes.Add("Events: $($events.Count); Steam path samples: $($routes.Count)")
foreach ($group in ($routes | Group-Object Edition, Launch, Run, Link, Route, POP)) {
    $values = @($group.Group | Where-Object { $_.RTT_ms -ge 0 })
    $rtt = if ($values.Count) {
        [Math]::Round(($values | Measure-Object RTT_ms -Average).Average, 1)
    } else {
        'n/a'
    }
    $notes.Add("Route: $($group.Name); samples=$($group.Count); mean RTT ms=$rtt")
}
if (-not $routes.Count) {
    $notes.Add('No established Steam path samples in the selected log windows. Check events.log for the last lobby or connection step.')
}

$null = [IO.Directory]::CreateDirectory($OutputDirectory)
$staging = Join-Path ([IO.Path]::GetTempPath()) "isaac-lan-logs-$token"
$archive = Join-Path $OutputDirectory "Isaac-LAN-Steam-Logs-$timestamp-$token.zip"
$partial = "$archive.tmp"
$null = New-Item -Path $staging -ItemType Directory
try {
    $notes | Set-Content -LiteralPath (Join-Path $staging 'summary.txt') -Encoding UTF8
    $orderedEvents = @($events | Sort-Object UtcTicks, Sequence | ForEach-Object { $_.Text })
    [IO.File]::WriteAllLines((Join-Path $staging 'events.log'), [string[]]$orderedEvents, $utf8)
    $csv = Join-Path $staging 'routes.csv'
    if ($routes.Count) {
        $routes | Export-Csv -LiteralPath $csv -Encoding UTF8 -NoTypeInformation
    } else {
        'Time,Edition,Launch,Run,Link,Route,POP,RTT_ms,MaxJitter_us,DeliveryQuality' | Set-Content -LiteralPath $csv -Encoding UTF8
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($staging, $partial)
    [IO.File]::Move($partial, $archive)
} finally {
    if ([IO.File]::Exists($partial)) {
        [IO.File]::Delete($partial)
    }
    [IO.Directory]::Delete($staging, $true)
}
Write-Output "Saved $archive ($($events.Count) events; $($routes.Count) Steam path samples)"
