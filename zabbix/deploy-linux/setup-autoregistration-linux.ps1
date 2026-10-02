# Membuat host group Linux-PC + autoregistration action untuk HostMetadata "linux" lewat Zabbix API.
# Jalankan sekali dari PC admin:  .\setup-autoregistration-linux.ps1 -Url http://192.168.0.182:8080 -Token <API token>
# Aman dijalankan ulang: kalau action sudah ada, dilewati.
param(
    [string]$Url = "http://localhost:8080",
    [Parameter(Mandatory)][string]$Token,
    [string]$TemplateName = "Linux by Zabbix agent active",
    [string]$GroupName = "Linux-PC"
)

$Api = "$Url/api_jsonrpc.php"
$Headers = @{ Authorization = "Bearer $Token" }
function Invoke-Zbx($method, $params) {
    $body = @{ jsonrpc = "2.0"; method = $method; params = $params; id = 1 } | ConvertTo-Json -Depth 10
    $r = Invoke-RestMethod -Uri $Api -Method Post -Body $body -ContentType "application/json-rpc" -Headers $Headers
    if ($r.error) { throw "$method gagal: $($r.error.data)" }
    $r.result
}

# 1. Host group
$g = Invoke-Zbx "hostgroup.get" @{ filter = @{ name = @($GroupName) } }
if ($g) { $groupId = $g[0].groupid } else { $groupId = (Invoke-Zbx "hostgroup.create" @{ name = $GroupName }).groupids[0] }

# 2. Template
$t = Invoke-Zbx "template.get" @{ filter = @{ host = @($TemplateName) } }
if (-not $t) { throw "Template '$TemplateName' tidak ditemukan" }
$templateId = $t[0].templateid

# 3. Autoregistration action: HostMetadata mengandung "linux"
$existing = Invoke-Zbx "action.get" @{ filter = @{ name = @("Autoregister Linux"); eventsource = 2 } }
if ($existing) { Write-Host "Action sudah ada, dilewati."; return }

Invoke-Zbx "action.create" @{
    name = "Autoregister Linux"
    eventsource = 2   # autoregistration
    status = 0
    filter = @{
        evaltype = 0
        conditions = @(@{ conditiontype = 24; operator = 2; value = "linux" })  # 24 = host metadata, 2 = contains
    }
    operations = @(
        @{ operationtype = 2 },                                                       # add host
        @{ operationtype = 4; opgroup = @(@{ groupid = $groupId }) },                 # add to group
        @{ operationtype = 6; optemplate = @(@{ templateid = $templateId }) },        # link template
        @{ operationtype = 10; opinventory = @{ inventory_mode = 1 } }                # set inventory mode: automatic
    )
} | Out-Null
Write-Host "Selesai. Group '$GroupName' + action 'Autoregister Linux' dibuat."
