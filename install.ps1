# Zarp installer for Windows.   Usage (PowerShell):  irm https://ishaandugar.github.io/zarp/install.ps1 | iex
# Reads the latest release manifest from GitHub and downloads Zarp-Setup.exe.
# Checks its size and SHA-256 against the manifest, then runs it silently. Nothing else.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$manifestUrl = 'https://github.com/IshaanDugar/zarp/releases/latest/download/manifest.json'
$siteUrl = 'https://ishaandugar.github.io/zarp/'

Write-Host ''
Write-Host '  zarp.  getting the latest version...' -ForegroundColor Yellow

try {
    $manifest = Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing
} catch {
    Write-Host "  Couldn't reach GitHub. Check your connection and try again." -ForegroundColor Red
    return
}

$payload = $manifest.payload
if ($payload -and $payload.beta_ended -eq $true) {
    Write-Host "  This release is no longer offered. See $siteUrl for the current one." -ForegroundColor Yellow
    return
}
$win = if ($payload) { $payload.windows } else { $null }
if (-not $win -or -not $win.url -or -not $win.sha256) {
    Write-Host "  There is no Windows download in the latest release yet. See $siteUrl" -ForegroundColor Yellow
    return
}

# Only download over https, and only an exact-size file.
if (-not ([string]$win.url).StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "  The download address isn't https, so I stopped. Nothing was installed." -ForegroundColor Red
    Write-Host '  Please tell us at https://github.com/IshaanDugar/zarp/issues' -ForegroundColor Red
    return
}

$version = $payload.latest
$expectedSize = [int64]$win.size
$sizeMb = [math]::Round($expectedSize / 1MB)

$dir = Join-Path ([IO.Path]::GetTempPath()) ('zarp-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$target = Join-Path $dir 'Zarp-Setup.exe'

try {
    Write-Host ("  downloading version {0} ({1} MB)..." -f $version, $sizeMb)
    try {
        Invoke-WebRequest -Uri $win.url -OutFile $target -UseBasicParsing
    } catch {
        Write-Host '  The download failed. Check your connection and try again.' -ForegroundColor Red
        return
    }

    if ((Get-Item -LiteralPath $target).Length -ne $expectedSize) {
        Write-Host '  The download is the wrong size, so I deleted it. Nothing was installed.' -ForegroundColor Red
        Write-Host '  Try again in a minute. If it keeps happening: https://github.com/IshaanDugar/zarp/issues' -ForegroundColor Red
        return
    }

    $hash = (Get-FileHash -Path $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$win.sha256).ToLowerInvariant()) {
        Write-Host "  The download doesn't match the published checksum, so I deleted it. Nothing was installed." -ForegroundColor Red
        Write-Host '  Try again in a minute. If it keeps happening: https://github.com/IshaanDugar/zarp/issues' -ForegroundColor Red
        return
    }

    Write-Host '  checksum matches. installing (about 30 seconds, no clicks needed)...'
    # /SILENT shows a small progress bar and skips every wizard page. The installer
    # then starts Zarp, which opens its setup window on the first run.
    # Wait for the installer process only. Start-Process -Wait would also wait for
    # Zarp itself (the installer starts it), so the window would hang until Zarp quits.
    $p = Start-Process -FilePath $target -ArgumentList '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -PassThru
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        Write-Host ("  The installer stopped with code {0}. Close Zarp from the tray if it's open, then run this line again." -f $p.ExitCode) -ForegroundColor Red
        return
    }
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '  installed. the Zarp setup window opens in a few seconds:' -ForegroundColor Yellow
Write-Host '  pick the folders your notes live in, press Start, then restart your AI app once.'
Write-Host '  (already set up? then it just updated, and it is running in your tray.)'
Write-Host ''
Write-Host '  anything feel off? https://github.com/IshaanDugar/zarp/issues'
Write-Host ''
