# Installer Zabbix Agent 2 untuk PC non-domain. Jalankan lewat Install.bat (otomatis minta admin).
# Taruh file MSI di folder yang sama; kalau tidak ada, script mencoba download dari cdn.zabbix.com.

$ZabbixServer = "192.168.0.182"   # IP host Docker Zabbix (harus statis / reserved di DHCP)
$Version      = "7.4.15"          # samakan dengan versi server
$MsiName      = "zabbix_agent2-$Version-windows-amd64-openssl.msi"
$Msi          = Join-Path $PSScriptRoot $MsiName
$Log          = Join-Path $env:TEMP "ZabbixAgent2-install.log"

if (-not (Test-Path $Msi)) {
    $Msi = Join-Path $env:TEMP $MsiName
    $short = ($Version -split '\.')[0..1] -join '.'
    $url = "https://cdn.zabbix.com/zabbix/binaries/stable/$short/$Version/$MsiName"
    Write-Host "MSI tidak ada di folder ini, download dari $url ..."
    try { Invoke-WebRequest -Uri $url -OutFile $Msi -UseBasicParsing }
    catch { Write-Host "Download gagal: $_" -ForegroundColor Red; exit 1 }
}

Write-Host "Memeriksa koneksi ke $ZabbixServer`:10051 ..."
if (-not (Test-NetConnection $ZabbixServer -Port 10051 -WarningAction SilentlyContinue).TcpTestSucceeded) {
    Write-Host "PERINGATAN: port 10051 tidak terjangkau. Agent tetap dipasang, tapi belum bisa register." -ForegroundColor Yellow
}

$args = @(
    "/i", "`"$Msi`"", "/qn", "/l*v", "`"$Log`"",
    "SERVER=$ZabbixServer", "SERVERACTIVE=$ZabbixServer",
    "HOSTNAME=$env:COMPUTERNAME", "HOSTMETADATA=windows",
    "ENABLEPATH=1", "ADDLOCAL=ALL"
)
$p = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
if ($p.ExitCode -eq 0) { Write-Host "Berhasil. Host '$env:COMPUTERNAME' akan muncul di Zabbix dalam ~1-2 menit." -ForegroundColor Green }
else { Write-Host "Gagal, exit code $($p.ExitCode). Lihat log: $Log" -ForegroundColor Red }
exit $p.ExitCode
