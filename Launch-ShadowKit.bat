@echo off
title ShadowKit Launcher
color 0B

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ========================================
    echo  ShadowKit requires Administrator rights
    echo ========================================
    echo Requesting elevation...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-ShadowKit.ps1"
pause
