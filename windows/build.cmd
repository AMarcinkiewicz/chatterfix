@echo off
rem build.cmd - rebuilds ChatterFix.exe from source. No tools needed beyond Windows itself.
setlocal
cd /d "%~dp0"

set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
if not exist "%CSC%" (
    echo Could not find csc.exe - .NET Framework 4.x is required.
    exit /b 1
)

if not exist ChatterFix.ico (
    echo Generating icon...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0make-icon.ps1"
    if errorlevel 1 exit /b 1
)

rem Stop a running instance so the exe can be overwritten
taskkill /im ChatterFix.exe /f >nul 2>&1

"%CSC%" /nologo /target:winexe /optimize+ /out:ChatterFix.exe /win32icon:ChatterFix.ico /res:ChatterFix.ico,ChatterFix.ico ChatterFix.cs
if errorlevel 1 exit /b 1

echo Built ChatterFix.exe
