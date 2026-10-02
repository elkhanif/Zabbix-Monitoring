@echo off
:: DARURAT: ganti alamat server Zabbix di agent. Pemakaian:  Update-ZabbixServer.bat <IP-baru>
:: Contoh:  Update-ZabbixServer.bat 192.168.0.200     (otomatis minta hak admin)
if "%~1"=="" (
    echo Pemakaian: %~nx0 ^<IP-server-Zabbix-baru^>
    pause
    exit /b 1
)
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%~1' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-ZabbixServer.ps1" -NewServer "%~1"
pause
