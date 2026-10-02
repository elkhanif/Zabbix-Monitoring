# Install / upgrade Zabbix Agent 2 secara silent. Dijalankan sebagai GPO Startup Script (SYSTEM).
# Idempotent: kalau versi sudah sama, langsung keluar.

$ZabbixServer = "192.168.0.182"   # IP host Docker Zabbix (ganti kalau beda)
$Version      = "7.4.15"          # samakan dengan versi server
$Share        = "\\FILESERVER\ZabbixAgent"   # share read-only: Domain Computers + Authenticated Users
$Msi          = Join-Path $Share "zabbix_agent2-$Version-windows-amd64-openssl.msi"
$Log          = "$env:ProgramData\ZabbixAgent2-install.log"

$svc = Get-Service -Name "Zabbix Agent 2" -ErrorAction SilentlyContinue
if ($svc) {
    $exe = "$env:ProgramFiles\Zabbix Agent 2\zabbix_agent2.exe"
    if ((Test-Path $exe) -and ((Get-Item $exe).VersionInfo.ProductVersion -like "$Version*")) { exit 0 }
}

if (-not (Test-Path $Msi)) { "$(Get-Date -f s) MSI tidak ditemukan: $Msi" | Add-Content $Log; exit 1 }

# Hostname = nama komputer; HostMetadata dipakai autoregistration untuk memilih template/group
$args = @(
    "/i", "`"$Msi`"", "/qn", "/l*v", "`"$Log`"",
    "SERVER=$ZabbixServer",
    "SERVERACTIVE=$ZabbixServer",
    "HOSTNAME=$env:COMPUTERNAME",
    "HOSTMETADATA=windows",
    "ENABLEPATH=1",
    "ADDLOCAL=ALL"
)
$p = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
"$(Get-Date -f s) msiexec exit code: $($p.ExitCode)" | Add-Content $Log
exit $p.ExitCode
