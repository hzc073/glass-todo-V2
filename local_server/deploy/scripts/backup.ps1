param(
    [switch]$Zip
)

$ErrorActionPreference = 'Stop'

function Import-DotEnv([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -gt 0 -and $line[0] -eq [char]0xFEFF) { $line = $line.TrimStart([char]0xFEFF) } # UTF-8 BOM
        if (-not $line) { return }
        if ($line.StartsWith('#')) { return }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { return }
        $name = $line.Substring(0, $idx).Trim()
        if ($name.Length -gt 0 -and $name[0] -eq [char]0xFEFF) { $name = $name.TrimStart([char]0xFEFF) } # UTF-8 BOM
        $value = $line.Substring($idx + 1).Trim()
        if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        Set-Item -Path "Env:$name" -Value $value
    }
}

function Resolve-IfRelative([string]$BaseDir, [string]$MaybeRelativePath) {
    if (-not $MaybeRelativePath) { return $MaybeRelativePath }
    if ([System.IO.Path]::IsPathRooted($MaybeRelativePath)) { return $MaybeRelativePath }
    return (Join-Path $BaseDir $MaybeRelativePath)
}

$DeployDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ServerDir = (Resolve-Path (Join-Path $DeployDir '..')).Path

Import-DotEnv (Join-Path $DeployDir '.env')
if (-not $env:ATTACHMENTS_DIR) { $env:ATTACHMENTS_DIR = './data/attachments' }

$dbDriver = ($env:DB_DRIVER | ForEach-Object { $_.Trim().ToLowerInvariant() })
if (-not $dbDriver) { $dbDriver = 'sqlite' }

$dbPath = $null
if ($dbDriver -eq 'sqlite') {
    if (-not $env:DB_PATH) { $env:DB_PATH = './data/database.sqlite' }
    $dbPath = Resolve-IfRelative $ServerDir $env:DB_PATH
} elseif ($dbDriver -eq 'postgres') {
    Write-Host "[Warn] DB_DRIVER=postgres detected. This script does not dump PostgreSQL; please use pg_dump (or stop Docker and back up data/postgres)."
} else {
    Write-Host "[Warn] Unknown DB_DRIVER=$dbDriver. Skipping DB backup."
}
$attachmentsDir = Resolve-IfRelative $ServerDir $env:ATTACHMENTS_DIR

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot = Join-Path $ServerDir 'backups'
$backupDir = Join-Path $backupRoot ("backup_{0}" -f $timestamp)

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

if ($dbPath) {
    if (Test-Path -LiteralPath $dbPath) {
        Copy-Item -LiteralPath $dbPath -Destination (Join-Path $backupDir 'database.sqlite') -Force
    } else {
        Write-Host "[Warn] DB file not found: $dbPath"
    }
}

if (Test-Path -LiteralPath $attachmentsDir) {
    Copy-Item -LiteralPath $attachmentsDir -Destination (Join-Path $backupDir 'attachments') -Recurse -Force
} else {
    Write-Host "[Warn] Attachments dir not found: $attachmentsDir"
}

if ($Zip) {
    $zipPath = "$backupDir.zip"
    Compress-Archive -Path $backupDir -DestinationPath $zipPath -Force
    Write-Host "[OK] Backup zip created: $zipPath"
} else {
    Write-Host "[OK] Backup created: $backupDir"
}
