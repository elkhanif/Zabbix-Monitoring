# Membuat discovery rule SNMP (192.168.0.0/22, dipecah per /24) + discovery action per merek lewat Zabbix API.
#   .\setup-snmp-discovery.ps1 -Token <API token> -Community <community SNMP>
# Aman dijalankan ulang: rule/action/group yang sudah ada dilewati.
# -SyncMacros saja: hanya menyetel macro {$SNMP_COMMUNITY} di host SNMP yang belum punya (jalankan setelah ada host baru).
param(
    [string]$Url = "http://localhost:8080",
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$Community,
    [string[]]$Subnets = @("192.168.0.0/24", "192.168.1.0/24", "192.168.2.0/24", "192.168.3.0/24"),
    [string]$Delay = "1h",
    [switch]$SyncMacros
)

$Api = "$Url/api_jsonrpc.php"
$Headers = @{ Authorization = "Bearer $Token" }
function Invoke-Zbx($method, $params) {
    $body = @{ jsonrpc = "2.0"; method = $method; params = $params; id = 1 } | ConvertTo-Json -Depth 12
    $r = Invoke-RestMethod -Uri $Api -Method Post -Body $body -ContentType "application/json-rpc" -Headers $Headers
    if ($r.error) { throw "$method gagal: $($r.error.data)" }
    $r.result
}

# Jenis perangkat: pola sysDescr (contains, OR), host group, template yang di-link.
# Template yang tidak ditemukan dilewati; kalau tidak ada satu pun, dipakai "Generic by SNMP".
$Types = @(
    @{ Name = "Ubiquiti";        Group = "Network";      Templates = @("Network Generic Device by SNMP")
       Patterns = @("UniFi", "UAP", "USW", "UDM", "U6-", "U7-", "U6+", "nanoHD", "FlexHD", "EdgeSwitch", "EdgeRouter", "Ubiquiti") },
    @{ Name = "TP-Link Switch";  Group = "Network";      Templates = @("Network Generic Device by SNMP")
       Patterns = @("JetStream", "TL-SG", "TL-SL", "T1600", "T2600") },
    @{ Name = "TP-Link Omada Router"; Group = "Network"; Templates = @("Network Generic Device by SNMP")
       Patterns = @("ER605", "ER7206", "ER8411", "Omada", "TL-R") },
    @{ Name = "Ruijie Switch";   Group = "Network";      Templates = @("Network Generic Device by SNMP")
       Patterns = @("Ruijie", "RGOS", "RG-S") },
    @{ Name = "Hikvision";       Group = "Camera-NVR";   Templates = @("Generic by SNMP")
       Patterns = @("Hikvision", "HIKVISION", "DS-2CD", "DS-7", "DS-9", "iDS-") },
    @{ Name = "Synology NAS";    Group = "NAS";          Templates = @("Synology DSM by SNMP", "ICMP Ping")
       Patterns = @("Synology", "DiskStation", "RackStation") },
    @{ Name = "Epson Printer";   Group = "Printer";      Templates = @("Generic by SNMP")
       Patterns = @("EPSON", "Epson") },
    @{ Name = "Kyocera Printer"; Group = "Printer";      Templates = @("Generic by SNMP")
       Patterns = @("KYOCERA", "Kyocera", "ECOSYS", "TASKalfa") }
)

function Get-GroupId($name) {
    $g = Invoke-Zbx "hostgroup.get" @{ filter = @{ name = @($name) } }
    if ($g) { return $g[0].groupid }
    (Invoke-Zbx "hostgroup.create" @{ name = $name }).groupids[0]
}

function Set-HostMacros {
    $groupIds = $Types | ForEach-Object { $_.Group } | Select-Object -Unique | ForEach-Object { Get-GroupId $_ }
    $hosts = Invoke-Zbx "host.get" @{ groupids = @($groupIds); selectMacros = "extend"; output = @("hostid", "host") }
    $n = 0
    foreach ($h in $hosts) {
        if ($h.macros | Where-Object { $_.macro -eq '{$SNMP_COMMUNITY}' }) { continue }
        Invoke-Zbx "usermacro.create" @{ hostid = $h.hostid; macro = '{$SNMP_COMMUNITY}'; value = $Community; type = 1 } | Out-Null
        $n++
    }
    Write-Host "Macro {`$SNMP_COMMUNITY} disetel di $n host."
}

if ($SyncMacros) { Set-HostMacros; return }

# 1. Macro global (fallback). Macro di template/host menimpa ini, makanya ada Set-HostMacros.
$gm = Invoke-Zbx "usermacro.get" @{ globalmacro = $true; filter = @{ macro = @('{$SNMP_COMMUNITY}') } }
if ($gm) { Invoke-Zbx "usermacro.updateglobal" @{ globalmacroid = $gm[0].globalmacroid; value = $Community } | Out-Null }
else     { Invoke-Zbx "usermacro.createglobal" @{ macro = '{$SNMP_COMMUNITY}'; value = $Community } | Out-Null }

# 2. Discovery rule per /24 (satu rule besar kena batas waktu fping 600s)
foreach ($subnet in $Subnets) {
    $name = "SNMP Discovery $subnet"
    if (Invoke-Zbx "drule.get" @{ filter = @{ name = @($name) } }) { Write-Host "Rule '$name' sudah ada, dilewati."; continue }
    Invoke-Zbx "drule.create" @{
        name = $name; iprange = $subnet; delay = $Delay
        dchecks = @(@{ type = 11; key_ = "1.3.6.1.2.1.1.1.0"; ports = "161"; snmp_community = '{$SNMP_COMMUNITY}'; uniq = 0 })
    } | Out-Null
    Write-Host "Rule '$name' dibuat."
}

# 3. Discovery action per merek
foreach ($t in $Types) {
    $actionName = "Discover $($t.Name)"
    if (Invoke-Zbx "action.get" @{ filter = @{ name = @($actionName); eventsource = 1 } }) { Write-Host "Action '$actionName' sudah ada, dilewati."; continue }

    $tpl = @()
    foreach ($tn in $t.Templates) {
        $found = Invoke-Zbx "template.get" @{ filter = @{ host = @($tn) } }
        if ($found) { $tpl += @{ templateid = $found[0].templateid } } else { Write-Warning "[$($t.Name)] template '$tn' tidak ditemukan, dilewati." }
    }
    if (-not $tpl) {
        $f = Invoke-Zbx "template.get" @{ filter = @{ host = @("Generic by SNMP") } }
        if (-not $f) { throw "Template 'Generic by SNMP' pun tidak ada." }
        $tpl = @(@{ templateid = $f[0].templateid })
    }

    # Jenis kondisi berbeda di-AND, jenis sama di-OR: (status Up) AND (service SNMPv2) AND (pola1 OR pola2 ...)
    $conds = @(
        @{ conditiontype = 10; operator = 0; value = "0" },    # discovery status = Up
        @{ conditiontype = 8;  operator = 0; value = "11" }    # service type = SNMPv2 agent
    )
    foreach ($p in $t.Patterns) { $conds += @{ conditiontype = 12; operator = 2; value = $p } }   # received value contains

    Invoke-Zbx "action.create" @{
        name = $actionName; eventsource = 1; status = 0
        filter = @{ evaltype = 0; conditions = $conds }
        operations = @(
            @{ operationtype = 2 },                                                                       # add host
            @{ operationtype = 4;  opgroup = @(@{ groupid = (Get-GroupId $t.Group) }) },                  # add to group
            @{ operationtype = 6;  optemplate = $tpl },                                                   # link templates
            @{ operationtype = 10; opinventory = @{ inventory_mode = 1 } }                                # inventory automatic
        )
    } | Out-Null
    Write-Host "Action '$actionName' dibuat (group $($t.Group))."
}

Set-HostMacros
Write-Host "Selesai. Nonaktifkan rule discovery lama yang scan range besar, lalu pantau Monitoring -> Discovery."

