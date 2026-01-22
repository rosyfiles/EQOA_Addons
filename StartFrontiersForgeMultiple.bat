@echo off
setlocal EnableExtensions EnableDelayedExpansion
title PCSX2 UiForge Injector

set "BASE=%~dp0"
cd /d "%BASE%"

set "UIFORGE=%BASE%bin\UiForge.exe"
set "PROC_NAME=pcsx2-qt"
set "PROC_EXE=pcsx2-qt.exe"
set "LISTFILE=%temp%\pcsx2_instances.txt"

if not exist "%UIFORGE%" (
  echo ERROR: UiForge not found at "%UIFORGE%"
  pause
  exit /b 1
)

del /q "%LISTFILE%" 2>nul

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p = Get-Process -Name '%PROC_NAME%' -ErrorAction SilentlyContinue |" ^
  "  Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -and $_.MainWindowTitle.Trim().Length -gt 0 } |" ^
  "  Sort-Object MainWindowTitle | Select-Object Id, MainWindowTitle;" ^
  "if(-not $p){ exit 10 }" ^
  "$lines=@(); $i=0; foreach($x in $p){ $i++; $lines += ('{0}|{1}|{2}' -f $i,$x.Id,$x.MainWindowTitle) }" ^
  "[System.IO.File]::WriteAllLines('%LISTFILE%', $lines); exit 0"

if errorlevel 10 (
  echo ERROR: No running %PROC_EXE% windows with titles found.
  pause
  exit /b 10
)

if not exist "%LISTFILE%" (
  echo ERROR: Could not create list file: "%LISTFILE%"
  pause
  exit /b 11
)

echo Select an instance:
echo.

for /f "usebackq tokens=1,2,* delims=|" %%A in ("%LISTFILE%") do (
  echo   %%A^) %%C
)

echo.
set /p CHOICE=Enter number:

set "TARGET_PID="
set "TARGET_TITLE="

for /f "usebackq tokens=1,2,* delims=|" %%A in ("%LISTFILE%") do (
  if "%%A"=="%CHOICE%" (
    set "TARGET_PID=%%B"
    set "TARGET_TITLE=%%C"
  )
)

del /q "%LISTFILE%" 2>nul

if not defined TARGET_PID (
  echo ERROR: Invalid selection.
  pause
  exit /b 4
)

echo.
echo Injecting into: %TARGET_TITLE%  (PID %TARGET_PID%)
echo.

"%UIFORGE%" -n %PROC_EXE% -p %TARGET_PID%

pause
endlocal
