param([switch]$Download)

$ErrorActionPreference = 'Stop'
if (-not $Download) {
    & (Join-Path $PSScriptRoot 'prepare-cuda132.ps1')
    & (Join-Path $PSScriptRoot 'prepare-msvc1450.ps1')
    'uv will sync the checked-in lockfile when -Download is explicitly passed.'
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
$WheelName = 'basicsr-1.4.2-py3-none-any.whl'
$WheelHash = '56b524d2ee49c0f0d3d5b97773df34ee73b4070a9bc6d86d89b6497f921e139e'
$Wheelhouse = Join-Path $PSScriptRoot '.wheelhouse'
$LocalWheel = Join-Path $Wheelhouse $WheelName
if (-not (Test-Path -LiteralPath $LocalWheel)) {
    $Cached = Get-ChildItem -Path "D:\.uv-cache\sdists-v*\pypi\basicsr\1.4.2\*\$WheelName" -File -ErrorAction SilentlyContinue |
        Where-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -eq $WheelHash } |
        Select-Object -First 1
    if (-not $Cached) { throw 'The verified BasicSR 1.4.2 universal wheel is missing from the local uv cache.' }
    New-Item -ItemType Directory -Path $Wheelhouse -Force | Out-Null
    Copy-Item -LiteralPath $Cached.FullName -Destination $LocalWheel
}
if ((Get-FileHash -LiteralPath $LocalWheel -Algorithm SHA256).Hash -ne $WheelHash) {
    throw 'The BasicSR wheel in .wheelhouse does not match the verified build.'
}

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
