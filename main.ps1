# ============================================================
#  IT AUTOMATION TOOLKIT - Main Entry Point
#  Centralized CLI menu for all automation modules
# ============================================================

#Requires -Version 7.0

# -- Script root ---------------------------------------------
$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

# -- Check Administrator ------------------------------------
function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host ""
    Write-Host "  [WARNING] This toolkit requires Administrator privileges." -ForegroundColor Yellow
    Write-Host "  Some features may not work without elevated permissions." -ForegroundColor Yellow
    Write-Host ""
    $continue = Read-Host "  Continue anyway? (Y/N)"
    if ($continue.ToUpper() -ne "Y") { exit }
}

# -- Check PowerShell Version -------------------------------
$psMajor = $PSVersionTable.PSVersion.Major
if ($psMajor -lt 7) {
    Write-Host ""
    Write-Host "  [ERROR] PowerShell 7+ is required to run this toolkit." -ForegroundColor Red
    Write-Host "  You are running PowerShell $psMajor." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  Press Enter to exit"
    exit
}

# -- Import Modules ------------------------------------------
$modulesPath = Join-Path $ScriptRoot "modules"

. (Join-Path $modulesPath "logger.ps1")
. (Join-Path $modulesPath "install.ps1")
. (Join-Path $modulesPath "cleanup.ps1")
. (Join-Path $modulesPath "backup.ps1")
. (Join-Path $modulesPath "optimize.ps1")

# -- ASCII Art Banner ----------------------------------------
function Show-MainBanner {
    Clear-Host
    $banner = @"
============================================================
    IT AUTOMATION TOOLKIT v1.0
    Windows System Administration
============================================================

"@
    Write-Host $banner -ForegroundColor Cyan
}

# -- Main Menu -----------------------------------------------
function Show-MainMenu {
    Write-Host "  +--------------------------------------+" -ForegroundColor DarkCyan
    Write-Host "  |              MAIN MENU               |" -ForegroundColor DarkCyan
    Write-Host "  +--------------------------------------+" -ForegroundColor DarkCyan
    Write-Host "  |                                      |" -ForegroundColor DarkCyan
    Write-Host "  |   1.  Install Software               |" -ForegroundColor White
    Write-Host "  |   2.  Cleanup System                 |" -ForegroundColor White
    Write-Host "  |   3.  Backup Data                    |" -ForegroundColor White
    Write-Host "  |   4.  Optimize System                |" -ForegroundColor White
    Write-Host "  |   5.  Exit                           |" -ForegroundColor DarkGray
    Write-Host "  |                                      |" -ForegroundColor DarkCyan
    Write-Host "  +--------------------------------------+" -ForegroundColor DarkCyan
    Write-Host ""
}

# -- Main Loop -----------------------------------------------
Write-Log "IT Automation Toolkit started." -Level "INFO" -NoConsole

do {
    Show-MainBanner
    Show-MainMenu

    $choice = Read-Host "  Select option"

    switch ($choice) {
        "1" { Start-InstallMenu }
        "2" { Start-CleanupMenu }
        "3" { Start-BackupMenu }
        "4" { Start-OptimizeMenu }
        "5" {
            Write-Host ""
            Write-Log "Exiting IT Automation Toolkit. Goodbye!" -Level "INFO"
            Write-Host ""
            exit
        }
        default {
            Write-Log "Invalid option. Please select 1-5." -Level "WARN"
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
