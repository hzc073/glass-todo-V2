@echo off
chcp 65001 >nul

setlocal enabledelayedexpansion
title Glass Todo Local Server

cd /d "%~dp0"

set "USE_LOCAL_STORAGE=false"
set "VAPID_PUBLIC_KEY="
set "VAPID_PRIVATE_KEY="
set "VAPID_SUBJECT=mailto:admin@example.com"

set "LOCAL_NODE=%~dp0bin"
set "NODE_EXE=node"
set "NPM_CMD=npm"

if exist "%LOCAL_NODE%\node.exe" (
  set "NODE_EXE=%LOCAL_NODE%\node.exe"
  set "NPM_CMD=%LOCAL_NODE%\npm.cmd"
)

echo ========================================================
echo   Glass Todo Local Server (Portable-friendly)
echo ========================================================
echo.

if not exist "node_modules" (
  echo [Info] Installing dependencies...
  call "%NPM_CMD%" install
  if !errorlevel! NEQ 0 (
    echo [Error] npm install failed.
    pause
    exit /b 1
  )
)

echo [Info] Open http://localhost:3000
start http://localhost:3000

echo [Info] Starting server...
"%NODE_EXE%" server.js

pause
