# Export inventaris aset PC (data item "Asset: ...") dari Zabbix ke CSV yang bisa dibuka di Excel.
#   .\export-assets.ps1 -Url http://192.168.0.182:8080 -Token <API token> [-OutFile aset.csv]
# Satu baris per PC. Kolom kosong = PC belum mengirim data itu (agent belum ambil, atau WMI tidak melaporkan, mis. TPM).
param(
    [string]$Url = "http://localhost:8080",
    [Parameter(Mandatory)][string]$Token,
    [string]$GroupName = "Laptop-PC",
    [string]$OutFile = "aset-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
)

$Api = "$Url/api_jsonrpc.php"
$Headers = @{ Authorization = "Bearer $Token" }
function Invoke-Zbx($method, $params) {
    $body = @{ jsonrpc = "2.0"; method = $method; params = $params; id = 1 } | ConvertTo-Json -Depth 10
    $r = Invoke-RestMethod -Uri $Api -Method Post -Body $body -ContentType "application/json-rpc" -Headers $Headers
    if ($r.error) { throw "$method gagal: $($r.error.data)" }
    $r.result
}

# Ubah JSON hasil wmi.getall jadi teks ringkas: "Prop=nilai, Prop=nilai ; baris berikutnya". Nilai bukan JSON dibiarkan.
function Format-Value($v) {
    if ([string]::IsNullOrWhiteSpace($v)) { return "" }
    if ($v -notmatch '^\s*[\[{]') { return $v.Trim() }
    try { $parsed = $v | ConvertFrom-Json } catch { return $v }
    $lines = foreach ($row in $parsed) {   # foreach membongkar array (ConvertFrom-Json PS 5.1 mengembalikan array sebagai satu objek)
        $parts = foreach ($p in $row.PSObject.Properties) {
            $val = $p.Value
            if ($val -is [array]) { $val = ($val -join "|") }
            elseif ($p.Name -in @("Size", "Capacity", "AdapterRAM") -and "$val" -match '^\d+$') { $val = "$([math]::Round([double]$val / 1GB, 1)) GB" }
            "$($p.Name)=$val"
        }
        $parts -join ", "
    }
    $lines -join " ; "
}

$g = Invoke-Zbx "hostgroup.get" @{ filter = @{ name = @($GroupName) } }
if (-not $g) { throw "Group '$GroupName' tidak ditemukan" }
$hosts = Invoke-Zbx "host.get" @{ groupids = @($g[0].groupid); output = @("hostid", "host", "status") }
if (-not $hosts) { Write-Host "Tidak ada host di group '$GroupName'."; return }

$items = Invoke-Zbx "item.get" @{
    hostids = @($hosts.hostid); search = @{ name = "Asset:" }
    output = @("hostid", "name", "lastvalue", "lastclock")
}
$byHost = $items | Group-Object hostid -AsHashTable -AsString

$rows = foreach ($h in ($hosts | Sort-Object host)) {
    $mine = $byHost[[string]$h.hostid]
    $o = [ordered]@{ "Nama PC" = $h.host }
    $latest = 0
    foreach ($it in ($mine | Sort-Object name)) {
        $col = $it.name -replace '^Asset:\s*', ''
        $val = Format-Value $it.lastvalue
        if ($col -eq "RAM total (bytes)" -and $val -match '^\d+$') { $col = "RAM total (GB)"; $val = [math]::Round([double]$val / 1GB, 1) }
        $o[$col] = $val
        if ([int64]$it.lastclock -gt $latest) { $latest = [int64]$it.lastclock }
    }
    $o["Data terakhir"] = if ($latest -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds($latest).LocalDateTime.ToString("yyyy-MM-dd HH:mm") } else { "" }
    [pscustomobject]$o
}

# Samakan kolom antar PC (PowerShell memakai kolom baris pertama saja)
$cols = $rows | ForEach-Object { $_.PSObject.Properties.Name } | Select-Object -Unique
try { $rows | Select-Object $cols | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8 -UseCulture -ErrorAction Stop }
catch { Write-Host "Gagal menulis $OutFile : $($_.Exception.Message)`nKalau file itu sedang terbuka di Excel, tutup dulu lalu jalankan ulang." -ForegroundColor Red; exit 1 }
Write-Host "Selesai: $($rows.Count) PC ditulis ke $((Resolve-Path $OutFile).Path)"
