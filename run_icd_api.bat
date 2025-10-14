@echo off
setlocal enabledelayedexpansion

REM ============================================
REM CONFIGURATION
REM ============================================
set "APP_NAME=whoicd_icd_api"
set "IMAGE=whoicd/icd-api"
set "HOST_PORT=8090"
set "CONTAINER_PORT=80"
set "PORT_MAPPING=%HOST_PORT%:%CONTAINER_PORT%"
set "ENV_VARS=-e include=2024-01_fr-en -e enableDoris=true -e acceptLicense=true -e saveAnalytics=true"
set "TASK_NAME=Start ICD API Container"
set "INSTALL_DIR=%ProgramFiles%\RedHat\Podman"
set "PODMAN_EXE=%INSTALL_DIR%\podman.exe"
set "LOGFILE=%~dp0podman_install.log"

REM ============================================
REM STEP 1: Check for Podman installation
REM ============================================
if not exist "%PODMAN_EXE%" (
    echo Podman not found. Installing Podman...
    echo.
    echo Checking for Winget...
    winget --version >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        echo Installing via Winget...
        winget install -e --id RedHat.Podman -h
    ) else (
        echo Winget not found, downloading installer...
        powershell -Command ^
        "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/containers/podman/releases/latest/download/podman-installer.exe' -OutFile 'podman-installer.exe'" ^
        >> "%LOGFILE%" 2>&1

        if not exist podman-installer.exe (
            echo ERROR: Failed to download Podman installer. Check your internet connection or the log file: %LOGFILE%
            pause
            exit /b 1
        )

        echo Running Podman installer...
        start /wait podman-installer.exe /SILENT
        del podman-installer.exe
    )
) else (
    echo Podman already installed.
)

REM Add Podman to PATH for current session
set "PATH=%PATH%;%INSTALL_DIR%"

REM Verify installation
where podman >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Podman not found even after installation. Check %LOGFILE%.
    pause
    exit /b 1
)

REM ============================================
REM STEP 2: Initialize Podman machine (if needed)
REM ============================================
podman machine inspect >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Initializing Podman machine...
    podman machine init --now
) else (
    echo Starting Podman machine...
    podman machine start
)

REM ============================================
REM STEP 3: Check if container exists
REM ============================================
for /f "tokens=*" %%i in ('podman ps -a --format "{{.Names}}"') do (
    if /I "%%i"=="%APP_NAME%" (
        set "CONTAINER_EXISTS=1"
    )
)

if defined CONTAINER_EXISTS (
    echo Container "%APP_NAME%" already exists.
    echo Starting container if not already running...
    podman start %APP_NAME% >nul 2>&1
) else (
    echo Creating and running new container...
    podman run -d --name %APP_NAME% -p %PORT_MAPPING% %ENV_VARS% %IMAGE%
)

REM ============================================
REM STEP 4: Add startup task to run at boot
REM ============================================
echo Checking for startup task...
schtasks /query /tn "%TASK_NAME%" >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Creating scheduled task to auto-start container on boot...
    schtasks /create /tn "%TASK_NAME%" ^
        /tr "\"%~f0\"" ^
        /sc onstart /ru SYSTEM /rl HIGHEST ^
        /f
    echo Task created: %TASK_NAME%
) else (
    echo Scheduled task already exists.
)

REM ============================================
REM STEP 5: Confirm status
REM ============================================
echo.
echo Checking container status...
podman ps
echo.
echo ✅ ICD API container should now be running.
echo Access it via: http://localhost:%HOST_PORT%
echo.
pause
endlocal
