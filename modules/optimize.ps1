# ============================================================
# IT Automation Toolkit - System Optimization Module
# Basic Windows optimizations for better performance
# ============================================================

$modulePath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $modulePath "logger.ps1")

function Set-HighPerformancePower {
    Write-Log "Setting High Performance power plan..." -Level "INFO"
    try {
        $plans = powercfg /list 2>&1
        $highPerf = $plans | Select-String "High performance|Hieu suat cao"
        if ($highPerf) {
            $guid = ($highPerf -replace '.*GUID:\s*', '' -replace '\s*\(.*', '').Trim()
            powercfg /setactive $guid
            Write-Log "High Performance power plan activated." -Level "SUCCESS"
        } else {
            # Create high performance plan if not available
            powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
            Write-Log "High Performance power plan activated (default GUID)." -Level "SUCCESS"
        }
    } catch {
        Write-Log "Error setting power plan: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Disable-VisualEffects {
    Write-Log "Adjusting visual effects for best performance..." -Level "INFO"
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        Set-ItemProperty -Path $regPath -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
        # Disable animations
        $regPath2 = "HKCU:\Control Panel\Desktop"
        Set-ItemProperty -Path $regPath2 -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -ErrorAction SilentlyContinue
        Write-Log "Visual effects adjusted for performance." -Level "SUCCESS"
    } catch {
        Write-Log "Error adjusting visual effects: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Optimize-DriveStorage {
    Write-Log "Optimizing drives..." -Level "INFO"
    try {
        $drives = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
        foreach ($drive in $drives) {
            $letter = $drive.DriveLetter
            Write-Log "  Optimizing drive ${letter}:..." -Level "INFO"
            # Detect SSD vs HDD
            $diskNum = (Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue).DiskNumber
            if ($null -ne $diskNum) {
                $mediaType = (Get-PhysicalDisk | Where-Object { $_.DeviceID -eq $diskNum }).MediaType
                if ($mediaType -eq 'SSD') {
                    Optimize-Volume -DriveLetter $letter -ReTrim -ErrorAction SilentlyContinue
                    Write-Log "  Drive ${letter}: (SSD) - TRIM completed." -Level "SUCCESS"
                } else {
                    Optimize-Volume -DriveLetter $letter -Defrag -ErrorAction SilentlyContinue
                    Write-Log "  Drive ${letter}: (HDD) - Defragmentation completed." -Level "SUCCESS"
                }
            }
        }
    } catch {
        Write-Log "Error optimizing drives: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Disable-UnnecessaryStartup {
    Write-Log "Checking startup programs..." -Level "INFO"
    try {
        $startupItems = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
        if ($startupItems) {
            Write-Host ""
            Write-Host "  Current Startup Programs:" -ForegroundColor White
            Write-Host ""
            $i = 1
            foreach ($item in $startupItems) {
                Write-Host "    $i. $($item.Name) - $($item.Command)" -ForegroundColor Gray
                $i++
            }
            Write-Host ""
            Write-Log "Found $($startupItems.Count) startup items." -Level "INFO"

            $selection = Read-Host "  Enter numbers to disable (comma-separated) or press Enter to skip"
            if (-not [string]::IsNullOrWhiteSpace($selection)) {
                $indices = $selection -split '[, ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Sort-Object -Unique
                foreach ($idx in $indices) {
                    $pos = $idx - 1
                    if ($pos -ge 0 -and $pos -lt $startupItems.Count) {
                        Disable-StartupItem -Item $startupItems[$pos]
                    }
                    else {
                        Write-Log "Invalid startup item number: $idx" -Level "WARN"
                    }
                }
            }
        } else {
            Write-Log "No startup items found via WMI." -Level "INFO"
        }
    } catch {
        Write-Log "Error checking startup: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Disable-StartupItem {
    <#
    .SYNOPSIS
        Disables a startup item by removing its Run entry or Startup folder shortcut.
    #>
    param([object]$Item)

    $name = $Item.Name
    $location = $Item.Location
    $command = $Item.Command

    if ([string]::IsNullOrWhiteSpace($location)) {
        Write-Log "Cannot disable $name: unknown location." -Level "WARN"
        return
    }

    if ($location -match '^HKLM\\') {
        $regPath = $location -replace '^HKLM\\', 'HKLM:\\'
        try {
            Remove-ItemProperty -Path $regPath -Name $name -ErrorAction Stop
            Write-Log "Disabled startup item: $name (HKLM)" -Level "SUCCESS"
        } catch {
            Write-Log "Failed to disable $name in HKLM: $($_.Exception.Message)" -Level "WARN"
        }
        return
    }

    if ($location -match '^HKCU\\') {
        $regPath = $location -replace '^HKCU\\', 'HKCU:\\'
        try {
            Remove-ItemProperty -Path $regPath -Name $name -ErrorAction Stop
            Write-Log "Disabled startup item: $name (HKCU)" -Level "SUCCESS"
        } catch {
            Write-Log "Failed to disable $name in HKCU: $($_.Exception.Message)" -Level "WARN"
        }
        return
    }

    $startupFolders = @(
        [Environment]::GetFolderPath("Startup"),
        [Environment]::GetFolderPath("CommonStartup")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $cmdPath = $null
    if ($command -match '^"([^"]+)"') {
        $cmdPath = $matches[1]
    } else {
        $cmdPath = ($command -split '\s+')[0]
    }

    if ($cmdPath) {
        foreach ($folder in $startupFolders) {
            if ($cmdPath.StartsWith($folder, [System.StringComparison]::OrdinalIgnoreCase)) {
                try {
                    Remove-Item -Path $cmdPath -Force -ErrorAction Stop
                    Write-Log "Disabled startup item: $name (Startup folder)" -Level "SUCCESS"
                } catch {
                    Write-Log "Failed to remove startup shortcut for $name: $($_.Exception.Message)" -Level "WARN"
                }
                return
            }
        }
    }

    Write-Log "Cannot disable $name automatically. Location: $location" -Level "WARN"
}

function Get-OptionalServicesReport {
    <#
    .SYNOPSIS
        Reports the status of optional Windows services.
    #>
    Write-Banner "OPTIONAL SERVICES REPORT"

    $serviceList = @(
        @{ Name = "DiagTrack";     Display = "Connected User Experiences and Telemetry" },
        @{ Name = "SysMain";       Display = "SysMain (Superfetch)" },
        @{ Name = "MapsBroker";    Display = "Downloaded Maps Manager" },
        @{ Name = "WSearch";       Display = "Windows Search" },
        @{ Name = "Fax";           Display = "Fax" },
        @{ Name = "XblGameSave";   Display = "Xbox Live Game Save" },
        @{ Name = "WMPNetworkSvc"; Display = "Windows Media Player Network Sharing" }
    )

    foreach ($svc in $serviceList) {
        $info = Get-CimInstance Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue
        if ($info) {
            Write-Log "$($svc.Display) ($($svc.Name)) - Status: $($info.State), StartMode: $($info.StartMode)" -Level "INFO"
        } else {
            Write-Log "$($svc.Display) ($($svc.Name)) not found." -Level "WARN"
        }
    }
}

function Get-SystemHealthReport {
    Write-Banner "SYSTEM HEALTH REPORT"
    # OS Info
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host "  OS:          $($os.Caption) $($os.Version)" -ForegroundColor Cyan
    Write-Host "  Uptime:      $((Get-Date) - $os.LastBootUpTime | ForEach-Object { "$($_.Days)d $($_.Hours)h $($_.Minutes)m" })" -ForegroundColor Cyan
    # CPU
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Write-Host "  CPU:         $($cpu.Name)" -ForegroundColor Cyan
    # RAM
    $totalRAM = [math]::Round(($os.TotalVisibleMemorySize / 1MB), 2)
    $freeRAM  = [math]::Round(($os.FreePhysicalMemory / 1MB), 2)
    Write-Host "  RAM:         $freeRAM GB free / $totalRAM GB total" -ForegroundColor Cyan
    # Disk
    $disks = Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }
    foreach ($d in $disks) {
        $freeGB = [math]::Round($d.SizeRemaining / 1GB, 2)
        $totalGB = [math]::Round($d.Size / 1GB, 2)
        Write-Host "  Disk $($d.DriveLetter):      $freeGB GB free / $totalGB GB total" -ForegroundColor Cyan
    }
    Write-Host ""

    Get-OptionalServicesReport
}

function Show-OptimizeMenu {
    Write-Banner "SYSTEM OPTIMIZATION"
    Write-Host "  Optimization Options:" -ForegroundColor White
    Write-Host ""
    Write-Host "    1. Set High Performance Power Plan" -ForegroundColor Gray
    Write-Host "    2. Disable Unnecessary Visual Effects" -ForegroundColor Gray
    Write-Host "    3. Optimize Drives (Defrag/TRIM)" -ForegroundColor Gray
    Write-Host "    4. Review Startup Programs" -ForegroundColor Gray
    Write-Host "    5. System Health Report" -ForegroundColor Gray
    Write-Host ""
    Write-Host "     A. Run ALL Optimizations" -ForegroundColor Yellow
    Write-Host "     B. Back to main menu" -ForegroundColor DarkGray
    Write-Host ""
}

function Start-FullOptimize {
    Write-Banner "RUNNING FULL OPTIMIZATION"
    $steps = 5
    Show-Progress -Activity "System Optimization" -Status "Power Plan (1/$($steps))" -PercentComplete 0
    Set-HighPerformancePower
    Show-Progress -Activity "System Optimization" -Status "Visual Effects (2/$($steps))" -PercentComplete 20
    Disable-VisualEffects
    Show-Progress -Activity "System Optimization" -Status "Drive Optimization (3/$($steps))" -PercentComplete 40
    Optimize-DriveStorage
    Show-Progress -Activity "System Optimization" -Status "Startup Review (4/$($steps))" -PercentComplete 60
    Disable-UnnecessaryStartup
    Show-Progress -Activity "System Optimization" -Status "Optional Services (5/$($steps))" -PercentComplete 80
    Get-OptionalServicesReport
    Write-Progress -Activity "System Optimization" -Completed
    Write-Host ""
    Write-Log "System optimization completed!" -Level "SUCCESS"
}

function Start-OptimizeMenu {
    do {
        Show-OptimizeMenu; $choice = Read-Host "  Select option"
        switch ($choice.ToUpper()) {
            "1" { Set-HighPerformancePower; Read-Host "`n  Press Enter to continue" }
            "2" { Disable-VisualEffects; Read-Host "`n  Press Enter to continue" }
            "3" { Optimize-DriveStorage; Read-Host "`n  Press Enter to continue" }
            "4" { Disable-UnnecessaryStartup; Read-Host "`n  Press Enter to continue" }
            "5" { Get-SystemHealthReport; Read-Host "`n  Press Enter to continue" }
            "A" { Start-FullOptimize; Read-Host "`n  Press Enter to continue" }
            "B" { return }
            default { Write-Log "Invalid selection." -Level "WARN"; Start-Sleep 1 }
        }
    } while ($true)
}
