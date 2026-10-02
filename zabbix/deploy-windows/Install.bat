@echo off
:: Klik dua kali. Otomatis minta hak admin lalu menjalankan installer.
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Standalone.ps1"
pause
