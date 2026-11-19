param([switch]$Download)

$ErrorActionPreference = 'Stop'
if (-not $Download) {
    & (Join-Path $PSScriptRoot 'prepare-cuda132.ps1')
    'Python dependencies will be resolved through uv when -Download is explicitly passed.'
    return
}

$Tun = (Get-NetIPAddress -InterfaceAlias 'singbox_tun' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Select-Object -First 1).IPAddress
if (-not $Tun) { throw 'Start singbox_tun before downloading.' }

# CUDA uses explicitly bound curl connections. uv uses the system route.
foreach ($Name in 'pypi.org','files.pythonhosted.org','download.pytorch.org','download-r2.pytorch.org') {
    $Addresses = @(Resolve-DnsName -Name $Name -Type A -ErrorAction Stop |
        Where-Object IPAddress | Select-Object -ExpandProperty IPAddress)
    if (-not $Addresses.Count) { throw "No IPv4 address for $Name." }
    foreach ($Address in $Addresses) {
        $Route = @(Find-NetRoute -RemoteIPAddress $Address -ErrorAction Stop |
            Where-Object DestinationPrefix)
        if (-not $Route.Count -or @($Route | Where-Object InterfaceAlias -ne 'singbox_tun').Count) {
            throw "System route for $Name is not through singbox_tun."
        }
    }
}

$Environment = @{
    TEMP = Join-Path $PSScriptRoot '.hunyuan-tmp'
    TMP = Join-Path $PSScriptRoot '.hunyuan-tmp'
    UV_CACHE_DIR = 'D:\.uv-cache'
    UV_PROJECT_ENVIRONMENT = Join-Path $PSScriptRoot '.venv'
    UV_HTTP_TIMEOUT = '90'
    UV_HTTP_RETRIES = '5'
}
$Previous = @{}
Push-Location -LiteralPath $PSScriptRoot
try {
    & .\prepare-cuda132.ps1 -Download
    foreach ($Name in $Environment.Keys) {
        $Previous[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
        [Environment]::SetEnvironmentVariable($Name, $Environment[$Name], 'Process')
    }
    & uv lock --no-python-downloads
    if ($LASTEXITCODE) { throw 'cu132 dependency resolution failed.' }
    & uv sync --locked --no-python-downloads
    if ($LASTEXITCODE) { throw 'cu132 dependency sync failed.' }
} finally {
    foreach ($Name in $Previous.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $Previous[$Name], 'Process')
    }
    Pop-Location
}
