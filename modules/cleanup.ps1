# ============================================================
# IT Automation Toolkit - System Cleanup Module
# Cleans unnecessary files to free disk space and improve performance
# ============================================================

# Import logger
$modulePath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $modulePath "logger.ps1")

function Get-FolderSize {
    <#
    .SYNOPSIS
        Calculates the total size of a folder in bytes.
    #>
    [CmdletBinding()]
    param([string]$Path)

    if (Test-Path $Path) {
        $size = (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [math]::Max($size, 0)
    }
    return 0
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Converts bytes to a human-readable string (KB / MB / GB).
    #>
    [CmdletBinding()]
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes Bytes"
}

function Get-CleanupOptions {
    <#
    .SYNOPSIS
        Returns cleanup settings from config.json with defaults.
    #>
    $cfg = Get-ToolkitConfig

    $opts = [pscustomobject]@{
        tempFiles          = $true
        recycleBin         = $true
        dnsCache           = $true
        windowsUpdateCache = $true
        browserCache       = $false
    }

    if ($cfg -and $cfg.cleanup) {
        if ($cfg.cleanup.PSObject.Properties.Match("tempFiles"))          { $opts.tempFiles = [bool]$cfg.cleanup.tempFiles }
        if ($cfg.cleanup.PSObject.Properties.Match("recycleBin"))         { $opts.recycleBin = [bool]$cfg.cleanup.recycleBin }
        if ($cfg.cleanup.PSObject.Properties.Match("dnsCache"))           { $opts.dnsCache = [bool]$cfg.cleanup.dnsCache }
        if ($cfg.cleanup.PSObject.Properties.Match("windowsUpdateCache")) { $opts.windowsUpdateCache = [bool]$cfg.cleanup.windowsUpdateCache }
        if ($cfg.cleanup.PSObject.Properties.Match("browserCache"))       { $opts.browserCache = [bool]$cfg.cleanup.browserCache }
    }

    return $opts
}

function Clear-TempFiles {
    <#
    .SYNOPSIS
        Deletes temporary files from user and system temp directories.
    #>
    Write-Log "Cleaning temporary files..." -Level "INFO"

    $paths = @(
        $env:TEMP,
        "C:\Windows\Temp"
    )

    $totalFreed = 0

    foreach ($path in $paths) {
        if (Test-Path $path) {
            $sizeBefore = Get-FolderSize -Path $path
            try {
                Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                $sizeAfter = Get-FolderSize -Path $path
                $freed = $sizeBefore - $sizeAfter
                $totalFreed += $freed
                Write-Log "  Cleaned: $path - freed $(Format-FileSize $freed)" -Level "SUCCESS"
            }
            catch {
                Write-Log "  Error cleaning $path : $($_.Exception.Message)" -Level "ERROR"
            }
        }
    }

    return $totalFreed
}

function Clear-RecycleBinItems {
    <#
    .SYNOPSIS
        Empties the Windows Recycle Bin.
    #>
    Write-Log "Emptying Recycle Bin..." -Level "INFO"
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Log "  Recycle Bin emptied." -Level "SUCCESS"
    }
    catch {
        Write-Log "  Could not clear Recycle Bin: $($_.Exception.Message)" -Level "WARN"
    }
}

function Clear-DnsCache {
    <#
    .SYNOPSIS
        Flushes the DNS resolver cache.
    #>
    Write-Log "Flushing DNS cache..." -Level "INFO"
    try {
        $result = ipconfig /flushdns 2>&1
        Write-Log "  DNS cache flushed successfully." -Level "SUCCESS"
    }
    catch {
        Write-Log "  Error flushing DNS: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Clear-WindowsUpdateCache {
    <#
    .SYNOPSIS
        Removes cached Windows Update files.
    #>
    Write-Log "Cleaning Windows Update cache..." -Level "INFO"

    $wuPath = "C:\Windows\SoftwareDistribution\Download"
    $freed  = 0

    if (Test-Path $wuPath) {
        $sizeBefore = Get-FolderSize -Path $wuPath
        try {
            # Stop Windows Update service first
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            Get-ChildItem -Path $wuPath -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            # Restart Windows Update service
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue

            $sizeAfter = Get-FolderSize -Path $wuPath
            $freed = $sizeBefore - $sizeAfter
            Write-Log "  Windows Update cache cleaned - freed $(Format-FileSize $freed)" -Level "SUCCESS"
        }
        catch {
            Write-Log "  Error cleaning WU cache: $($_.Exception.Message)" -Level "ERROR"
            # Make sure WU service is restarted
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Log "  Windows Update cache path not found." -Level "WARN"
    }

    return $freed
}

function Clear-BrowserCache {
    <#
    .SYNOPSIS
        Removes cached data for Chrome and Edge browsers.
    #>
    Write-Log "Cleaning browser caches..." -Level "INFO"

    $freed = 0

    # Chrome cache
    $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    if (Test-Path $chromePath) {
        $sizeBefore = Get-FolderSize -Path $chromePath
        Get-ChildItem -Path $chromePath -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $sizeAfter = Get-FolderSize -Path $chromePath
        $chromeFreed = $sizeBefore - $sizeAfter
        $freed += $chromeFreed
        Write-Log "  Chrome cache cleaned - freed $(Format-FileSize $chromeFreed)" -Level "SUCCESS"
    }

    # Edge cache
    $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    if (Test-Path $edgePath) {
        $sizeBefore = Get-FolderSize -Path $edgePath
        Get-ChildItem -Path $edgePath -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $sizeAfter = Get-FolderSize -Path $edgePath
        $edgeFreed = $sizeBefore - $sizeAfter
        $freed += $edgeFreed
        Write-Log "  Edge cache cleaned - freed $(Format-FileSize $edgeFreed)" -Level "SUCCESS"
    }

    return $freed
}

function Show-CleanupMenu {
    <#
    .SYNOPSIS
        Displays the cleanup sub-menu.
    #>
    $opts = Get-CleanupOptions

    Write-Banner "SYSTEM CLEANUP"

    Write-Host "  Cleanup Options:" -ForegroundColor White
    Write-Host ""
    $tempLabel = if ($opts.tempFiles) { "Delete Temporary Files" } else { "Delete Temporary Files (disabled)" }
    $binLabel  = if ($opts.recycleBin) { "Empty Recycle Bin" } else { "Empty Recycle Bin (disabled)" }
    $dnsLabel  = if ($opts.dnsCache) { "Flush DNS Cache" } else { "Flush DNS Cache (disabled)" }
    $wuLabel   = if ($opts.windowsUpdateCache) { "Clear Windows Update Cache" } else { "Clear Windows Update Cache (disabled)" }
    $brLabel   = if ($opts.browserCache) { "Clear Browser Cache (Chrome & Edge)" } else { "Clear Browser Cache (Chrome & Edge) (disabled)" }

    Write-Host "    1. $tempLabel" -ForegroundColor Gray
    Write-Host "    2. $binLabel" -ForegroundColor Gray
    Write-Host "    3. $dnsLabel" -ForegroundColor Gray
    Write-Host "    4. $wuLabel" -ForegroundColor Gray
    Write-Host "    5. $brLabel" -ForegroundColor Gray
    Write-Host ""
    Write-Host "     A. Run ALL Cleanup Tasks" -ForegroundColor Yellow
    Write-Host "     B. Back to main menu" -ForegroundColor DarkGray
    Write-Host ""
}

function Start-FullCleanup {
    <#
    .SYNOPSIS
        Runs all cleanup tasks sequentially and reports total freed space.
    #>
    $opts = Get-CleanupOptions
    $tasks = @()

    if ($opts.tempFiles)          { $tasks += @{ Name = "Temporary files";       Action = { Clear-TempFiles } } }
    if ($opts.recycleBin)         { $tasks += @{ Name = "Recycle Bin";           Action = { Clear-RecycleBinItems } } }
    if ($opts.dnsCache)           { $tasks += @{ Name = "DNS cache";             Action = { Clear-DnsCache } } }
    if ($opts.windowsUpdateCache) { $tasks += @{ Name = "Windows Update cache";  Action = { Clear-WindowsUpdateCache } } }
    if ($opts.browserCache)       { $tasks += @{ Name = "Browser cache";         Action = { Clear-BrowserCache } } }

    if ($tasks.Count -eq 0) {
        Write-Log "No cleanup tasks are enabled in config.json." -Level "WARN"
        return
    }

    Write-Banner "RUNNING FULL SYSTEM CLEANUP"

    $freeBefore = $null
    try { $freeBefore = (Get-PSDrive -Name C -ErrorAction Stop).Free } catch { $freeBefore = $null }

    $totalFreed = 0
    $steps = $tasks.Count

    for ($i = 0; $i -lt $steps; $i++) {
        $task = $tasks[$i]
        $pct = [math]::Round((($i / $steps) * 100))
        Show-Progress -Activity "System Cleanup" -Status "$($task.Name) ($($i+1)/$steps)" -PercentComplete $pct
        $result = & $task.Action
        if ($null -ne $result) { $totalFreed += [long]$result }
    }

    Write-Progress -Activity "System Cleanup" -Completed

    $freeAfter = $null
    try { $freeAfter = (Get-PSDrive -Name C -ErrorAction Stop).Free } catch { $freeAfter = $null }

    # Final report
    Write-Host ""
    Write-Banner "CLEANUP REPORT"
    if ($null -ne $freeBefore -and $null -ne $freeAfter) {
        Write-Log "Disk free before: $(Format-FileSize $freeBefore)" -Level "INFO"
        Write-Log "Disk free after:  $(Format-FileSize $freeAfter)" -Level "INFO"
    }
    Write-Log "Total disk space freed: $(Format-FileSize $totalFreed)" -Level "SUCCESS"
}

function Start-CleanupMenu {
    <#
    .SYNOPSIS
        Entry point - runs the cleanup interactive menu.
    #>
    do {
        $opts = Get-CleanupOptions
        Show-CleanupMenu
        $choice = Read-Host "  Select option"

        switch ($choice.ToUpper()) {
            "1" {
                if ($opts.tempFiles) { Clear-TempFiles } else { Write-Log "Temp file cleanup is disabled in config.json." -Level "WARN" }
                Read-Host "`n  Press Enter to continue"
            }
            "2" {
                if ($opts.recycleBin) { Clear-RecycleBinItems } else { Write-Log "Recycle Bin cleanup is disabled in config.json." -Level "WARN" }
                Read-Host "`n  Press Enter to continue"
            }
            "3" {
                if ($opts.dnsCache) { Clear-DnsCache } else { Write-Log "DNS cache cleanup is disabled in config.json." -Level "WARN" }
                Read-Host "`n  Press Enter to continue"
            }
            "4" {
                if ($opts.windowsUpdateCache) { Clear-WindowsUpdateCache } else { Write-Log "Windows Update cache cleanup is disabled in config.json." -Level "WARN" }
                Read-Host "`n  Press Enter to continue"
            }
            "5" {
                if ($opts.browserCache) { Clear-BrowserCache } else { Write-Log "Browser cache cleanup is disabled in config.json." -Level "WARN" }
                Read-Host "`n  Press Enter to continue"
            }
            "A" { Start-FullCleanup;          Read-Host "`n  Press Enter to continue" }
            "B" { return }
            default {
                Write-Log "Invalid selection. Please try again." -Level "WARN"
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}
