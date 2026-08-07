# setup_runner.ps1
# Register this machine as a GitHub self-hosted runner for personal-workbench
# and configure it to start automatically on login (foreground mode).
#
# Why foreground? The "install as Windows service" approach requires the
# account to have "Log on as a service" rights and often ends up running as
# NETWORK SERVICE, which cannot read C:\Users\13115\.workbuddy. Foreground
# mode runs as your normal user and "just works".
#
# Usage (run PowerShell as your normal user 13115):
#   & "D:\Users\qingdeng-ws\personal-workbench\setup_runner.ps1" -Token "PASTE_TOKEN_HERE"
#
# The Token is the short-lived --token value from:
#   GitHub repo -> Settings -> Actions -> Runners -> New self-hosted runner
param(
    [Parameter(Mandatory=$true)][string]$Token,
    [switch]$RunAsService
)

$ErrorActionPreference = "Stop"
$RunnerDir = "D:\actions-runner"
$RepoUrl   = "https://github.com/W-lik721/personal-workbench"
$StartupDir = [Environment]::GetFolderPath("Startup")

if (-not (Test-Path "$RunnerDir\config.cmd")) {
    Write-Error "Runner not found at $RunnerDir. Download and unzip actions-runner first."
    exit 1
}

Set-Location $RunnerDir

if ($RunAsService) {
    Write-Host "==> Configuring runner and installing as Windows service..."
    & ".\config.cmd" --url $RepoUrl --token $Token --runasservice --unattended --replace
} else {
    Write-Host "==> Configuring runner (foreground mode, runs as current user)..."
    & ".\config.cmd" --url $RepoUrl --token $Token --unattended --replace
}
if ($LASTEXITCODE -ne 0) {
    Write-Error "config.cmd failed (rc=$LASTEXITCODE)"
    exit 1
}

if (-not $RunAsService) {
    Write-Host "==> Adding runner to Windows Startup folder so it starts on login..."
    if (-not (Test-Path $StartupDir)) {
        New-Item -ItemType Directory -Path $StartupDir -Force | Out-Null
    }
    $StartupFile = Join-Path $StartupDir "start-workbench-runner.cmd"
    @"
@echo off`ncd /d $RunnerDir`ncall run.cmd`n"@ | Set-Content -Path $StartupFile -Encoding ASCII
    Write-Host "==> Created: $StartupFile"

    Write-Host "==> Starting runner now..."
    Start-Process "cmd.exe" -ArgumentList "/c `"$StartupFile`"" -WorkingDirectory $RunnerDir
}

Write-Host "==> DONE. Open GitHub repo -> Settings -> Actions -> Runners and confirm it shows 'Idle' (online)."
