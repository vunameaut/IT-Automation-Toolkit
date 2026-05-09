@echo off
setlocal EnableExtensions
title IT Automation Toolkit
color 0B

echo.
echo  ============================================
echo   IT AUTOMATION TOOLKIT - Launcher
echo  ============================================
echo.

set "LOGDIR=%~dp0logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
set "LOG=%LOGDIR%\launcher.log"
echo ==== %DATE% %TIME% ====>> "%LOG%"
call :log "Launcher started."

set "ELEVATED=0"
if /I "%~1"=="--elevated" set "ELEVATED=1"

:: Check for Administrator privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    call :log "[!] Dang yeu cau quyen Administrator..."
    call :log "Neu khong thay UAC, hay chay start.bat bang Run as Administrator."
    echo.
    powershell -NoProfile -Command "Start-Process -FilePath 'cmd.exe' -ArgumentList '/k ""%~f0"" --elevated' -Verb RunAs"
    call :log "Da gui yeu cau UAC. Nhan phim bat ky de dong cua so nay."
    echo.
    pause
    exit /b
)

call :log "[OK] Dang chay voi quyen Administrator"
echo.

:: Check if PowerShell 7 is available
where pwsh >nul 2>&1
if %errorlevel% neq 0 (
    call :log "[!] Chua co PowerShell 7. Dang tu dong cai dat..."
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" -LogPath "%LOG%"
    if %errorlevel% neq 0 (
        call :log "[!] Tu dong cai dat PowerShell 7 that bai."
        echo.
        pause
        exit /b
    )
)

where pwsh >nul 2>&1
if %errorlevel% neq 0 (
    call :log "[!] Khong tim thay PowerShell 7 sau khi cai dat."
    call :log "Hay khoi dong lai may va thu lai."
    echo.
    pause
    exit /b
)

call :log "[OK] PowerShell 7 da san sang. Dang mo chuong trinh..."
echo.
pwsh -ExecutionPolicy Bypass -File "%~dp0main.ps1"

echo.
echo  Toolkit closed. Press any key to exit...
pause

exit /b

:log
set "MSG=%~1"
echo  %MSG%
echo  %MSG%>> "%LOG%"
exit /b
