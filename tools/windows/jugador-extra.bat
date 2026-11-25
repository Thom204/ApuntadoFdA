@echo off
rem Abre un cliente con su propia identidad, para simular otro jugador en este PC.
rem Mismo numero = mismo jugador (sirve para probar la reconexion).
cd /d "%~dp0"
set "N="
set /p "N=Numero de jugador (ej. 2, 3, 4): "
if "%N%"=="" (
  echo No escribiste un numero.
  pause
  exit /b 1
)
echo Abriendo el jugador %N%
start "Jugador %N%" "%~dp0ApuntadoFdA.exe" -- --perfil=%N%
