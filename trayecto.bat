@echo off
rem Arranca Trayecto en Windows. Necesita Python 3 (python.org o Microsoft Store).
where py >nul 2>nul && (py -3 "%~dp0servidor.py" %* & exit /b)
where python >nul 2>nul && (python "%~dp0servidor.py" %* & exit /b)
echo Trayecto necesita Python 3: https://www.python.org/downloads/
echo Sin Python tambien funciona: abre web\index.html con doble clic.
pause
