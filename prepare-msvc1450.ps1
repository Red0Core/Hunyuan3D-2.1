param([switch]$Download)

$ErrorActionPreference = 'Stop'
$Version = '14.50.35717'
$Root = Join-Path $PSScriptRoot '.hunyuan-tmp\msvc-14.50'
$Tools = Join-Path $Root "VC\Tools\MSVC\$Version"
$VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$Instances = & $VsWhere -products Microsoft.VisualStudio.Product.Community -version '[18.0,19.0)' -latest -format json | ConvertFrom-Json
$Instance = $Instances | Select-Object -First 1
if (-not $Instance) { throw 'Visual Studio Community 2026 is required for its catalog and Windows SDK setup.' }
$VsAux = Join-Path $Instance.installationPath 'VC\Auxiliary'
if (-not (Test-Path -LiteralPath (Join-Path $VsAux 'Build\vcvarsall.bat'))) {
    throw 'Visual Studio is missing VC\Auxiliary\Build\vcvarsall.bat.'
}
$Aux = Join-Path $Root 'VC\Auxiliary'
if ((Test-Path -LiteralPath (Join-Path $Tools 'bin\Hostx64\x64\cl.exe')) -and
    (Test-Path -LiteralPath (Join-Path $Tools 'include\yvals_core.h')) -and
    (Test-Path -LiteralPath (Join-Path $Tools 'lib\x64\libcmt.lib')) -and
    (Test-Path -LiteralPath (Join-Path $Aux 'Build\vcvarsall.bat'))) {
    "Local MSVC $Version is ready at $Tools"
    return
}
if (-not $Download) {
    "MSVC $Version x64 compiler, headers and libraries: 83 284 392 bytes from the installed Microsoft catalog."
    return
}

$CatalogDir = Join-Path $env:ProgramData 'Microsoft\VisualStudio\Packages\_Instances'
$CatalogPath = Join-Path (Join-Path $CatalogDir $Instance.instanceId) 'catalog.json'
$Catalog = Get-Content -Raw -LiteralPath $CatalogPath | ConvertFrom-Json
$Packages = @($Catalog.packages | Where-Object {
    $_.id -match '^Microsoft\.VC\.14\.50\.18\.0\.(Tools\.HostX64\.TargetX64(\.Res)?|CRT\.(Headers|x64\.Desktop))\.base$' -and
    $_.language -in 'en-US',$null
})
if ($Packages.Count -ne 4) { throw 'The installed catalog is missing the four MSVC 14.50 x64 packages.' }
$Tun = (Get-NetIPAddress -InterfaceAlias singbox_tun -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Select-Object -First 1).IPAddress
if (-not $Tun) { throw 'Start singbox_tun before downloading MSVC.' }

New-Item -ItemType Directory -Force -Path $Tools | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Prefix = "Contents/VC/Tools/MSVC/$Version/"
$TargetRoot = [IO.Path]::GetFullPath($Tools).TrimEnd('\') + '\'
foreach ($Payload in $Packages.payloads) {
    $Uri = [uri]$Payload.url
    if ($Uri.Scheme -ne 'https' -or $Uri.Host -ne 'download.visualstudio.microsoft.com' -or
        [IO.Path]::GetFileName($Payload.fileName) -ne $Payload.fileName) {
        throw "Unexpected URL or file name for $($Payload.fileName)."
    }
    $File = Join-Path $Root $Payload.fileName
    if (-not (Test-Path -LiteralPath $File) -or (Get-Item -LiteralPath $File).Length -ne $Payload.size) {
        & curl.exe --interface $Tun --proto '=https' --fail --retry 2 --continue-at - --silent --show-error --output $File $Uri.AbsoluteUri
        if ($LASTEXITCODE) { throw "MSVC download failed for $($Payload.fileName)." }
    }
    if ((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Payload.sha256) {
        throw "SHA-256 mismatch for $File."
    }
    $Archive = [IO.Compression.ZipFile]::OpenRead($File)
    try {
        foreach ($Entry in $Archive.Entries) {
            $Name = [uri]::UnescapeDataString($Entry.FullName)
            if (-not $Entry.Name -or -not $Name.StartsWith($Prefix)) { continue }
            $Relative = $Name.Substring($Prefix.Length)
            if ($Relative -notmatch '^(bin|include|lib)/') { continue }
            $Target = [IO.Path]::GetFullPath((Join-Path $Tools $Relative))
            if (-not $Target.StartsWith($TargetRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "MSVC archive path escapes the local toolset: $Name"
            }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Target, $true)
        }
    } finally {
        $Archive.Dispose()
    }
}
# nvcc detects MSVC via this layout even when using the already configured SDK environment.
if (-not (Test-Path -LiteralPath $Aux)) {
    New-Item -ItemType Junction -Path $Aux -Target $VsAux | Out-Null
}
"Local MSVC $Version is ready at $Tools"
