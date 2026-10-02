# Membuat template "Asset Windows - Hardware" (item WMI untuk inventaris aset) lewat Zabbix API,
# lalu memasangnya ke host group Laptop-PC (yang sudah ada + PC baru lewat autoregistration).
#   .\setup-asset-template.ps1 -Url http://192.168.0.182:8080 -Token <API token>
# Aman dijalankan ulang: template, item, action, dan link template yang sudah ada dilewati.
# Butuh Zabbix Agent 2 (Windows) di PC; item pakai wmi.get / wmi.getall (agent active).
param(
    [string]$Url = "http://localhost:8080",
    [Parameter(Mandatory)][string]$Token,
    [string]$TemplateName = "Asset Windows - Hardware",
    [string]$BaseTemplateName = "Windows by Zabbix agent active",
    [string]$GroupName = "Laptop-PC"
)

$Api = "$Url/api_jsonrpc.php"
$Headers = @{ Authorization = "Bearer $Token" }
function Invoke-Zbx($method, $params) {
    $body = @{ jsonrpc = "2.0"; method = $method; params = $params; id = 1 } | ConvertTo-Json -Depth 10
    $r = Invoke-RestMethod -Uri $Api -Method Post -Body $body -ContentType "application/json-rpc" -Headers $Headers
    if ($r.error) { throw "$method gagal: $($r.error.data)" }
    $r.result
}

# ID field inventory host (Zabbix): 5=os, 8=serialno_a, 12=macaddress_a, 14=hardware, 29=model, 31=vendor.
# Hanya kosmetik (mengisi tab Inventory). Kalau salah, export-assets.ps1 tetap benar karena membaca item, bukan inventory.
$Items = @(
    # Name, Key, ValueType (4=text, 3=unsigned), Delay, InventoryLink (0=tidak)
    @("Asset: Manufacturer",        'wmi.get[root\cimv2,"SELECT Manufacturer FROM Win32_ComputerSystem"]', 4, "1h",31),
    @("Asset: Model",               'wmi.get[root\cimv2,"SELECT Model FROM Win32_ComputerSystem"]',        4, "1h",29),
    @("Asset: Serial number",       'wmi.get[root\cimv2,"SELECT SerialNumber FROM Win32_BIOS"]',           4, "1h",8),
    @("Asset: CPU",                 'wmi.get[root\cimv2,"SELECT Name FROM Win32_Processor"]',              4, "1h",14),
    @("Asset: Motherboard",         'wmi.getall[root\cimv2,"SELECT Manufacturer,Product,SerialNumber FROM Win32_BaseBoard"]', 4, "1h",0),
    @("Asset: TPM",                 'wmi.getall[root\cimv2\Security\MicrosoftTpm,"SELECT SpecVersion,ManufacturerIdTxt,ManufacturerVersion FROM Win32_Tpm"]', 4, "1h",0),
    @("Asset: RAM total (bytes)",   'wmi.get[root\cimv2,"SELECT TotalPhysicalMemory FROM Win32_ComputerSystem"]', 3, "1h", 0),
    @("Asset: RAM modules",         'wmi.getall[root\cimv2,"SELECT Capacity,Manufacturer,PartNumber,Speed FROM Win32_PhysicalMemory"]', 4, "1h",0),
    @("Asset: GPU",                 'wmi.getall[root\cimv2,"SELECT Name,AdapterRAM,DriverVersion FROM Win32_VideoController"]', 4, "1h",0),
    @("Asset: Monitor",             'wmi.getall[root\cimv2,"SELECT Name,MonitorManufacturer,ScreenWidth,ScreenHeight FROM Win32_DesktopMonitor"]', 4, "1h",0),
    @("Asset: Disks",               'wmi.getall[root\cimv2,"SELECT Model,SerialNumber,Size,MediaType,InterfaceType FROM Win32_DiskDrive"]', 4, "1h",0),
    @("Asset: Printers",            'wmi.getall[root\cimv2,"SELECT Name,DriverName,PortName FROM Win32_Printer"]', 4, "1h",0),
    @("Asset: OS",                  'wmi.get[root\cimv2,"SELECT Caption FROM Win32_OperatingSystem"]',     4, "1h",5),
    @("Asset: OS details",          'wmi.getall[root\cimv2,"SELECT Caption,Version,BuildNumber,OSArchitecture FROM Win32_OperatingSystem"]', 4, "1h",0),
    @("Asset: Network adapters",    'wmi.getall[root\cimv2,"SELECT Description,IPAddress,MACAddress,DHCPEnabled FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled=True"]', 4, "1h", 0),
    @("Asset: MAC address",         'wmi.get[root\cimv2,"SELECT MACAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled=True"]', 4, "1h", 12),
    @("Asset: Current user",        'wmi.get[root\cimv2,"SELECT UserName FROM Win32_ComputerSystem"]',     4, "15m", 0),
    @("Asset: Domain or workgroup", 'wmi.get[root\cimv2,"SELECT Domain FROM Win32_ComputerSystem"]',       4, "1h",0)
)

# 1. Template group + template
$tg = Invoke-Zbx "templategroup.get" @{ filter = @{ name = @("Templates") } }
if (-not $tg) { throw "Template group 'Templates' tidak ditemukan" }
$t = Invoke-Zbx "template.get" @{ filter = @{ host = @($TemplateName) } }
if ($t) { $templateId = $t[0].templateid; Write-Host "Template '$TemplateName' sudah ada." }
else {
    $templateId = (Invoke-Zbx "template.create" @{ host = $TemplateName; groups = @(@{ groupid = $tg[0].groupid }) }).templateids[0]
    Write-Host "Template '$TemplateName' dibuat."
}

# 2. Item (tipe 7 = Zabbix agent active)
# Satu field inventory hanya boleh diisi satu item per host. Field yang sudah dipakai template Windows bawaan
# (mis. OS lewat system.sw.os) tidak kita isi lagi; item tetap dibuat, hanya tanpa link inventory.
$base = Invoke-Zbx "template.get" @{ filter = @{ host = @($BaseTemplateName) } }
$used = @{}
if ($base) {
    Invoke-Zbx "item.get" @{ hostids = @($base[0].templateid); output = @("inventory_link") } |
        Where-Object { $_.inventory_link -ne "0" } | ForEach-Object { $used[[string]$_.inventory_link] = $true }
}
$have = @{}
Invoke-Zbx "item.get" @{ hostids = @($templateId); output = @("itemid", "key_", "inventory_link") } | ForEach-Object { $have[$_.key_] = $_ }
foreach ($i in $Items) {
    $name, $key, $vt, $delay, $inv = $i
    if ($inv -ne 0 -and $used.ContainsKey([string]$inv)) {
        Write-Host "  '$name': field inventory $inv sudah dipakai template '$BaseTemplateName', link inventory dilewati."
        $inv = 0
    }
    if ($have.ContainsKey($key)) {
        if ($have[$key].inventory_link -ne "0" -and $inv -eq 0) {
            Invoke-Zbx "item.update" @{ itemid = $have[$key].itemid; inventory_link = 0 } | Out-Null
            Write-Host "  '$name' sudah ada, link inventory dilepas."
        } else { Write-Host "  '$name' sudah ada, dilewati." }
        continue
    }
    $p = @{ hostid = $templateId; name = $name; key_ = $key; type = 7; value_type = $vt; delay = $delay; history = "90d"
            tags = @(@{ tag = "component"; value = "asset" }) }
    if ($vt -eq 3) { $p.trends = "365d" } else { $p.trends = "0" }
    if ($inv -ne 0) { $p.inventory_link = $inv }
    try { Invoke-Zbx "item.create" $p | Out-Null; Write-Host "  Item '$name' dibuat." }
    catch { Write-Host "  PERINGATAN: item '$name' gagal: $_" -ForegroundColor Yellow }
}

# 3. Autoregistration action kedua: PC baru otomatis dapat template ini
$act = "Autoregister Windows - Asset"
if (Invoke-Zbx "action.get" @{ filter = @{ name = @($act); eventsource = 2 } }) { Write-Host "Action '$act' sudah ada, dilewati." }
else {
    Invoke-Zbx "action.create" @{
        name = $act; eventsource = 2; status = 0
        filter = @{ evaltype = 0; conditions = @(@{ conditiontype = 24; operator = 2; value = "windows" }) }
        operations = @(@{ operationtype = 6; optemplate = @(@{ templateid = $templateId }) })
    } | Out-Null
    Write-Host "Action '$act' dibuat."
}

# 4. Pasang ke host Laptop-PC yang sudah ada (hanya yang belum punya template ini)
$g = Invoke-Zbx "hostgroup.get" @{ filter = @{ name = @($GroupName) } }
if (-not $g) { Write-Host "Group '$GroupName' tidak ada, lewati link ke host."; return }
$hosts = Invoke-Zbx "host.get" @{ groupids = @($g[0].groupid); selectParentTemplates = @("templateid"); output = @("hostid", "host") }
$n = 0
foreach ($h in $hosts) {
    if ($h.parentTemplates | Where-Object { $_.templateid -eq $templateId }) { continue }
    try { Invoke-Zbx "host.massadd" @{ hosts = @(@{ hostid = $h.hostid }); templates = @(@{ templateid = $templateId }) } | Out-Null; $n++ }
    catch { Write-Host "PERINGATAN: gagal memasang ke host '$($h.host)': $_" -ForegroundColor Yellow }
}
Write-Host "Template dipasang ke $n host dari $($hosts.Count) host di '$GroupName'."
Write-Host "Selesai. Data pertama muncul beberapa menit setelah agent mengambil daftar item (Monitoring -> Latest data)."
