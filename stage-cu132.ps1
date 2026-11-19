param([switch]$Download)

$ErrorActionPreference = 'Stop'
if (-not $Download) {
    & (Join-Path $PSScriptRoot 'prepare-cuda132.ps1')
    & (Join-Path $PSScriptRoot 'prepare-msvc1450.ps1')
    'uv will sync the checked-in lockfile when -Download is explicitly passed.'
    return
}

$TunAdapter = & (Join-Path $PSScriptRoot 'get-tun.ps1')

# CUDA uses explicitly bound curl connections. uv uses the system route.
foreach ($Name in 'pypi.org','files.pythonhosted.org','download.pytorch.org','download-r2.pytorch.org') {
    $Addresses = @(Resolve-DnsName -Name $Name -Type A -ErrorAction Stop |
        Where-Object IPAddress | Select-Object -ExpandProperty IPAddress)
    if (-not $Addresses.Count) { throw "No IPv4 address for $Name." }
    foreach ($Address in $Addresses) {
        $Route = @(Find-NetRoute -RemoteIPAddress $Address -ErrorAction Stop |
            Where-Object DestinationPrefix)
        if (-not $Route.Count -or @($Route | Where-Object InterfaceAlias -ne $TunAdapter.InterfaceAlias).Count) {
            throw "System route for $Name is not through the active sing-box TUN."
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
$Wheel = Join-Path $PSScriptRoot 'vendor\basicsr-1.4.2-py3-none-any.whl'
$WheelHash = '56b524d2ee49c0f0d3d5b97773df34ee73b4070a9bc6d86d89b6497f921e139e'
if ((Get-FileHash -LiteralPath $Wheel -Algorithm SHA256).Hash -ne $WheelHash) {
    throw 'The BasicSR wheel does not match the verified build.'
}
New-Item -ItemType Directory -Path $Environment.TEMP -Force | Out-Null

Push-Location -LiteralPath $PSScriptRoot
try {
    foreach ($Name in $Environment.Keys) {
        $Previous[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
        [Environment]::SetEnvironmentVariable($Name, $Environment[$Name], 'Process')
    }
    & uv sync --locked --no-python-downloads
    if ($LASTEXITCODE) { throw 'cu132 dependency sync failed.' }
    & .\prepare-cuda132.ps1 -Download
    & .\prepare-msvc1450.ps1 -Download
} finally {
    foreach ($Name in $Previous.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $Previous[$Name], 'Process')
    }
    Pop-Location
}
