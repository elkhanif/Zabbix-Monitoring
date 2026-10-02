# Pembungkus satu-klik untuk export-assets.ps1. Dijalankan lewat Export-Aset.bat.
# Token: kalau clipboard berisi token Zabbix (64 karakter hex) dipakai otomatis lalu clipboard dikosongkan,
# kalau tidak, token diminta diketik/paste. Token tidak disimpan di mana pun.
$ZabbixUrl = "http://192.168.0.182:8080"
$OutDir    = Join-Path $PSScriptRoot "hasil"

Write-Host "Export aset dari $ZabbixUrl" -ForegroundColor Cyan
if (-not (Test-NetConnection 192.168.0.182 -Port 8080 -WarningAction SilentlyContinue).TcpTestSucceeded) {
    Write-Host "Server Zabbix tidak terjangkau. Pastikan terhubung ke jaringan kantor (atau VPN)." -ForegroundColor Red
    exit 1
}

$token = ""
$clip = try { (Get-Clipboard -Raw).Trim() } catch { "" }
if ($clip -match '^[0-9a-f]{64}$') {
    $token = $clip
    Set-Clipboard -Value " "
    Write-Host "Token diambil dari clipboard (clipboard sudah dikosongkan)." -ForegroundColor Green
} else {
    Write-Host "Copy token dari Zabbix dulu (Users -> API tokens), lalu paste di sini dengan klik kanan."
    $token = (Read-Host "Token").Trim()
}
if ($token -notmatch '^[0-9a-f]{64}$') { Write-Host "Token tidak valid (harus 64 karakter hex)." -ForegroundColor Red; exit 1 }

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$out = Join-Path $OutDir ("aset-" + (Get-Date -Format "yyyyMMdd-HHmm") + ".csv")
& (Join-Path $PSScriptRoot "export-assets.ps1") -Url $ZabbixUrl -Token $token -OutFile $out
if (Test-Path $out) { Start-Process explorer.exe "/select,`"$out`"" }
Write-Host "`nSetelah selesai, hapus tokennya di Zabbix: Users -> API tokens." -ForegroundColor Yellow
