# ============================================================
# IT Automation Toolkit - Data Backup Module
# Backs up user data to another drive using Robocopy
# ============================================================

$modulePath = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $modulePath "logger.ps1")

function Get-BackupSettings {
    <#
    .SYNOPSIS
        Returns backup settings from config.json with defaults.
    #>
    $cfg = Get-ToolkitConfig

    $defaultDest = ""
    $targetNames = @("Desktop", "Documents", "Downloads", "Pictures")

    if ($cfg -and $cfg.backup) {
        if ($cfg.backup.PSObject.Properties.Match("defaultDestination")) {
            $defaultDest = [string]$cfg.backup.defaultDestination
        }
        if ($cfg.backup.PSObject.Properties.Match("targets") -and $cfg.backup.targets) {
            $targetNames = @($cfg.backup.targets)
        }
    }

    return [pscustomobject]@{
        DefaultDestination = $defaultDest
        TargetNames        = $targetNames
    }
}

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

function Get-OneDrivePaths {
    $paths = @()
    foreach ($p in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path $p)) {
            $paths += $p
        }
    }
    return $paths | Select-Object -Unique
}

function Resolve-BackupTargetPath {
    param([string]$Name)

    $candidates = @()

    switch ($Name.ToLower()) {
        "desktop" {
            $candidates += "$env:USERPROFILE\Desktop"
            foreach ($p in (Get-OneDrivePaths)) { $candidates += (Join-Path $p "Desktop") }
        }
        "documents" {
            $candidates += "$env:USERPROFILE\Documents"
            foreach ($p in (Get-OneDrivePaths)) { $candidates += (Join-Path $p "Documents") }
        }
        "downloads" {
            $candidates += "$env:USERPROFILE\Downloads"
            foreach ($p in (Get-OneDrivePaths)) { $candidates += (Join-Path $p "Downloads") }
        }
        "pictures" {
            $candidates += "$env:USERPROFILE\Pictures"
            foreach ($p in (Get-OneDrivePaths)) { $candidates += (Join-Path $p "Pictures") }
        }
        default { return $null }
    }

    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    return $candidates[0]
}

function Get-BackupTargets {
    <#
    .SYNOPSIS
        Returns backup targets based on config.json with defaults.
    #>
    $settings = Get-BackupSettings
    $targets = @()

    foreach ($name in $settings.TargetNames) {
        $path = Resolve-BackupTargetPath -Name $name
        if ($path) {
            $targets += @{ Name = $name; Path = $path }
        }
    }

    if ($targets.Count -eq 0) {
        $targets = @(
            @{ Name = "Desktop";   Path = "$env:USERPROFILE\Desktop" }
            @{ Name = "Documents"; Path = "$env:USERPROFILE\Documents" }
            @{ Name = "Downloads"; Path = "$env:USERPROFILE\Downloads" }
            @{ Name = "Pictures";  Path = "$env:USERPROFILE\Pictures" }
        )
    }

    return $targets
}

function Get-AvailableDrives {
    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -and $_.Name -ne "C" }
}

function Select-BackupDestination {
    $settings = Get-BackupSettings
    $defaultDest = $settings.DefaultDestination

    Write-Host "  Available Destinations:" -ForegroundColor White
    Write-Host ""
    $drives = Get-AvailableDrives
    $i = 1
    foreach ($d in $drives) {
        $freeGB = [math]::Round($d.Free / 1GB, 2)
        Write-Host "    $i. Drive $($d.Name):\ - Free: $freeGB GB" -ForegroundColor Gray
        $i++
    }
    if (-not [string]::IsNullOrWhiteSpace($defaultDest)) {
        Write-Host "    D. Use default destination: $defaultDest" -ForegroundColor Yellow
    }
    Write-Host "    C. Enter custom path" -ForegroundColor Yellow
    Write-Host ""
    $choice = Read-Host "  Select destination"
    if ($choice.ToUpper() -eq "D" -and -not [string]::IsNullOrWhiteSpace($defaultDest)) {
        $p = $defaultDest
        if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
        return $p
    }
    if ($choice.ToUpper() -eq "C") {
        $p = Read-Host "  Enter full backup path"
        if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
        return $p
    }
    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx)) {
        $idx--; $arr = @($drives)
        if ($idx -ge 0 -and $idx -lt $arr.Count) {
            $dest = "$($arr[$idx].Name):\Backup"
            if (-not (Test-Path $dest)) { New-Item -Path $dest -ItemType Directory -Force | Out-Null }
            return $dest
        }
    }
    Write-Log "Invalid selection." -Level "WARN"; return $null
}

function Start-FolderBackup {
    param([string]$SourcePath, [string]$DestinationPath, [string]$FolderName)
    if (-not (Test-Path $SourcePath)) { Write-Log "Source not found: $SourcePath" -Level "WARN"; return $null }
    if (-not (Test-Path $DestinationPath)) { New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null }
    $sourceSize = Get-FolderSize -Path $SourcePath
    Write-Log "Backing up $FolderName..." -Level "INFO"
    Write-Log "  Source size: $(Format-FileSize $sourceSize)" -Level "INFO"
    try {
        $logDir = Get-LogDirectory
        $logFile = Join-Path $logDir "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$FolderName.log"
        $robocopyArgs = @("`"$SourcePath`"", "`"$DestinationPath`"", "/MIR", "/R:3", "/W:5", "/NP", "/NDL", "/LOG:`"$logFile`"")
        $proc = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -le 7) { Write-Log "$FolderName backup completed." -Level "SUCCESS"; return $true }
        else {
            Write-Log "$FolderName backup failed (exit $($proc.ExitCode))." -Level "ERROR"
            Write-Log "  Log file: $logFile" -Level "WARN"
            return $false
        }
    } catch { Write-Log "Error: $($_.Exception.Message)" -Level "ERROR"; return $false }
}

function Start-FullBackup {
    param([string]$Destination, [array]$Targets)
    Write-Banner "STARTING FULL BACKUP"
    $ok = 0; $fail = 0; $skipped = 0; $total = $Targets.Count
    for ($i = 0; $i -lt $total; $i++) {
        $t = $Targets[$i]
        Show-Progress -Activity "Data Backup" -Status "$($t.Name) ($($i+1)/$total)" -PercentComplete ([math]::Round(($i/$total)*100))
        $result = Start-FolderBackup -SourcePath $t.Path -DestinationPath (Join-Path $Destination $t.Name) -FolderName $t.Name
        if ($result -eq $true) { $ok++ }
        elseif ($result -eq $false) { $fail++ }
        else { $skipped++ }
    }
    Write-Progress -Activity "Data Backup" -Completed
    Write-Banner "BACKUP SUMMARY"
    Write-Log "Total: $total | OK: $ok | Failed: $fail | Skipped: $skipped" -Level $(if ($fail -eq 0) {"SUCCESS"} else {"WARN"})
}

function Show-BackupMenu {
    Write-Banner "DATA BACKUP"
    Write-Host "  Backup Targets:" -ForegroundColor White; Write-Host ""
    $targets = Get-BackupTargets
    for ($i = 0; $i -lt $targets.Count; $i++) {
        $t = $targets[$i]; $n = ($i+1).ToString().PadLeft(2)
        $ex = if (Test-Path $t.Path) {"[Found]"} else {"[Not Found]"}
        Write-Host "    $n. $($t.Name.PadRight(15)) $ex" -ForegroundColor Gray
    }
    Write-Host ""; Write-Host "     A. Backup ALL" -ForegroundColor Yellow
    Write-Host "     B. Back to main menu" -ForegroundColor DarkGray; Write-Host ""
}

function Start-BackupMenu {
    do {
        $targets = Get-BackupTargets
        Show-BackupMenu; $choice = Read-Host "  Select option"
        switch ($choice.ToUpper()) {
            "A" { $d = Select-BackupDestination; if ($d) { Start-FullBackup -Destination $d -Targets $targets }; Read-Host "`n  Press Enter to continue" }
            "B" { return }
            default {
                $idx = 0
                if ([int]::TryParse($choice, [ref]$idx)) {
                    $idx--
                    if ($idx -ge 0 -and $idx -lt $targets.Count) {
                        $t = $targets[$idx]; $d = Select-BackupDestination
                        if ($d) { Start-FolderBackup -SourcePath $t.Path -DestinationPath (Join-Path $d $t.Name) -FolderName $t.Name }
                        Read-Host "`n  Press Enter to continue"
                    } else { Write-Log "Invalid selection." -Level "WARN"; Start-Sleep 1 }
                } else { Write-Log "Invalid input." -Level "WARN"; Start-Sleep 1 }
            }
        }
    } while ($true)
}
