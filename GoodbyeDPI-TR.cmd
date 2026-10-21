@ECHO OFF
REM GoodbyeDPI-TR menusunu yonetici olarak acar.
NET SESSION >NUL 2>&1
IF %ERRORLEVEL% NEQ 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    EXIT /B
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gdpi-tr.ps1" %*
PAUSE
