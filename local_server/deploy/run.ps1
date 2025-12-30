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

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ServerDir = (Resolve-Path (Join-Path $ScriptDir '..')).Path

Import-DotEnv (Join-Path $ScriptDir '.env')

if (-not $env:PORT) { $env:PORT = '3000' }
if (-not $env:DB_PATH) { $env:DB_PATH = './data/database.sqlite' }
if (-not $env:ATTACHMENTS_DIR) { $env:ATTACHMENTS_DIR = './data/attachments' }

$env:DB_PATH = Resolve-IfRelative $ServerDir $env:DB_PATH
$env:ATTACHMENTS_DIR = Resolve-IfRelative $ServerDir $env:ATTACHMENTS_DIR

$dbDir = Split-Path -Parent $env:DB_PATH
New-Item -ItemType Directory -Force -Path $dbDir | Out-Null
New-Item -ItemType Directory -Force -Path $env:ATTACHMENTS_DIR | Out-Null

$NodeExe = Join-Path $ServerDir 'bin\node.exe'
$NpmCmd = Join-Path $ServerDir 'bin\npm.cmd'
if (-not (Test-Path -LiteralPath $NodeExe)) { $NodeExe = 'node' }
if (-not (Test-Path -LiteralPath $NpmCmd)) { $NpmCmd = 'npm' }

Set-Location $ServerDir

if (-not (Test-Path -LiteralPath (Join-Path $ServerDir 'node_modules'))) {
    Write-Host '[Info] Installing dependencies...'
    & $NpmCmd install
}

Write-Host "[Info] Starting server on port $($env:PORT) ..."
& $NodeExe 'server.js'
