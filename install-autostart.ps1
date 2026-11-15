#Requires -Version 5.1
<#
  QQ 农场 - 安装/移除 登录时自动启动
  用法：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install-autostart.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install-autostart.ps1 -Remove
#>
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$taskName = 'QQFarmBot-Autostart'
$reportTask = 'QQFarmBot-DailyReport'

if ($Remove) {
    foreach ($name in @($taskName, $reportTask)) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Host "已移除任务：$name" -ForegroundColor Green
        }
    }
    Write-Host "已移除开机自启与每日报表任务。" -ForegroundColor Green
    exit 0
}

$powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$action = New-ScheduledTaskAction `
    -Execute $powerShell `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$root\start.ps1`" -NoBrowser" `
    -WorkingDirectory $root

$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$trigger.Delay = 'PT30S'

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description 'QQ 农场面板 + NapCat 容器 + QQ 授权服务，登录 Windows 后自动启动并自动运行已保存账号' `
    -Force | Out-Null

Write-Host "已安装开机自启：$taskName" -ForegroundColor Green
Write-Host "登录 Windows 约 30 秒后自动执行：$root\start.ps1 -NoBrowser"

# 每日报表：每天 23:55 生成 core/data/daily/<日期>.md
$reportAction = New-ScheduledTaskAction `
    -Execute $powerShell `
    -Argument "-NoProfile -WindowStyle Hidden -Command `"Set-Location '$root'; node daily-report.js`"" `
    -WorkingDirectory $root
$reportTrigger = New-ScheduledTaskTrigger -Daily -At '23:55'
$reportSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew
Register-ScheduledTask `
    -TaskName $reportTask `
    -Action $reportAction `
    -Trigger $reportTrigger `
    -Settings $reportSettings `
    -Description '每天 23:55 汇总 QQ 农场各账号的偷菜、收获、金币变化，输出到 core/data/daily/' `
    -Force | Out-Null
Write-Host "已安装每日报表：$reportTask（每天 23:55，输出 core/data/daily/<日期>.md）" -ForegroundColor Green
Write-Host "取消自启：install-autostart.ps1 -Remove（或双击 取消开机自启.bat）"
