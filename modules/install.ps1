# ============================================================
# IT Automation Toolkit - Software Installation Module
# Automates installation of common Windows applications via Winget
# ============================================================

# Import logger
$modulePath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $modulePath "logger.ps1")

# -- Software catalog ---------------------------------------
$script:DefaultSoftwareCatalog = @(
    @{ Name = "Google Chrome";       Id = "Google.Chrome";                  Category = "Browser" }
    @{ Name = "Unikey";              Id = "DuongDieuPhap.UniKey";           Category = "Utility" }
    @{ Name = "Visual Studio Code";  Id = "Microsoft.VisualStudioCode";     Category = "Development" }
    @{ Name = "WinRAR";              Id = "RARLab.WinRAR";                  Category = "Utility" }
    @{ Name = "Discord";             Id = "Discord.Discord";                Category = "Communication" }
    @{ Name = "Microsoft Office";    Id = "Microsoft.Office";               Category = "Productivity" }
    @{ Name = "7-Zip";               Id = "7zip.7zip";                      Category = "Utility" }
    @{ Name = "Notepad++";           Id = "Notepad++.Notepad++";            Category = "Development" }
)

function Get-SoftwareCatalog {
    <#
    .SYNOPSIS
        Returns the software catalog from config.json or defaults.
    #>
    $cfg = Get-ToolkitConfig
    $items = @()

    if ($cfg -and $cfg.softwareList) {
        foreach ($item in $cfg.softwareList) {
            if ($null -eq $item) { continue }
            if ($item.PSObject.Properties.Match("enabled") -and $item.enabled -eq $false) { continue }

            $name = if ($item.name) { [string]$item.name } elseif ($item.Name) { [string]$item.Name } else { "" }
            $id = if ($item.id) { [string]$item.id } elseif ($item.Id) { [string]$item.Id } else { "" }
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($id)) { continue }

            $category = if ($item.category) { [string]$item.category } elseif ($item.Category) { [string]$item.Category } else { "General" }
            $items += @{ Name = $name; Id = $id; Category = $category }
        }
    }

    if ($items.Count -eq 0) { return $script:DefaultSoftwareCatalog }
    return $items
}

function Show-SoftwareMenu {
    <#
    .SYNOPSIS
        Displays the software installation sub-menu.
    #>
    param([array]$Catalog)

    Write-Banner "SOFTWARE INSTALLATION"

    Write-Host "  Available Software:" -ForegroundColor White
    Write-Host ""

    for ($i = 0; $i -lt $Catalog.Count; $i++) {
        $sw   = $Catalog[$i]
        $num  = ($i + 1).ToString().PadLeft(2)
        $name = $sw.Name.PadRight(25)
        $cat  = "[$($sw.Category)]"
        Write-Host "    $num. $name $cat" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "     A. Install ALL software" -ForegroundColor Yellow
    Write-Host "     B. Back to main menu" -ForegroundColor DarkGray
    Write-Host ""
}

function Install-SingleApp {
    <#
    .SYNOPSIS
        Installs a single application via winget with retry logic.
    .PARAMETER AppName
        Display name of the application.
    .PARAMETER AppId
        Winget package ID.
    .PARAMETER MaxRetries
        Maximum number of retry attempts. Default is 3.
    .OUTPUTS
        Boolean - $true if installation succeeded, $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppName,

        [Parameter(Mandatory)]
        [string]$AppId,

        [int]$MaxRetries = 3
    )

    Write-Log "Starting installation: $AppName ($AppId)" -Level "INFO"

    # Check if already installed
    $checkResult = winget list --id $AppId 2>&1
    if ($LASTEXITCODE -eq 0 -and $checkResult -match $AppId) {
        Write-Log "$AppName is already installed - skipping." -Level "WARN"
        return $true
    }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Write-Log "Attempt $attempt/$MaxRetries - Installing $AppName..." -Level "INFO"

            $installArgs = "install --id $AppId --silent --accept-package-agreements --accept-source-agreements"

            $process = Start-Process -FilePath "winget" -ArgumentList $installArgs `
                -Wait -PassThru -NoNewWindow

            if ($process.ExitCode -eq 0) {
                Write-Log "$AppName installed successfully!" -Level "SUCCESS"
                return $true
            }
            else {
                Write-Log "$AppName installation returned exit code $($process.ExitCode)" -Level "WARN"
            }
        }
        catch {
            Write-Log "Error installing $AppName : $($_.Exception.Message)" -Level "ERROR"
        }

        if ($attempt -lt $MaxRetries) {
            Write-Log "Retrying in 5 seconds..." -Level "WARN"
            Start-Sleep -Seconds 5
        }
    }

    Write-Log "FAILED to install $AppName after $MaxRetries attempts." -Level "ERROR"
    return $false
}

function Install-AllSoftware {
    <#
    .SYNOPSIS
        Installs every application in the catalog sequentially.
    #>
    param([array]$Catalog)

    if (-not $Catalog -or $Catalog.Count -eq 0) {
        Write-Log "No software entries available to install." -Level "WARN"
        return
    }

    Write-Banner "INSTALLING ALL SOFTWARE"

    $total     = $Catalog.Count
    $succeeded = 0
    $failed    = 0

    for ($i = 0; $i -lt $total; $i++) {
        $sw = $Catalog[$i]
        $pct = [math]::Round((($i / $total) * 100))
        Show-Progress -Activity "Installing Software" -Status "$($sw.Name) ($($i+1)/$total)" -PercentComplete $pct

        if (Install-SingleApp -AppName $sw.Name -AppId $sw.Id) {
            $succeeded++
        }
        else {
            $failed++
        }
    }

    Write-Progress -Activity "Installing Software" -Completed

    # Summary
    Write-Host ""
    Write-Banner "INSTALLATION SUMMARY"
    Write-Log "Total: $total | Succeeded: $succeeded | Failed: $failed" -Level $(if ($failed -eq 0) { "SUCCESS" } else { "WARN" })
}

function Start-InstallMenu {
    <#
    .SYNOPSIS
        Entry point - runs the software installation interactive menu.
    #>
    do {
        $catalog = Get-SoftwareCatalog
        Show-SoftwareMenu -Catalog $catalog
        $choice = Read-Host "  Select option"

        switch ($choice.ToUpper()) {
            "A" {
                Install-AllSoftware -Catalog $catalog
                Read-Host "`n  Press Enter to continue"
            }
            "B" { return }
            default {
                $index = 0
                if ([int]::TryParse($choice, [ref]$index)) {
                    $index-- # convert to 0-based
                    if ($index -ge 0 -and $index -lt $catalog.Count) {
                        $sw = $catalog[$index]
                        Install-SingleApp -AppName $sw.Name -AppId $sw.Id
                        Read-Host "`n  Press Enter to continue"
                    }
                    else {
                        Write-Log "Invalid selection. Please choose 1-$($catalog.Count), A, or B." -Level "WARN"
                        Start-Sleep -Seconds 1
                    }
                }
                else {
                    Write-Log "Invalid input. Please try again." -Level "WARN"
                    Start-Sleep -Seconds 1
                }
            }
        }
    } while ($true)
}
