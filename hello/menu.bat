@echo off
TITLE Portable App Launcher
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\run.ps1" -AppDir "%~dp0."
