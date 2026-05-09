# IT Automation Toolkit - Bootstrap installer
# Ensures PowerShell 7 is available by installing winget/App Installer or MSI fallback.

param(
    [string]$LogPath = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

function Write-Log {
    param([string]$Message)
    Write-Host $Message
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        Add-Content -Path $LogPath -Value $Message
    }
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Download-File {
    param(
        [string]$Uri,
        [string]$OutFile,
        [string]$Activity
    )

    $req = [System.Net.HttpWebRequest]::Create($Uri)
    $resp = $req.GetResponse()
    $len = $resp.ContentLength
    $stream = $resp.GetResponseStream()
    $fs = [System.IO.File]::Create($OutFile)
    $buf = New-Object byte[] 8192
    $total = 0

    try {
        while (($read = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $fs.Write($buf, 0, $read)
            $total += $read
            if ($len -gt 0) {
                $pct = [int](($total / $len) * 100)
                Write-Progress -Activity $Activity -Status ("{0} pct" -f $pct) -PercentComplete $pct
            }
        }
    }
    finally {
        $fs.Close()
        $stream.Close()
        $resp.Close()
        Write-Progress -Activity $Activity -Completed
    }
}

function Install-AppInstallerOffline {
    Write-Log "Dang tai va cai App Installer (offline)..."
    $dir = Join-Path $env:TEMP "winget-offline"
    New-Item -Path $dir -ItemType Directory -Force | Out-Null

    $files = @(
        @{ Uri = "https://aka.ms/getwinget"; Out = "AppInstaller.appxbundle"; Label = "Dang tai App Installer" },
        @{ Uri = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"; Out = "VCLibs_x64.appx"; Label = "Dang tai VCLibs x64" },
        @{ Uri = "https://aka.ms/Microsoft.VCLibs.x86.14.00.Desktop.appx"; Out = "VCLibs_x86.appx"; Label = "Dang tai VCLibs x86" },
        @{ Uri = "https://aka.ms/Microsoft.UI.Xaml.2.8.x64.appx"; Out = "UIXaml_x64.appx"; Label = "Dang tai UI.Xaml x64" },
        @{ Uri = "https://aka.ms/Microsoft.UI.Xaml.2.8.x86.appx"; Out = "UIXaml_x86.appx"; Label = "Dang tai UI.Xaml x86" }
    )

    foreach ($f in $files) {
        $outPath = Join-Path $dir $f.Out
        Download-File -Uri $f.Uri -OutFile $outPath -Activity $f.Label
    }

    Add-AppxPackage -Path (Join-Path $dir "VCLibs_x64.appx")
    Add-AppxPackage -Path (Join-Path $dir "VCLibs_x86.appx")
    Add-AppxPackage -Path (Join-Path $dir "UIXaml_x64.appx")
    Add-AppxPackage -Path (Join-Path $dir "UIXaml_x86.appx")
    Add-AppxPackage -Path (Join-Path $dir "AppInstaller.appxbundle")
}

function Install-PowerShellFromWinget {
    Write-Log "Dang cai PowerShell 7 bang winget..."
    winget install --id Microsoft.PowerShell -e --accept-package-agreements --accept-source-agreements --silent
}

function Install-PowerShellFromMsi {
    Write-Log "Dang tai PowerShell 7 (MSI)..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
    $asset = $release.assets | Where-Object { $_.name -match "win-x64.msi$" } | Select-Object -First 1
    if (-not $asset) {
        Write-Log "Khong tim thay file MSI tu GitHub."
        return $false
    }

    $msiPath = Join-Path $env:TEMP $asset.name
    Download-File -Uri $asset.browser_download_url -OutFile $msiPath -Activity "Dang tai PowerShell 7 MSI"

    Write-Log "Dang cai PowerShell 7 (MSI)..."
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList ("/i `"{0}`" /qn /norestart" -f $msiPath) -Wait -PassThru
    return $proc.ExitCode -eq 0
}

try {
    if (Test-Command -Name "pwsh") {
        Write-Log "PowerShell 7 da san sang."
        exit 0
    }

    if (Test-Command -Name "winget") {
        Install-PowerShellFromWinget
    }
    else {
        try {
            Install-AppInstallerOffline
        }
        catch {
            Write-Log "Cai App Installer that bai: $($_.Exception.Message)"
        }

        if (Test-Command -Name "winget") {
            Install-PowerShellFromWinget
        }
    }

    if (-not (Test-Command -Name "pwsh")) {
        $msiOk = Install-PowerShellFromMsi
        if (-not $msiOk) {
            Write-Log "Cai dat PowerShell 7 bang MSI that bai."
            exit 1
        }
    }

    if (Test-Command -Name "pwsh") {
        Write-Log "PowerShell 7 da san sang."
        exit 0
    }

    Write-Log "Khong tim thay PowerShell 7 sau khi cai dat."
    exit 1
}
catch {
    Write-Log "Loi: $($_.Exception.Message)"
    exit 1
}
