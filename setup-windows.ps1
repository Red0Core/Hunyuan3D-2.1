param(
    [switch]$Offline,
    [string]$TunnelInterface
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Scratch = Join-Path $Root '.hunyuan-tmp'
$Venv = Join-Path $Root '.venv'
$Toolkit = Join-Path $Root '.cuda-13.2.2'
$MsvcRoot = Join-Path $Scratch 'msvc-14.50'
$Msvc = Join-Path $MsvcRoot 'VC\Tools\MSVC\14.50.35717'

function Receive-File([string]$Url, [string]$Path, [switch]$Resume) {
    if ($Offline) { throw "Offline setup needs the cached file $Path." }
    $Options = @('--proto', '=https', '--proto-redir', '=https', '--location', '--fail', '--silent',
        '--show-error', '--retry', '4', '--connect-timeout', '25', '--output', $Path)
    if ($Adapter) { $Options += @('--interface', $Adapter.IPAddress) }
    if ($Resume) { $Options += @('--continue-at', '-') }
    & curl.exe @Options $Url
    if ($LASTEXITCODE) { throw "Download interrupted for $Url. Run setup again to resume." }
}

function Test-Archive([string]$Path, [long]$Bytes, [string]$Sha256) {
    (Test-Path -LiteralPath $Path -PathType Leaf) -and
        ($Bytes -eq 0 -or (Get-Item -LiteralPath $Path).Length -eq $Bytes) -and
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Sha256
}

function Get-VerifiedArchive([string]$Url, [string]$Path, [long]$Bytes, [string]$Sha256) {
    if ($Sha256 -notmatch '^[a-f0-9]{64}$') { throw "Missing SHA-256 for $Url." }
    if (Test-Archive $Path $Bytes $Sha256) { return }
    $Partial = "$Path.part"
    if (-not (Test-Archive $Partial $Bytes $Sha256)) {
        Receive-File $Url $Partial -Resume
    }
    if (-not (Test-Archive $Partial $Bytes $Sha256)) {
        throw "Size or SHA-256 mismatch for $Partial."
    }
    Move-Item -LiteralPath $Partial -Destination $Path -Force
}

function Expand-ToolArchive([string]$Archive, [string]$Destination, [string]$EntryPattern) {
    $TargetRoot = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $Zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($Entry in $Zip.Entries) {
            $Name = [uri]::UnescapeDataString($Entry.FullName)
            if (-not $Entry.Name -or $Name.EndsWith('/') -or $Name -notmatch $EntryPattern) { continue }
            $Target = [IO.Path]::GetFullPath((Join-Path $Destination $Matches[1]))
            if (-not $Target.StartsWith($TargetRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Archive entry escapes the tool directory: $Name"
            }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Target, $true)
        }
    } finally {
        $Zip.Dispose()
    }
}

function Initialize-Cuda {
    $Nvcc = Join-Path $Toolkit 'bin\nvcc.exe'
    if ((Test-Path -LiteralPath $Nvcc) -and
        (Test-Path -LiteralPath (Join-Path $Toolkit 'bin\cudafe++.exe')) -and
        (Test-Path -LiteralPath (Join-Path $Toolkit 'include\cuda_runtime.h')) -and
        (Test-Path -LiteralPath (Join-Path $Toolkit 'include\cccl\cub\cub.cuh')) -and
        (Test-Path -LiteralPath (Join-Path $Toolkit 'lib\x64\cudart.lib')) -and
        (Test-Path -LiteralPath (Join-Path $Toolkit 'nvvm\bin\cicc.exe'))) { return }

    $Base = 'https://developer.download.nvidia.com/compute/cuda/redist'
    $Cache = Join-Path $Scratch 'cuda-redist-13.2.2'
    $ManifestPath = Join-Path $Cache 'redistrib.json'
    $Parts = [ordered]@{
        cuda_nvcc = 31078504
        cuda_cudart = 3094421
        cuda_cccl = 3519613
        cuda_crt = 139368
        libnvvm = 55237784
    }
    New-Item -ItemType Directory -Path $Cache,$Toolkit -Force | Out-Null
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        Receive-File "$Base/redistrib_13.2.2.json" "$ManifestPath.part"
        Move-Item -LiteralPath "$ManifestPath.part" -Destination $ManifestPath -Force
    }
    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    foreach ($Name in $Parts.Keys) {
        $Entry = $Manifest.$Name.'windows-x86_64'
        $FileName = "$Name-windows-x86_64-13.2.86-archive.zip"
        $RelativePath = "$Name/windows-x86_64/$FileName"
        if ($Entry.relative_path -ne $RelativePath -or [long]$Entry.size -ne $Parts[$Name]) {
            throw "Unexpected CUDA manifest entry for $Name."
        }
        $Archive = Join-Path $Cache $FileName
        Get-VerifiedArchive "$Base/$RelativePath" $Archive $Parts[$Name] $Entry.sha256
        Expand-ToolArchive $Archive $Toolkit '^[^/]+/((?:bin|include|lib|nvvm)/.+)$'
    }
    if (-not (Test-Path -LiteralPath $Nvcc)) { throw 'The CUDA archives did not install nvcc.' }
}

function Initialize-Msvc($VisualStudio) {
    $VsAux = Join-Path $VisualStudio.installationPath 'VC\Auxiliary'
    if (-not (Test-Path -LiteralPath (Join-Path $VsAux 'Build\vcvars64.bat'))) {
        throw 'Install the C++ workload in Visual Studio Community 2026.'
    }
    $Aux = Join-Path $MsvcRoot 'VC\Auxiliary'
    if (-not ((Test-Path -LiteralPath (Join-Path $Msvc 'bin\Hostx64\x64\cl.exe')) -and
              (Test-Path -LiteralPath (Join-Path $Msvc 'include\yvals_core.h')) -and
              (Test-Path -LiteralPath (Join-Path $Msvc 'lib\x64\libcmt.lib')))) {
        $InstallerCatalog = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages\_Instances\$($VisualStudio.instanceId)\catalog.json"
        $Catalog = Get-Content -LiteralPath $InstallerCatalog -Raw | ConvertFrom-Json
        $Packages = @($Catalog.packages | Where-Object {
            $_.id -match '^Microsoft\.VC\.14\.50\.18\.0\.(Tools\.HostX64\.TargetX64(\.Res)?|CRT\.(Headers|x64\.Desktop))\.base$' -and
            $_.language -in 'en-US',$null
        })
        if ($Packages.Count -ne 4) { throw 'The Visual Studio catalog is missing the four MSVC 14.50 x64 packages.' }
        New-Item -ItemType Directory -Path $Msvc -Force | Out-Null
        foreach ($Payload in $Packages.payloads) {
            $Uri = [uri]$Payload.url
            if ($Uri.Scheme -ne 'https' -or $Uri.Host -ne 'download.visualstudio.microsoft.com' -or
                [IO.Path]::GetFileName($Payload.fileName) -ne $Payload.fileName) {
                throw "Unexpected Visual Studio payload for $($Payload.fileName)."
            }
            $Archive = Join-Path $MsvcRoot $Payload.fileName
            # The installer size can be an estimate. The manifest's SHA-256 identifies the VSIX.
            Get-VerifiedArchive -Url $Uri.AbsoluteUri -Path $Archive -Sha256 $Payload.sha256
            Expand-ToolArchive $Archive $Msvc '^Contents/VC/Tools/MSVC/14\.50\.35717/((?:bin|include|lib)/.+)$'
        }
    }
    # nvcc looks for vcvarsall.bat relative to cl.exe even with --use-local-env.
    if (-not (Test-Path -LiteralPath $Aux)) {
        New-Item -ItemType Junction -Path $Aux -Target $VsAux | Out-Null
    }
}

function Build-NativeExtensions {
    # Use a child process to activate Visual Studio without changing the caller's environment.
    $Build = Join-Path $Scratch ("native-build-" + [guid]::NewGuid().ToString('N') + '.cmd')
    @'
@echo off
setlocal
pushd "%~dp0.."
set "PROJECT=%CD%"
set "CUDA_HOME=%PROJECT%\.cuda-13.2.2"
set "CUDA_PATH=%CUDA_HOME%"
set "PYTHON=%PROJECT%\.venv\Scripts\python.exe"
set "MSVC=%PROJECT%\.hunyuan-tmp\msvc-14.50\VC\Tools\MSVC\14.50.35717"
call "%HUNYUAN_VS_ROOT%\VC\Auxiliary\Build\vcvars64.bat" || goto :error
set "VCToolsInstallDir=%MSVC%\"
set "VCToolsVersion=14.50.35717"
set "NVCC_PREPEND_FLAGS=--use-local-env"
set "PATH=%MSVC%\bin\Hostx64\x64;%CUDA_HOME%\bin;%CUDA_HOME%\bin\x64;%HUNYUAN_VS_ROOT%\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%"
set "INCLUDE=%MSVC%\include;%CUDA_HOME%\include\cccl;%INCLUDE%"
set "LIB=%MSVC%\lib\x64;%CUDA_HOME%\lib\x64;%CUDA_HOME%\lib;%LIB%"
set "DISTUTILS_USE_SDK=1"
if not defined TORCH_CUDA_ARCH_LIST set "TORCH_CUDA_ARCH_LIST=12.0"
if not defined MAX_JOBS set "MAX_JOBS=2"
"%PYTHON%" -c "import sys,torch; assert sys.version_info[:2]==(3,13) and torch.version.cuda=='13.2', (sys.version,torch.version.cuda)" || goto :error
cd /d "%PROJECT%\hy3dpaint\custom_rasterizer"
"%PYTHON%" setup.py build_ext --inplace || goto :error
cd /d "%PROJECT%\hy3dpaint\DifferentiableRenderer"
"%PYTHON%" setup.py build_ext --inplace || goto :error
cd /d "%PROJECT%"
"%PYTHON%" -B hunyuan_cli.py doctor || goto :error
popd
exit /b 0
:error
popd
exit /b 1
'@ | Set-Content -LiteralPath $Build -Encoding ASCII
    try {
        & $env:ComSpec /d /c $Build
        if ($LASTEXITCODE) { throw 'Native build or doctor failed.' }
    } finally {
        Remove-Item -LiteralPath $Build
    }
}

$Adapter = $null
if ($TunnelInterface) {
    $Adapter = Get-NetIPAddress -InterfaceAlias $TunnelInterface -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object AddressState -eq 'Preferred' | Select-Object -First 1
    if (-not $Adapter) { throw "No active IPv4 address on $TunnelInterface." }
}
if ($Adapter -and -not $Offline) {
    foreach ($Name in 'pypi.org','files.pythonhosted.org','download.pytorch.org','download-r2.pytorch.org') {
        $Addresses = @(Resolve-DnsName -Name $Name -ErrorAction Stop | Where-Object IPAddress)
        if (-not $Addresses.Count) { throw "Could not check the route to $Name." }
        foreach ($Address in $Addresses.IPAddress) {
            $Routes = @(Find-NetRoute -RemoteIPAddress $Address -ErrorAction Stop | Where-Object DestinationPrefix)
            if (-not $Routes.Count -or @($Routes | Where-Object InterfaceAlias -ne $Adapter.InterfaceAlias).Count) {
                throw "$Name is not routed through $TunnelInterface."
            }
        }
    }
}

$VsWhere = Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $VsWhere)) { throw 'Visual Studio Community 2026 with its C++ workload is required.' }
$VisualStudio = & $VsWhere -products Microsoft.VisualStudio.Product.Community -version '[18.0,19.0)' -latest -format json |
    ConvertFrom-Json | Select-Object -First 1
if (-not $VisualStudio) { throw 'Visual Studio Community 2026 was not found.' }
$Wheel = Join-Path $Root 'vendor\basicsr-1.4.2-py3-none-any.whl'
if (-not (Test-Archive $Wheel 214936 '56b524d2ee49c0f0d3d5b97773df34ee73b4070a9bc6d86d89b6497f921e139e')) {
    throw 'The bundled BasicSR wheel does not match the verified build.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Path $Scratch -Force | Out-Null
$Settings = @{
    TEMP = $Scratch
    TMP = $Scratch
    UV_PROJECT_ENVIRONMENT = $Venv
    HUNYUAN_VS_ROOT = $VisualStudio.installationPath
}
$Previous = @{}
Push-Location -LiteralPath $Root
try {
    foreach ($Name in $Settings.Keys) {
        $Previous[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
        [Environment]::SetEnvironmentVariable($Name, $Settings[$Name], 'Process')
    }
    $UvArgs = @('sync', '--locked', '--no-python-downloads')
    if ($Offline) { $UvArgs += '--offline' }
    & uv @UvArgs
    if ($LASTEXITCODE) { throw 'uv sync failed.' }
    Initialize-Cuda
    Initialize-Msvc $VisualStudio
    Build-NativeExtensions
} finally {
    foreach ($Name in $Previous.Keys) {
        [Environment]::SetEnvironmentVariable($Name, $Previous[$Name], 'Process')
    }
    Pop-Location
}
