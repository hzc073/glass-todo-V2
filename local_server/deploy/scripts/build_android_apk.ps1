param(
    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode = 'release',
    [string]$OutRoot,
    [switch]$SplitPerAbi,
    [switch]$Clean,
    [switch]$NoPubGet,
    [switch]$OpenOutput
)

$ErrorActionPreference = 'Stop'

$DeployDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ServerDir = (Resolve-Path (Join-Path $DeployDir '..')).Path
$RepoRoot = (Resolve-Path (Join-Path $ServerDir '..')).Path

$FlutterAppDir = Join-Path $RepoRoot 'flutter_app'
if (-not (Test-Path -LiteralPath $FlutterAppDir)) {
    throw "Flutter app dir not found: $FlutterAppDir"
}

if (-not $OutRoot) {
    $OutRoot = Join-Path $RepoRoot 'release'
}
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$pubspecPath = Join-Path $FlutterAppDir 'pubspec.yaml'
$version = ''
if (Test-Path -LiteralPath $pubspecPath) {
    $match = Select-String -LiteralPath $pubspecPath -Pattern '^\s*version\s*:\s*(.+?)\s*$' | Select-Object -First 1
    if ($match -and $match.Matches.Count -gt 0) {
        $version = $match.Matches[0].Groups[1].Value.Trim()
    }
}
if ($version.Trim().Length -eq 0) { $version = 'unknown' }
$versionSafe = ($version -replace '[^0-9A-Za-z+._-]', '_')

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outName = "GlassTodo-Android-$versionSafe-$Mode-$timestamp"
$outDir = Join-Path $OutRoot $outName
if (Test-Path -LiteralPath $outDir) {
    throw "Output already exists: $outDir"
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "[Info] Building Android APK ($Mode)..."
Write-Host "       App    : $FlutterAppDir"
Write-Host "       OutDir : $outDir"

Push-Location $FlutterAppDir
try {
    if ($Clean) {
        Write-Host '[Info] flutter clean'
        & flutter clean
    }
    if (-not $NoPubGet) {
        Write-Host '[Info] flutter pub get'
        & flutter pub get
    }

    $flutterArgs = @('build', 'apk', "--$Mode")
    if ($SplitPerAbi) { $flutterArgs += '--split-per-abi' }

    & flutter @flutterArgs
} finally {
    Pop-Location
}

$apkDir = Join-Path $FlutterAppDir 'build\\app\\outputs\\flutter-apk'
if (-not (Test-Path -LiteralPath $apkDir)) {
    throw "Flutter APK output dir not found: $apkDir"
}

$apks = Get-ChildItem -LiteralPath $apkDir -File -Filter "*-$Mode.apk"
if (-not $apks) {
    $apks = Get-ChildItem -LiteralPath $apkDir -File -Filter '*.apk'
}
if (-not $apks) {
    throw "No APK found in: $apkDir"
}

Write-Host '[Info] Copying APK(s)...'
foreach ($apk in $apks) {
    $dest = Join-Path $outDir $apk.Name
    Copy-Item -LiteralPath $apk.FullName -Destination $dest -Force
    $hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host "       $($apk.Name)  sha256=$hash"
}

Write-Host "[OK] APK output: $outDir"
if ($OpenOutput) {
    Invoke-Item -LiteralPath $outDir
}

