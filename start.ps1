#Requires -Version 5.1
<#
  QQ 农场挂机面板 - 一键启动（NapCat 容器 + 授权服务 + 面板）
  用法：双击 启动服务.bat，或 powershell -File start.ps1 -NoBrowser
#>
param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

$dockerDir = Join-Path $root 'napcat-docker'
$authDir   = Join-Path (Split-Path $root -Parent) 'qq-miniapp-auth'
$botPid    = Join-Path $root 'app.pid'
$botLog    = Join-Path $root 'app.log'
$botErr    = Join-Path $root 'app.err.log'
$authPid   = Join-Path $authDir 'auth.pid'
$authLog   = Join-Path $authDir 'auth.log'
$authErr   = Join-Path $authDir 'auth.err.log'
$collectorPid = Join-Path $root 'daily-collector.pid'
$collectorLog = Join-Path $root 'daily-collector.log'
$collectorErr = Join-Path $root 'daily-collector.err.log'
$port      = if ($env:ADMIN_PORT) { [int]$env:ADMIN_PORT } else { 3007 }
$url       = "http://localhost:$port"

function Test-Listen([int]$p) {
    [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
}

function Wait-Listen([int]$p, [int]$seconds) {
    for ($i = 0; $i -lt $seconds; $i++) {
        if (Test-Listen $p) { return $true }
        Start-Sleep 1
    }
    return $false
}

function Test-Tcp([string]$target, [int]$p, [int]$timeoutMs = 1000) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $task = $client.ConnectAsync($target, $p)
        $ok = $task.Wait($timeoutMs) -and $client.Connected
        $client.Close()
        return [bool]$ok
    } catch {
        return $false
    }
}

function Wait-Tcp([string]$target, [int]$p, [int]$seconds) {
    for ($i = 0; $i -lt $seconds; $i++) {
        if (Test-Tcp $target $p) { return $true }
        Start-Sleep 1
    }
    return $false
}

function Get-FarmProcess {
    if (-not (Test-Path $botPid)) { return $null }
    $savedPid = (Get-Content $botPid -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $savedPid -or $savedPid -notmatch '^\d+$') { return $null }
    $p = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid" -ErrorAction SilentlyContinue
    if ($p -and $p.Name -eq 'node.exe' -and $p.CommandLine -like '*core\client.js*') { return $p }
    return $null
}

function Get-CollectorProcess {
    if (-not (Test-Path $collectorPid)) { return $null }
    $savedPid = (Get-Content $collectorPid -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $savedPid -or $savedPid -notmatch '^\d+$') { return $null }
    $p = Get-CimInstance Win32_Process -Filter "ProcessId = $savedPid" -ErrorAction SilentlyContinue
    if ($p -and $p.Name -eq 'node.exe' -and $p.CommandLine -like '*daily-collector.js*') { return $p }
    return $null
}

function Start-Collector {
    if (Get-CollectorProcess) { return }
    if (-not (Test-Path (Join-Path $root 'daily-collector.js'))) { return }
    $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $nodeExe) { return }
    Set-Content -Path $collectorLog -Value '' -Encoding utf8
    Set-Content -Path $collectorErr -Value '' -Encoding utf8
    $cp = Start-Process -FilePath $nodeExe `
        -ArgumentList 'daily-collector.js' `
        -WorkingDirectory $root `
        -RedirectStandardOutput $collectorLog `
        -RedirectStandardError $collectorErr `
        -WindowStyle Hidden `
        -PassThru
    Set-Content -Path $collectorPid -Value $cp.Id -Encoding ascii
    Write-Host "每日数据采集已启动 (PID $($cp.Id)，每 5 分钟采样)" -ForegroundColor Gray
}

function Test-DockerEngine {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    docker info 2>$null | Out-Null
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    return ($code -eq 0)
}

function Start-DockerEngine {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host "未检测到 Docker，跳过 NapCat（QQ 扫码登录将不可用）。" -ForegroundColor Yellow
        return $false
    }
    if (Test-DockerEngine) { return $true }

    $desktop = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
    if (Test-Path $desktop) {
        Write-Host "正在启动 Docker Desktop..." -ForegroundColor Yellow
        Start-Process $desktop
    }
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep 2
        if (Test-DockerEngine) { return $true }
    }
    return $false
}

# ---------- 1. NapCat 容器 ----------
if (Start-DockerEngine) {
    $ErrorActionPreference = 'Continue'
    $container = (docker ps --filter 'name=qq-napcat' --format '{{.Names}}' 2>$null) -join ''
    if (-not $container) {
        Write-Host "正在启动 NapCat 容器..." -ForegroundColor Yellow
        Push-Location $dockerDir
        docker compose up -d 2>$null
        Pop-Location
    }
    $ErrorActionPreference = 'Stop'
    if (Wait-Tcp '127.0.0.1' 6099 90) {
        Write-Host "NapCat 已就绪 (WebUI: http://127.0.0.1:6099)" -ForegroundColor Green
    } else {
        Write-Host "NapCat 未在预期时间内就绪，QQ 扫码登录可能暂不可用，详见 docker logs qq-napcat" -ForegroundColor Yellow
    }
} else {
    Write-Host "Docker 引擎未启动，NapCat 不可用。" -ForegroundColor Yellow
}

# ---------- 2. qq-miniapp-auth 授权服务 ----------
if (-not (Test-Listen 8787)) {
    $authEntry = Join-Path $authDir 'start-all.js'
    if (Test-Path $authEntry) {
        Write-Host "正在启动 QQ 授权服务..." -ForegroundColor Yellow
        $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
        if (-not $nodeExe) { Write-Host "未找到 Node.js。" -ForegroundColor Red; exit 1 }
        Set-Content -Path $authLog -Value '' -Encoding utf8
        Set-Content -Path $authErr -Value '' -Encoding utf8
        $ap = Start-Process -FilePath $nodeExe `
            -ArgumentList 'start-all.js' `
            -WorkingDirectory $authDir `
            -RedirectStandardOutput $authLog `
            -RedirectStandardError $authErr `
            -WindowStyle Hidden `
            -PassThru
        Set-Content -Path $authPid -Value $ap.Id -Encoding ascii
        if (-not (Wait-Listen 8787 40)) {
            Write-Host "QQ 授权服务启动失败，见 $authErr" -ForegroundColor Red
        }
    } else {
        Write-Host "未找到 qq-miniapp-auth（$authDir），QQ 扫码登录不可用。" -ForegroundColor Yellow
    }
}

# ---------- 3. 农场面板 ----------
$running = Get-FarmProcess
if ($running) {
    Write-Host "QQ 农场已在运行 (PID $($running.ProcessId))：$url" -ForegroundColor Green
    Start-Collector
    if (-not $NoBrowser) { Start-Process $url }
    exit 0
}

if (-not (Test-Path (Join-Path $root 'core\client.js'))) {
    Write-Host "未找到 core\client.js，正在构建（首次启动约 1 分钟）..." -ForegroundColor Yellow
    & pnpm build
    if ($LASTEXITCODE -ne 0) { Write-Host "构建失败。" -ForegroundColor Red; exit 1 }
}

$nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $nodePath) { Write-Host "未找到 Node.js，请先安装 Node.js 20.19+。" -ForegroundColor Red; exit 1 }

Set-Content -Path $botLog -Value '' -Encoding utf8
Set-Content -Path $botErr -Value '' -Encoding utf8

# 固定服务 Token：供 QQFarmCodeHelper 等本机工具跨重启调用 API（不随面板登录 Token 失效）
$serviceTokenFile = Join-Path $root 'service-token.txt'
if (-not (Test-Path $serviceTokenFile)) {
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 32
    $rng.GetBytes($bytes)
    ([BitConverter]::ToString($bytes) -replace '-', '').ToLower() | Set-Content -Path $serviceTokenFile -Encoding ascii
}
$env:FARM_SERVICE_TOKEN = (Get-Content $serviceTokenFile -Raw).Trim()

$proc = Start-Process -FilePath $nodePath `
    -ArgumentList 'core\client.js' `
    -WorkingDirectory $root `
    -RedirectStandardOutput $botLog `
    -RedirectStandardError $botErr `
    -WindowStyle Hidden `
    -PassThru
Set-Content -Path $botPid -Value $proc.Id -Encoding ascii

if (Wait-Listen $port 40) {
    Write-Host "QQ 农场已启动 (PID $($proc.Id))：$url" -ForegroundColor Green
    Write-Host "初始账号：admin / admin（登录后请立即修改密码）" -ForegroundColor Yellow
    Write-Host "QQ 扫码登录已开启：设置 → 系统设置 → 登录设置；添加账号时选择“QQ扫码登录”。" -ForegroundColor Gray
    Start-Collector
    if (-not $NoBrowser) { Start-Process $url }
} else {
    Write-Host "启动失败，最近日志：" -ForegroundColor Red
    if (Test-Path $botLog) { Get-Content $botLog -Tail 30 }
    if (Test-Path $botErr) { Get-Content $botErr -Tail 30 }
    Remove-Item $botPid -ErrorAction SilentlyContinue
    exit 1
}
