param([switch]$Download)
$ErrorActionPreference = 'Stop'
$Version = '13.2.1'
$Base = 'https://developer.download.nvidia.com/compute/cuda/redist'
$Parts = [ordered]@{
    cuda_nvcc   = @{ Path = 'cuda_nvcc/windows-x86_64/cuda_nvcc-windows-x86_64-13.2.78-archive.zip'; Bytes = 31257705 }
    cuda_cudart = @{ Path = 'cuda_cudart/windows-x86_64/cuda_cudart-windows-x86_64-13.2.75-archive.zip'; Bytes = 3094062 }
    cuda_cccl   = @{ Path = 'cuda_cccl/windows-x86_64/cuda_cccl-windows-x86_64-13.2.75-archive.zip'; Bytes = 3519616 }
    cuda_crt    = @{ Path = 'cuda_crt/windows-x86_64/cuda_crt-windows-x86_64-13.2.78-archive.zip'; Bytes = 139371 }
    libnvvm     = @{ Path = 'libnvvm/windows-x86_64/libnvvm-windows-x86_64-13.2.78-archive.zip'; Bytes = 55236155 }
}
$Cache = Join-Path $PSScriptRoot ".hunyuan-tmp\cuda-redist-$Version"
$Toolkit = Join-Path $PSScriptRoot ".cuda-$Version"
$Total = ($Parts.Values.Bytes | Measure-Object -Sum).Sum
$Parts.GetEnumerator() | ForEach-Object {
    [pscustomobject]@{ Component = $_.Key; Bytes = $_.Value.Bytes; URL = "$Base/$($_.Value.Path)" }
}
"Total: $Total bytes. Destination: $Toolkit"
if (-not $Download) { return }

$Tun = (Get-NetIPAddress -InterfaceAlias 'singbox_tun' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Select-Object -First 1).IPAddress
if (-not $Tun) { throw 'Start singbox_tun before downloading.' }
New-Item -ItemType Directory -Path $Cache, $Toolkit -Force | Out-Null
$ManifestPath = Join-Path $Cache 'redistrib.json'
& curl.exe --interface $Tun -fLsS --retry 4 --connect-timeout 25 --output $ManifestPath "$Base/redistrib_$Version.json"
if ($LASTEXITCODE) { throw 'Could not download the NVIDIA release manifest.' }
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

foreach ($Name in $Parts.Keys) {
    $Entry = $Manifest.$Name.'windows-x86_64'
    $Expected = $Parts[$Name]
    if ($Entry.relative_path -ne $Expected.Path -or [int64]$Entry.size -ne $Expected.Bytes -or
        $Entry.sha256 -notmatch '^[a-f0-9]{64}$') {
        throw "Unexpected release manifest entry for $Name."
    }
    $Zip = Join-Path $Cache ([IO.Path]::GetFileName($Expected.Path))
    if ((Test-Path -LiteralPath $Zip) -and (Get-Item -LiteralPath $Zip).Length -eq $Expected.Bytes -and
        (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash -eq $Entry.sha256) { continue }

    $Partial = "$Zip.part"
    if (-not (Test-Path -LiteralPath $Partial) -or (Get-Item -LiteralPath $Partial).Length -lt $Expected.Bytes) {
        & curl.exe --interface $Tun -fLsS --retry 8 --retry-all-errors --connect-timeout 25 --speed-limit 1024 --speed-time 45 --continue-at - --output $Partial "$Base/$($Expected.Path)"
        if ($LASTEXITCODE) { throw "Download interrupted for $Name. Resume with the same command." }
    }
    if ((Get-Item -LiteralPath $Partial).Length -ne $Expected.Bytes -or
        (Get-FileHash -LiteralPath $Partial -Algorithm SHA256).Hash -ne $Entry.sha256) {
        throw "Invalid size or SHA-256 for $Partial."
    }
    Move-Item -LiteralPath $Partial -Destination $Zip -Force
}

$Python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
$Archives = @($Parts.Values | ForEach-Object { Join-Path $Cache ([IO.Path]::GetFileName($_.Path)) })
@'
from pathlib import Path, PurePosixPath
from shutil import copyfileobj
import sys
from zipfile import ZipFile

toolkit = Path(sys.argv[1]).resolve()
for archive in sys.argv[2:]:
    with ZipFile(archive) as source:
        for member in source.infolist():
            parts = PurePosixPath(member.filename).parts
            if member.is_dir() or len(parts) < 3 or parts[1] not in {"bin", "include", "lib", "nvvm"}:
                continue
            target = (toolkit.joinpath(*parts[1:])).resolve()
            if not target.is_relative_to(toolkit):
                raise ValueError(f"Unsafe ZIP member: {member.filename}")
            target.parent.mkdir(parents=True, exist_ok=True)
            with source.open(member) as reader, target.open("wb") as writer:
                copyfileobj(reader, writer)
'@ | & $Python -B - $Toolkit @Archives
if ($LASTEXITCODE) { throw 'Toolkit extraction failed.' }
$Nvcc = Join-Path $Toolkit 'bin\nvcc.exe'
& $Nvcc --version
if ($LASTEXITCODE) { throw 'nvcc did not start.' }
