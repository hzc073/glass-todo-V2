param(
    [switch]$Zip,
    [string]$OutRoot,
    [ValidateSet('debug', 'profile', 'release')]
    [string]$FlutterMode = 'release',
    [switch]$SkipFlutterPublish,
    [switch]$SkipNpmInstall
)

$ErrorActionPreference = 'Stop'

$DeployDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ServerDir = (Resolve-Path (Join-Path $DeployDir '..')).Path
$RepoRoot = (Resolve-Path (Join-Path $ServerDir '..')).Path

if (-not $OutRoot) {
    $OutRoot = Join-Path $RepoRoot 'release'
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$packageName = "GlassTodo-Portable-$timestamp"
$packageDir = Join-Path $OutRoot $packageName
$backendDir = Join-Path $packageDir 'backend'
$dataDir = Join-Path $packageDir 'data'
$attachmentsDir = Join-Path $dataDir 'attachments'

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null
if (Test-Path -LiteralPath $packageDir) {
    throw "Output already exists: $packageDir"
}

if (-not $SkipFlutterPublish) {
    $publishScript = Join-Path $DeployDir 'scripts\\publish_flutter_web.ps1'
    if (-not (Test-Path -LiteralPath $publishScript)) {
        throw "Publish script not found: $publishScript"
    }
    & $publishScript -Mode $FlutterMode
}

if (-not $SkipNpmInstall) {
    $nodeModulesPath = Join-Path $ServerDir 'node_modules'
    if (-not (Test-Path -LiteralPath $nodeModulesPath)) {
        $npmCmd = Join-Path $ServerDir 'bin\\npm.cmd'
        if (-not (Test-Path -LiteralPath $npmCmd)) { $npmCmd = 'npm' }

        Write-Host '[Info] Installing backend dependencies...'
        Push-Location $ServerDir
        try {
            & $npmCmd install
        } finally {
            Pop-Location
        }
    }
}

Write-Host '[Info] Assembling portable package...'
New-Item -ItemType Directory -Force -Path $backendDir | Out-Null
New-Item -ItemType Directory -Force -Path $attachmentsDir | Out-Null

Write-Host "       Backend: $backendDir"
Write-Host "       Data   : $dataDir"

$excludeDirs = @(
    (Join-Path $ServerDir 'storage'),
    (Join-Path $ServerDir 'data'),
    (Join-Path $ServerDir 'backups')
)

$excludeFiles = @(
    'database.sqlite', '*.sqlite', '*.sqlite3', '*.db', '*.db-journal', '*.db-wal', '*.db-shm', '*.bak',
    'server.out.log', 'server.err.log'
)

$robocopyArgs = @(
    $ServerDir, $backendDir,
    '/MIR',
    '/NFL', '/NDL', '/NJH', '/NJS',
    '/XD'
) + $excludeDirs + @('/XF') + $excludeFiles

& robocopy @robocopyArgs | Out-Null

if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code: $LASTEXITCODE"
}

# Basic sanity check (avoid broken node_modules copy)
$multerDisk = Join-Path $backendDir 'node_modules\\multer\\storage\\disk.js'
if (-not (Test-Path -LiteralPath $multerDisk)) {
    throw "Packaging sanity check failed: missing multer storage at $multerDisk"
}

# Remove any .bat in backend root (avoid user confusion).
Get-ChildItem -LiteralPath $backendDir -File -Filter '*.bat' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# Create a ready-to-run .env for distribution (store data outside backend/)
$envExample = Join-Path $backendDir 'deploy\\.env.example'
$envPath = Join-Path $backendDir 'deploy\\.env'
if (Test-Path -LiteralPath $envExample) {
    $lines = Get-Content -LiteralPath $envExample
    $outLines = foreach ($line in $lines) {
        if ($line -match '^(\s*DB_PATH\s*=)') { 'DB_PATH=../data/database.sqlite'; continue }
        if ($line -match '^(\s*ATTACHMENTS_DIR\s*=)') { 'ATTACHMENTS_DIR=../data/attachments'; continue }
        if ($line -match '^(\s*API_BASE_URL\s*=)') { 'API_BASE_URL='; continue }
        $line
    }
    Set-Content -LiteralPath $envPath -Value $outLines -Encoding ASCII
}

# Top-level launcher (double-click)
$runBat = @(
    '@echo off',
    'chcp 65001 >nul',
    'cd /d "%~dp0"',
    'call "%~dp0backend\\deploy\\run.bat"'
)
Set-Content -LiteralPath (Join-Path $packageDir 'run.bat') -Value $runBat -Encoding ASCII

$readme = @(
    '# GlassTodo Windows Portable',
    '',
    '## Start',
    '1) Double-click `run.bat`',
    '2) Open: `http://127.0.0.1:3000/` (change port in `backend\\deploy\\.env`)',
    '',
    '## Data',
    '- DB: `data\\database.sqlite`',
    '- Attachments: `data\\attachments\\`',
    '',
    '## Backup / Restore',
    '- Backup the whole `data\\` folder (stop the server first).',
    '',
    'More docs: `backend\\deploy\\README.md`'
)
Set-Content -LiteralPath (Join-Path $packageDir 'README.md') -Value $readme -Encoding UTF8

if ($Zip) {
    $zipPath = "$packageDir.zip"
    if (Get-Command tar -ErrorAction SilentlyContinue) {
        Push-Location $OutRoot
        try {
            & tar -a -c -f $zipPath $packageName
        } finally {
            Pop-Location
        }
    } else {
        Compress-Archive -Path $packageDir -DestinationPath $zipPath -Force
    }
    Write-Host "[OK] Zip created: $zipPath"
}

Write-Host "[OK] Package created: $packageDir"
