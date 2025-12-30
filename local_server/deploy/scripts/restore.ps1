param(
    [Parameter(Mandatory = $true)]
    [string]$BackupPath
)

$ErrorActionPreference = 'Stop'

function Import-DotEnv([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        if ($line.StartsWith('#')) { return }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { return }
        $name = $line.Substring(0, $idx).Trim()
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
if (-not $env:DB_PATH) { $env:DB_PATH = './data/database.sqlite' }
if (-not $env:ATTACHMENTS_DIR) { $env:ATTACHMENTS_DIR = './data/attachments' }

$dbPath = Resolve-IfRelative $ServerDir $env:DB_PATH
$attachmentsDir = Resolve-IfRelative $ServerDir $env:ATTACHMENTS_DIR

$resolvedBackup = $BackupPath
if (-not (Test-Path -LiteralPath $resolvedBackup)) {
    throw "BackupPath not found: $BackupPath"
}

if ($resolvedBackup.ToLowerInvariant().EndsWith('.zip')) {
    $extractDir = Join-Path $ServerDir ('backups\\_restore_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    Expand-Archive -LiteralPath $resolvedBackup -DestinationPath $extractDir -Force
    $resolvedBackup = $extractDir
}

$srcDb = Join-Path $resolvedBackup 'database.sqlite'
$srcAttachments = Join-Path $resolvedBackup 'attachments'

if (-not (Test-Path -LiteralPath $srcDb)) {
    $foundDb = Get-ChildItem -LiteralPath $resolvedBackup -Recurse -File -Filter 'database.sqlite' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $foundDb) {
        throw "Backup DB file missing under: $resolvedBackup"
    }
    $resolvedBackup = Split-Path -Parent $foundDb.FullName
    $srcDb = $foundDb.FullName
    $srcAttachments = Join-Path $resolvedBackup 'attachments'
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dbPath) | Out-Null
Copy-Item -LiteralPath $srcDb -Destination $dbPath -Force

if (Test-Path -LiteralPath $srcAttachments) {
    New-Item -ItemType Directory -Force -Path $attachmentsDir | Out-Null
    Copy-Item -LiteralPath $srcAttachments -Destination $attachmentsDir -Recurse -Force
}

Write-Host "[OK] Restore completed."
Write-Host "     DB  -> $dbPath"
Write-Host "     Att -> $attachmentsDir"
