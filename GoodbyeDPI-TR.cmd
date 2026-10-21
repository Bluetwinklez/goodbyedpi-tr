@ECHO OFF
REM GoodbyeDPI-TR menusunu (veya verilen komutu) yonetici olarak calistirir.
SET "GDPI_PS1=%~dp0gdpi-tr.ps1"
SET "GDPI_ARGS=%*"
NET SESSION >NUL 2>&1
IF ERRORLEVEL 1 GOTO yukselt
powershell -NoProfile -ExecutionPolicy Bypass -File "%GDPI_PS1%" %*
PAUSE
EXIT /B

:yukselt
REM Yol ve argumanlar ortam degiskeninden okunur; tirnak ve kesme isareti sorun cikarmaz.
powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath powershell.exe -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File \"' + $env:GDPI_PS1 + '\" ' + $env:GDPI_ARGS)"
