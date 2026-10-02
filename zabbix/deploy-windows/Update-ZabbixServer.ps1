# DARURAT: mengubah alamat server Zabbix di Agent 2 yang sudah terpasang (mis. IP VM Zabbix berubah).
# Jalankan di tiap PC sebagai Administrator, lewat Update-ZabbixServer.bat:
#   Update-ZabbixServer.bat 192.168.0.200
# atau langsung:  powershell -ExecutionPolicy Bypass -File Update-ZabbixServer.ps1 -NewServer 192.168.0.200
# Hanya mengubah Server= dan ServerActive= di zabbix_agent2.conf lalu restart service. Konfigurasi lain tidak disentuh.
param([Parameter(Mandatory)][string]$NewServer)

$ErrorActionPreference = "Stop"
$conf = Join-Path $env:ProgramFiles "Zabbix Agent 2\zabbix_agent2.conf"
$svc  = "Zabbix Agent 2"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Jalankan sebagai Administrator." -ForegroundColor Red; exit 1
}
if (-not (Test-Path $conf)) { Write-Host "Config tidak ditemukan: $conf (Agent 2 belum terpasang?)" -ForegroundColor Red; exit 1 }

Write-Host "Memeriksa koneksi ke ${NewServer}:10051 ..."
if (-not (Test-NetConnection $NewServer -Port 10051 -WarningAction SilentlyContinue).TcpTestSucceeded) {
    Write-Host "PERINGATAN: port 10051 tidak terjangkau di alamat baru. Config tetap diubah." -ForegroundColor Yellow
}

Copy-Item $conf "$conf.bak-$(Get-Date -Format yyyyMMdd-HHmm)"
$lines = Get-Content $conf
$lines = $lines | ForEach-Object {
    if     ($_ -match '^Server=')       { "Server=$NewServer" }
    elseif ($_ -match '^ServerActive=') { "ServerActive=$NewServer" }
    else                                { $_ }
}
Set-Content -Path $conf -Value $lines -Encoding ASCII

Restart-Service $svc
Start-Sleep -Seconds 3
$s = Get-Service $svc
Write-Host "Service '$svc': $($s.Status). Server sekarang: $NewServer" -ForegroundColor Green
Select-String -Path $conf -Pattern '^(Server|ServerActive|Hostname)=' | ForEach-Object { "  " + $_.Line }
