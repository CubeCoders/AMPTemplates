@echo off

rem Arguments: [number_clients] [server_binding] [server_port] "<server_password>" "<mod_list>"

set "clients="

rem Check if no headless clients are to be run
rem If none, immediately exit
if "%1" equ "0" exit /b 0

rem Start the headless clients
set /a "baseport=%3 + 498"
cd "%~dp0arma3\233780"
for /l %%i in (1,1,%1) do (
  if "%2" equ "0.0.0.0" (
    set "connect=127.0.0.1"
  ) else (
    set "connect=%2"
  )
  start /b "" "ArmA3Server_x64.exe" -client -nosound -connect="%connect%:%3" -port="%baseport%" -password="%4" "-mod=%5" >nul 2>&1
  set "clients=%clients% %ERRORLEVEL%"
)

rem Check if server starts successfully within 3 minutes
rem If not, terminate headless clients
set "server_started=false"
for /l %%i in (1,1,180) do (
  netstat -aon -p udp | findstr /c:":%3 " >nul 2>&1 && set "server_started=true" && goto :continue
  ping -n 1 127.0.0.1 >nul 2>&1
)
if not "%server_started%" equ "true" (
  for %%c in (%clients%) do taskkill /pid %%c /f >nul 2>&1
  exit /b 1
)

:continue
rem Monitor server process and terminate headless clients
rem when server terminates
:loop
netstat -aon -p udp | findstr /c:":%3 " >nul 2>&1 || (
  for %%c in (%clients%) do taskkill /pid %%c /f >nul 2>&1
  exit /b 0
)
ping -n 1 127.0.0.1 >nul 2>&1
goto :loop
