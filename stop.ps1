#Requires -Version 5.1
<#
  QQ 农场挂机面板 - 停止全部服务（面板 + 授权服务 + NapCat 容器）
  用法：双击 停止服务.bat
#>
$ErrorActionPreference = 'SilentlyContinue'
$root = $PSScriptRoot
Set-Location $root

$dockerDir = Join-Path $root 'napcat-docker'
$authDir   = Join-Path (Split-Path $root -Parent) 'qq-miniapp-auth'
$botPid    = Join-Path $root 'app.pid'
$authPid   = Join-Path $authDir 'auth.pid'
$collectorPid = Join-Path $root 'daily-collector.pid'
$port      = if ($env:ADMIN_PORT) { [int]$env:ADMIN_PORT } else { 3007 }

$stopped = @()

# ---------- 1. 农场面板 ----------
if (Test-Path $botPid) {
    $savedPid = (Get-Content $botPid | Select-Object -First 1)
    if ($savedPid -match '^\d+$') {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid"
        if ($p -and $p.Name -eq 'node.exe' -and $p.CommandLine -like '*core\client.js*') {
            Stop-Process -Id $savedPid -Force
            $stopped += "面板 (PID $savedPid)"
        }
    }
    Remove-Item $botPid -Force
}

$conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
foreach ($c in $conns) {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId = $($c.OwningProcess)"
    if ($p -and $p.Name -eq 'node.exe' -and $p.CommandLine -like '*core\client.js*') {
        Stop-Process -Id $p.ProcessId -Force
        $stopped += "面板端口 $port (PID $($p.ProcessId))"
    }
}

# ---------- 2. QQ 授权服务 ----------
if (Test-Path $authPid) {
    $savedPid = (Get-Content $authPid | Select-Object -First 1)
    if ($savedPid -match '^\d+$') {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid"
        if ($p -and $p.Name -eq 'node.exe') {
            taskkill /PID $savedPid /T /F *> $null
            $stopped += "QQ 授权服务 (PID $savedPid)"
        }
    }
    Remove-Item $authPid -Force
}

foreach ($authPort in 8787, 9010) {
    $conns = Get-NetTCPConnection -LocalPort $authPort -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId = $($c.OwningProcess)"
        if ($p -and $p.Name -eq 'node.exe' -and $p.CommandLine -like '*qq-miniapp-auth*') {
            Stop-Process -Id $p.ProcessId -Force
            $stopped += "授权服务端口 $authPort (PID $($p.ProcessId))"
        }
    }
}

# ---------- 3. 每日数据采集 ----------
if (Test-Path $collectorPid) {
    $savedPid = (Get-Content $collectorPid | Select-Object -First 1)
    if ($savedPid -match '^\d+$') {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid"
        if ($p -and $p.Name -eq 'node.exe' -and $p.CommandLine -like '*daily-collector.js*') {
            Stop-Process -Id $savedPid -Force
            $stopped += "每日采集 (PID $savedPid)"
        }
    }
    Remove-Item $collectorPid -Force
}

Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -match 'node\.exe"?\s+daily-collector\.js\s*$' } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force
    $stopped += "每日采集 (PID $($_.ProcessId))"
}

# ---------- 4. NapCat 容器 ----------
if ((Get-Command docker -ErrorAction SilentlyContinue)) {
    docker info *> $null
    if ($LASTEXITCODE -eq 0) {
        Push-Location $dockerDir
        docker compose stop *> $null
        Pop-Location
        $stopped += "NapCat 容器"
    }
}

if ($stopped.Count -gt 0) {
    Write-Host ("已停止：" + ($stopped -join '、')) -ForegroundColor Green
} else {
    Write-Host "QQ 农场当前没有在运行。" -ForegroundColor Yellow
}
