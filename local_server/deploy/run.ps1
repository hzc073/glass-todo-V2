$ErrorActionPreference = 'Stop'

function Get-EnvBool([string]$Name, [bool]$Default = $false) {
    $raw = (Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue).Value
    if (-not $raw) { return $Default }
    $v = $raw.Trim().ToLowerInvariant()
    if ($v -in @('1', 'true', 'yes', 'y', 'on')) { return $true }
    if ($v -in @('0', 'false', 'no', 'n', 'off')) { return $false }
    return $Default
}

function UrlEncode([string]$Value) {
    if ($null -eq $Value) { return '' }
    return [System.Uri]::EscapeDataString($Value)
}

function Test-PortInUse([int]$Port) {
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $false
    } catch {
        return $true
    } finally {
        if ($listener) { $listener.Stop() }
    }
}

function Get-FreePort([int[]]$Candidates) {
    foreach ($p in $Candidates) {
        if (-not (Test-PortInUse $p)) { return $p }
    }
    throw "No free TCP port found in candidates: $($Candidates -join ', ')"
}

function Ensure-BundledPostgres([string]$ServerDir) {
    $binDir = $env:POSTGRES_BIN_DIR
    if (-not $binDir) { $binDir = './bin/postgres/bin' }
    $binDir = Resolve-IfRelative $ServerDir $binDir

    $dataDir = $env:POSTGRES_DATA_DIR
    if (-not $dataDir) { $dataDir = './data/postgres' }
    $dataDir = Resolve-IfRelative $ServerDir $dataDir

    $host = ($env:POSTGRES_HOST | ForEach-Object { $_.Trim() })
    if (-not $host) { $host = '127.0.0.1' }

    $user = ($env:POSTGRES_USER | ForEach-Object { $_.Trim() })
    if (-not $user) { $user = 'glass' }
    $password = ($env:POSTGRES_PASSWORD | ForEach-Object { $_.Trim() })
    if (-not $password) { $password = 'glass' }
    $dbName = ($env:POSTGRES_DB | ForEach-Object { $_.Trim() })
    if (-not $dbName) { $dbName = 'glass_todo' }

    if ($user -notmatch '^[a-zA-Z0-9_]+$') { throw "POSTGRES_USER must match ^[a-zA-Z0-9_]+$ (got: $user)" }
    if ($dbName -notmatch '^[a-zA-Z0-9_]+$') { throw "POSTGRES_DB must match ^[a-zA-Z0-9_]+$ (got: $dbName)" }

    $portRaw = ($env:POSTGRES_PORT | ForEach-Object { $_.Trim() })
    [int]$port = 0
    if ($portRaw -and [int]::TryParse($portRaw, [ref]$port) -and $port -gt 0) {
        # use as-is
    } else {
        $port = Get-FreePort @(5432, 54321, 54322, 54323)
    }

    $pgCtl = Join-Path $binDir 'pg_ctl.exe'
    $initdb = Join-Path $binDir 'initdb.exe'
    $psql = Join-Path $binDir 'psql.exe'
    $createdb = Join-Path $binDir 'createdb.exe'
    $pgIsReady = Join-Path $binDir 'pg_isready.exe'

    foreach ($exe in @($pgCtl, $initdb, $psql, $createdb)) {
        if (-not (Test-Path -LiteralPath $exe)) {
            throw "Bundled PostgreSQL not found. Expected: $exe`nPlease extract PostgreSQL Windows binaries to: $binDir"
        }
    }

    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

    $startedByUs = $false
    $pgVersionFile = Join-Path $dataDir 'PG_VERSION'
    if (-not (Test-Path -LiteralPath $pgVersionFile)) {
        Write-Host "[Info] Initializing PostgreSQL data dir: $dataDir"
        $pwFile = Join-Path $env:TEMP ("pg_pw_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
        try {
            Set-Content -LiteralPath $pwFile -Value $password -NoNewline -Encoding ASCII
            & $initdb '-D' $dataDir '-U' $user '--pwfile' $pwFile '--auth-local' 'scram-sha-256' '--auth-host' 'scram-sha-256' '-E' 'UTF8' | Out-Null
        } finally {
            if (Test-Path -LiteralPath $pwFile) { Remove-Item -LiteralPath $pwFile -Force -ErrorAction SilentlyContinue }
        }
    }

    $pidFile = Join-Path $dataDir 'postmaster.pid'
    $isRunning = $false
    try {
        & $pgCtl '-D' $dataDir 'status' | Out-Null
        if ($LASTEXITCODE -eq 0) { $isRunning = $true }
    } catch {
        $isRunning = $false
    }

    if ($isRunning -and (Test-Path -LiteralPath $pidFile)) {
        try {
            $lines = Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue
            if ($lines.Count -ge 4) {
                $pidPort = [int]($lines[3])
                if ($pidPort -gt 0) { $port = $pidPort }
            }
        } catch {}
    }

    if (-not $isRunning) {
        if (Test-PortInUse $port) {
            throw "PostgreSQL port $port is already in use. Set POSTGRES_PORT to a free port."
        }
        $logPath = $env:POSTGRES_LOG_PATH
        if (-not $logPath) { $logPath = (Join-Path $dataDir 'postgres.log') }
        $logPath = Resolve-IfRelative $ServerDir $logPath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null

        Write-Host "[Info] Starting bundled PostgreSQL on $host`:$port ..."
        $oldPgPassword = $env:PGPASSWORD
        try {
            $env:PGPASSWORD = $password
            & $pgCtl '-D' $dataDir '-l' $logPath '-o' ("-p {0} -h {1}" -f $port, $host) 'start' | Out-Null
        } finally {
            $env:PGPASSWORD = $oldPgPassword
        }
        $startedByUs = $true

        $timeoutSecRaw = ($env:POSTGRES_START_TIMEOUT_SEC | ForEach-Object { $_.Trim() })
        [int]$timeoutSec = 15
        if ($timeoutSecRaw -and [int]::TryParse($timeoutSecRaw, [ref]$timeoutSec) -and $timeoutSec -gt 0) { }
        $deadline = (Get-Date).AddSeconds($timeoutSec)

        $ready = $false
        while ((Get-Date) -lt $deadline) {
            try {
                if (Test-Path -LiteralPath $pgIsReady) {
                    & $pgIsReady '-h' $host '-p' $port.ToString() '-U' $user '-d' 'postgres' | Out-Null
                    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
                } else {
                    $oldPgPassword2 = $env:PGPASSWORD
                    try {
                        $env:PGPASSWORD = $password
                        & $psql '-h' $host '-p' $port.ToString() '-U' $user '-d' 'postgres' '-tAc' 'SELECT 1' | Out-Null
                        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
                    } finally {
                        $env:PGPASSWORD = $oldPgPassword2
                    }
                }
            } catch {}
            Start-Sleep -Milliseconds 300
        }
        if (-not $ready) {
            throw "PostgreSQL did not become ready in ${timeoutSec}s. Check logs in: $dataDir"
        }
    }

    # Ensure database exists.
    $oldPgPassword3 = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $password
        $exists = (& $psql '-h' $host '-p' $port.ToString() '-U' $user '-d' 'postgres' '-tAc' ("SELECT 1 FROM pg_database WHERE datname='{0}'" -f $dbName) 2>$null).Trim()
        if ($exists -ne '1') {
            Write-Host "[Info] Creating database: $dbName"
            & $createdb '-h' $host '-p' $port.ToString() '-U' $user $dbName | Out-Null
        }
    } finally {
        $env:PGPASSWORD = $oldPgPassword3
    }

    $urlUser = UrlEncode $user
    $urlPass = UrlEncode $password
    $urlDb = UrlEncode $dbName
    $databaseUrl = "postgresql://{0}:{1}@{2}:{3}/{4}" -f $urlUser, $urlPass, $host, $port, $urlDb

    return [pscustomobject]@{
        StartedByUs = $startedByUs
        DataDir = $dataDir
        PgCtlExe = $pgCtl
        Host = $host
        Port = $port
        User = $user
        DbName = $dbName
        DatabaseUrl = $databaseUrl
    }
}

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

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ServerDir = (Resolve-Path (Join-Path $ScriptDir '..')).Path

Import-DotEnv (Join-Path $ScriptDir '.env')

if (-not $env:PORT) { $env:PORT = '3000' }
if (-not $env:ATTACHMENTS_DIR) { $env:ATTACHMENTS_DIR = './data/attachments' }

$dbDriver = ($env:DB_DRIVER | ForEach-Object { $_.Trim().ToLowerInvariant() })
if (-not $dbDriver) {
    if ($env:DATABASE_URL) { $dbDriver = 'postgres' } else { $dbDriver = 'sqlite' }
    $env:DB_DRIVER = $dbDriver
}

if ($dbDriver -eq 'sqlite') {
    if (-not $env:DB_PATH) { $env:DB_PATH = './data/database.sqlite' }
    $env:DB_PATH = Resolve-IfRelative $ServerDir $env:DB_PATH
} elseif ($dbDriver -eq 'postgres') {
    $bundledPg = $null
    if (-not $env:DATABASE_URL) {
        $autoStartPg = Get-EnvBool 'AUTO_START_POSTGRES' $false
        if (-not $autoStartPg) {
            throw "DB_DRIVER=postgres requires DATABASE_URL, or set AUTO_START_POSTGRES=true to use bundled PostgreSQL."
        }
        $bundledPg = Ensure-BundledPostgres $ServerDir
        $env:DATABASE_URL = $bundledPg.DatabaseUrl
        Write-Host ("[Info] PostgreSQL ready: {0}:{1}/{2} (user={3})" -f $bundledPg.Host, $bundledPg.Port, $bundledPg.DbName, $bundledPg.User)
    } else {
        Write-Host "[Info] Using PostgreSQL from DATABASE_URL."
    }
} else {
    throw "Unsupported DB_DRIVER: $dbDriver (supported: postgres, sqlite)"
}

$env:ATTACHMENTS_DIR = Resolve-IfRelative $ServerDir $env:ATTACHMENTS_DIR

if ($dbDriver -eq 'sqlite') {
    $dbDir = Split-Path -Parent $env:DB_PATH
    New-Item -ItemType Directory -Force -Path $dbDir | Out-Null
}
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
try {
    & $NodeExe 'server.js'
} finally {
    if ($dbDriver -eq 'postgres' -and $bundledPg -and $bundledPg.StartedByUs -and (Get-EnvBool 'STOP_POSTGRES_ON_EXIT' $true)) {
        try {
            Write-Host '[Info] Stopping bundled PostgreSQL...'
            & $bundledPg.PgCtlExe '-D' $bundledPg.DataDir '-m' 'fast' 'stop' | Out-Null
        } catch {
            Write-Host "[Warn] Failed to stop PostgreSQL: $($_.Exception.Message)"
        }
    }
}
