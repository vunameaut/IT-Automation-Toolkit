# Build MSI installer using WiX Toolset

param(
    [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"

function Find-WixBin {
    $cmd = Get-Command candle.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return Split-Path -Parent $cmd.Source
    }

    $candidates = @(
        "${env:ProgramFiles(x86)}\WiX Toolset v3.11\bin",
        "${env:ProgramFiles(x86)}\WiX Toolset v3.14\bin",
        "${env:ProgramFiles}\WiX Toolset v3.11\bin",
        "${env:ProgramFiles}\WiX Toolset v3.14\bin"
    )

    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "candle.exe")) { return $c }
    }

    return $null
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$staging = Join-Path $scriptDir "staging"
$build = Join-Path $scriptDir "build"
$dist = Join-Path $projectRoot "dist"

$wixBin = Find-WixBin
if (-not $wixBin) {
    Write-Host "Khong tim thay WiX Toolset. Hay cai bang winget:"
    Write-Host "  winget install --id WiXToolset.WiXToolset -e"
    exit 1
}

$candle = Join-Path $wixBin "candle.exe"
$light = Join-Path $wixBin "light.exe"
$heat = Join-Path $wixBin "heat.exe"

if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
if (Test-Path $build) { Remove-Item $build -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging, $build, $dist | Out-Null

$exclude = @(
    ".git",
    "logs",
    "dist",
    "installer",
    "IT-Automation-Toolkit-v1.0.zip"
)

$items = Get-ChildItem -Path $projectRoot -Force | Where-Object { $exclude -notcontains $_.Name }
foreach ($item in $items) {
    Copy-Item -Path $item.FullName -Destination $staging -Recurse -Force
}

$harvest = Join-Path $build "Harvested.wxs"
& $heat @(
    "dir", $staging,
    "-cg", "HarvestedFiles",
    "-dr", "INSTALLFOLDER",
    "-gg",
    "-scom",
    "-sreg",
    "-srd",
    "-sfrag",
    "-var", "var.SourceDir",
    "-out", $harvest
)

$productWxs = Join-Path $scriptDir "Product.wxs"
& $candle @(
    "-dSourceDir=$staging",
    "-dProductVersion=$Version",
    "-out", (Join-Path $build "Product.wixobj"),
    $productWxs
)

& $candle @(
    "-dSourceDir=$staging",
    "-dProductVersion=$Version",
    "-out", (Join-Path $build "Harvested.wixobj"),
    $harvest
)

$msiPath = Join-Path $dist ("IT-Automation-Toolkit-" + $Version + ".msi")
if (Test-Path $msiPath) { Remove-Item $msiPath -Force }

& $light @(
    "-ext", "WixUIExtension",
    "-ext", "WixUtilExtension",
    "-out", $msiPath,
    (Join-Path $build "Product.wixobj"),
    (Join-Path $build "Harvested.wixobj")
)

Write-Host "Da tao MSI: $msiPath"
