param(
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode = 'release'
)

$ErrorActionPreference = 'Stop'

$DeployDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ServerDir = (Resolve-Path (Join-Path $DeployDir '..')).Path
$RepoRoot = (Resolve-Path (Join-Path $ServerDir '..')).Path

$FlutterAppDir = Join-Path $RepoRoot 'flutter_app'
$BuildDir = Join-Path $FlutterAppDir 'build\\web'
$DestDir = Join-Path $ServerDir 'public'

if (-not (Test-Path -LiteralPath $FlutterAppDir)) {
    throw "Flutter app dir not found: $FlutterAppDir"
}

Write-Host "[Info] Building Flutter web ($Mode)..."
Push-Location $FlutterAppDir
try {
    & flutter build web "--$Mode"
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $BuildDir)) {
    throw "Flutter build output not found: $BuildDir"
}

Write-Host "[Info] Publishing to backend static dir..."
Write-Host "       From: $BuildDir"
Write-Host "       To  : $DestDir"

New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

& robocopy $BuildDir $DestDir /MIR /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code: $LASTEXITCODE"
}

Write-Host "[OK] Done. Restart backend and open:"
Write-Host "     http://127.0.0.1:3000/"
