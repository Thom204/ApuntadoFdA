@echo off
rem Servidor de Apuntado en este PC (puerto 7777). Deja esta ventana abierta.
cd /d "%~dp0"
ApuntadoFdA.console.exe --headless res://app/server.tscn
pause
