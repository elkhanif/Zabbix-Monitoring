@echo off
:: Klik dua kali. Membuat file CSV aset PC dari Zabbix di folder "hasil" (bisa dibuka di Excel).
:: Sebelum klik: copy token API dari Zabbix (Users -> API tokens -> Create), atau paste saat diminta.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-export-aset.ps1"
pause
