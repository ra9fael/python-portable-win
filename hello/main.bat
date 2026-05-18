@echo off
TITLE Data Analyzer
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\run.ps1" -AppDir "%~dp0." -TargetScript "main.py"
