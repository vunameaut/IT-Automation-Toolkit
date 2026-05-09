# ============================================================
# IT Automation Toolkit - Logger Module
# Provides centralized logging with timestamps and severity levels
# ============================================================

# Get the root directory of the toolkit (parent of modules/)
$script:ToolkitRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:LogDirectory = Join-Path $script:ToolkitRoot "logs"

function Get-ToolkitConfig {
    <#
    .SYNOPSIS
        Loads and returns the toolkit configuration from config.json.
    #>
    if ($global:ToolkitConfig) { return $global:ToolkitConfig }

    $configPath = Join-Path $script:ToolkitRoot "config.json"
    $cfg = $null

    if (Test-Path $configPath) {
        try {
            $raw = Get-Content -Path $configPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
            }
        }
        catch {
            $cfg = $null
        }
    }

    if (-not $cfg) { $cfg = [pscustomobject]@{} }

    if (-not $cfg.PSObject.Properties.Match("logging")) {
        $cfg | Add-Member -NotePropertyName "logging" -NotePropertyValue ([pscustomobject]@{})
    }
    if ($null -eq $cfg.logging) { $cfg.logging = [pscustomobject]@{} }

    if (-not $cfg.logging.PSObject.Properties.Match("enabled")) {
        $cfg.logging | Add-Member -NotePropertyName "enabled" -NotePropertyValue $true
    }
    if (-not $cfg.logging.PSObject.Properties.Match("logDirectory")) {
        $cfg.logging | Add-Member -NotePropertyName "logDirectory" -NotePropertyValue "logs"
    }
    if (-not $cfg.logging.PSObject.Properties.Match("logLevel")) {
        $cfg.logging | Add-Member -NotePropertyName "logLevel" -NotePropertyValue "INFO"
    }

    if (-not $cfg.PSObject.Properties.Match("backup")) {
        $cfg | Add-Member -NotePropertyName "backup" -NotePropertyValue ([pscustomobject]@{})
    }
    if ($null -eq $cfg.backup) { $cfg.backup = [pscustomobject]@{} }

    if (-not $cfg.backup.PSObject.Properties.Match("defaultDestination")) {
        $cfg.backup | Add-Member -NotePropertyName "defaultDestination" -NotePropertyValue ""
    }
    if (-not $cfg.backup.PSObject.Properties.Match("targets")) {
        $cfg.backup | Add-Member -NotePropertyName "targets" -NotePropertyValue @("Desktop", "Documents", "Downloads", "Pictures")
    }

    if (-not $cfg.PSObject.Properties.Match("cleanup")) {
        $cfg | Add-Member -NotePropertyName "cleanup" -NotePropertyValue ([pscustomobject]@{})
    }
    if ($null -eq $cfg.cleanup) { $cfg.cleanup = [pscustomobject]@{} }

    if (-not $cfg.cleanup.PSObject.Properties.Match("tempFiles")) {
        $cfg.cleanup | Add-Member -NotePropertyName "tempFiles" -NotePropertyValue $true
    }
    if (-not $cfg.cleanup.PSObject.Properties.Match("recycleBin")) {
        $cfg.cleanup | Add-Member -NotePropertyName "recycleBin" -NotePropertyValue $true
    }
    if (-not $cfg.cleanup.PSObject.Properties.Match("dnsCache")) {
        $cfg.cleanup | Add-Member -NotePropertyName "dnsCache" -NotePropertyValue $true
    }
    if (-not $cfg.cleanup.PSObject.Properties.Match("windowsUpdateCache")) {
        $cfg.cleanup | Add-Member -NotePropertyName "windowsUpdateCache" -NotePropertyValue $true
    }
    if (-not $cfg.cleanup.PSObject.Properties.Match("browserCache")) {
        $cfg.cleanup | Add-Member -NotePropertyName "browserCache" -NotePropertyValue $false
    }

    if (-not $cfg.PSObject.Properties.Match("softwareList")) {
        $cfg | Add-Member -NotePropertyName "softwareList" -NotePropertyValue @()
    }

    $global:ToolkitConfig = $cfg
    return $cfg
}

function Get-LogLevelValue {
    <#
    .SYNOPSIS
        Converts a log level string to a numeric value for comparison.
    #>
    param([string]$Level)

    $levelText = if ($null -eq $Level) { "" } else { $Level.ToString().ToUpperInvariant() }
    switch ($levelText) {
        "ERROR"   { return 3 }
        "WARN"    { return 2 }
        "INFO"    { return 1 }
        "SUCCESS" { return 1 }
        default   { return 1 }
    }
}

function Get-LogDirectory {
    <#
    .SYNOPSIS
        Returns the resolved log directory path based on config settings.
    #>
    $cfg = Get-ToolkitConfig
    $dir = $cfg.logging.logDirectory
    if ([string]::IsNullOrWhiteSpace($dir)) { $dir = "logs" }

    if ([System.IO.Path]::IsPathRooted($dir)) { return $dir }
    return Join-Path $script:ToolkitRoot $dir
}

function Initialize-Logger {
    <#
    .SYNOPSIS
        Initializes the logging system by creating the logs directory if needed.
    #>
    $script:LogDirectory = Get-LogDirectory
    if (-not (Test-Path $script:LogDirectory)) {
        New-Item -Path $script:LogDirectory -ItemType Directory -Force | Out-Null
    }
}

function Get-LogPath {
    <#
    .SYNOPSIS
        Returns the path to today's log file.
    .OUTPUTS
        String - Full path to the log file (e.g. logs/2026-05-09.log)
    #>
    Initialize-Logger
    $datestamp = Get-Date -Format "yyyy-MM-dd"
    return Join-Path $script:LogDirectory "$datestamp.log"
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a log entry with timestamp and severity level.
    .PARAMETER Message
        The message to log.
    .PARAMETER Level
        Severity level: INFO, WARN, ERROR, SUCCESS. Defaults to INFO.
    .PARAMETER NoConsole
        If set, suppresses console output (only writes to file).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",

        [switch]$NoConsole
    )

    $cfg = Get-ToolkitConfig
    $minLevelValue = Get-LogLevelValue -Level $cfg.logging.logLevel
    $currentLevelValue = Get-LogLevelValue -Level $Level

    if ($currentLevelValue -lt $minLevelValue) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "[$timestamp] [$Level] $Message"

    if ($cfg.logging.enabled -ne $false) {
        $logPath = Get-LogPath
        Add-Content -Path $logPath -Value $logEntry -Encoding UTF8
    }

    if (-not $NoConsole) {
        switch ($Level) {
            "INFO"    { Write-Host $logEntry -ForegroundColor Cyan }
            "WARN"    { Write-Host $logEntry -ForegroundColor Yellow }
            "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
            "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        }
    }
}

function Write-Banner {
    <#
    .SYNOPSIS
        Displays a styled section banner in the console.
    .PARAMETER Title
        The title text to display inside the banner.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor White
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host ""
}

function Show-Progress {
    <#
    .SYNOPSIS
        Displays a custom progress bar in the console.
    .PARAMETER Activity
        Description of the current activity.
    .PARAMETER Status
        Current status text.
    .PARAMETER PercentComplete
        Completion percentage (0-100).
    #>
    [CmdletBinding()]
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete
    )

    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
}

# Initialize logger on module load
Initialize-Logger
