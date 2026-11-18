param(
    [ValidateSet('setup', 'doctor', 'models', 'generate', 'verify')]
    [string]$Action = 'doctor'
)

$ErrorActionPreference = 'Stop'
$Forwarded = @($args)
$TempPath = Join-Path $PSScriptRoot '.hunyuan-tmp'
$Variables = @{
    TEMP = $TempPath
    TMP = $TempPath
    UV_PROJECT_ENVIRONMENT = (Join-Path $PSScriptRoot '.venv')
    UV_HTTP_TIMEOUT = '90'
    UV_HTTP_RETRIES = '5'
    PYTHONUTF8 = '1'
}

if ($Action -eq 'models') {
    $Variables.HF_HUB_DOWNLOAD_TIMEOUT = '90'
    $Variables.HF_HUB_ETAG_TIMEOUT = '25'
    $Variables.HF_XET_HIGH_PERFORMANCE = '1'
}
$Previous = @{}
$Status = 1
Push-Location -LiteralPath $PSScriptRoot
try {
    New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
    foreach ($Name in $Variables.Keys) {
        $Previous[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
        [Environment]::SetEnvironmentVariable($Name, $Variables[$Name], 'Process')
    }
    if ($Action -eq 'setup') {
        & uv sync --locked --no-python-downloads
    } else {
        & uv run --locked --no-sync --no-python-downloads python -u hunyuan_cli.py $Action @Forwarded
    }
    $Status = $LASTEXITCODE
} finally {
    foreach ($Name in $Previous.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $Previous[$Name], 'Process')
    }
    Pop-Location
}
exit $Status
