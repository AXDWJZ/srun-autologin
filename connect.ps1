# ============================================================
#  校园网连接工具（手动双击版 · 会真实验证能否上网）
# ============================================================

$ErrorActionPreference = 'Continue'
$dir  = $PSScriptRoot
$ps1  = Join-Path $dir 'campus_login.ps1'
$log  = Join-Path $dir 'campus_login.log'

# 读取配置（WLAN 名称 / 认证服务器地址）
$cfg = $null
$cfgPath = Join-Path $dir 'config.json'
if (Test-Path $cfgPath) { try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch {} }
$targetSsid = if ($cfg -and $cfg.ssid)   { [string]$cfg.ssid }   else { "" }
$portalUrl  = if ($cfg -and $cfg.portal) { "http://" + [string]$cfg.portal + "/" } else { "http://172.16.245.50/" }

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "          校园网连接" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $ps1)) {
    Write-Host "找不到 campus_login.ps1（请确认它和本工具在同一个文件夹）" -ForegroundColor Red
    Read-Host "按回车关闭"
    exit 1
}

function Test-Portal {
    try {
        $null = Invoke-WebRequest -Uri $portalUrl -UseBasicParsing -TimeoutSec 3
        return $true
    } catch { return $false }
}

function Test-Net {
    try {
        $r = Invoke-WebRequest -Uri "https://www.baidu.com" -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

function Get-CurSsid {
    try {
        $out = netsh wlan show interfaces 2>$null
        $line = $out | Where-Object { $_ -match '^\s*SSID\s*:' } | Select-Object -First 1
        if ($line) { return ($line -split ':', 2)[1].Trim() }
    } catch {}
    return ""
}

# 第零步：确保已连上校园网 WiFi（没连就自动连）
if ($targetSsid) {
    Write-Host "正在检查 WiFi ..." -ForegroundColor Yellow
    $cur = Get-CurSsid
    if ($cur -ne $targetSsid) {
        Write-Host "当前 WiFi：$(if($cur){$cur}else{'未连接'})，正在自动连接 '$targetSsid' ..." -ForegroundColor Yellow
        for ($i = 1; $i -le 8; $i++) {
            try { & netsh wlan connect "name=$targetSsid" 2>$null | Out-Null } catch {}
            Start-Sleep -Seconds 3
            $cur = Get-CurSsid
            if ($cur -eq $targetSsid) { break }
        }
        if ($cur -eq $targetSsid) {
            Write-Host "WiFi 已连上 '$targetSsid'。" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host ">>> 没能连上校园网 WiFi '$targetSsid'。" -ForegroundColor Red
            Write-Host "    请确认：1) 在校园网信号范围内；2) 笔记本 WiFi 开关已打开。" -ForegroundColor Red
            Write-Host ""
            Read-Host "按回车关闭"
            exit 1
        }
    } else {
        Write-Host "WiFi 已连接 '$targetSsid'。" -ForegroundColor Green
    }
}

# 第一步：等网络真正就绪（认证服务器能访问）
Write-Host "正在等待网络就绪..." -ForegroundColor Yellow
$portalOk = $false
for ($i = 0; $i -lt 20; $i++) {
    if (Test-Portal) { $portalOk = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $portalOk) {
    Write-Host ""
    Write-Host ">>> 连不上校园网认证服务器。" -ForegroundColor Red
    Write-Host "    请确认右下角 WiFi 已连上 'SWPU-EDU'，然后重新双击本图标。" -ForegroundColor Red
    Write-Host ""
    Read-Host "按回车关闭"
    exit 1
}

# 第二步：执行登录
Write-Host "正在登录..." -ForegroundColor Yellow
$before = if (Test-Path $log) { (Get-Content $log).Count } else { 0 }
& $ps1 -Once -MaxAttempts 5 6>$null
$after = if (Test-Path $log) { Get-Content $log } else { @() }
$new = @($after | Select-Object -Skip $before)
$loggedIn = (($new | Select-String -Pattern 'Login success' -SimpleMatch).Count -gt 0)

# 第三步：真实验证能不能上网
Write-Host "正在验证能否上网..." -ForegroundColor Yellow
$netOk = $false
for ($i = 0; $i -lt 6; $i++) {
    if (Test-Net) { $netOk = $true; break }
    Start-Sleep -Seconds 3
}

Write-Host ""
if ($netOk) {
    Write-Host ">>> 连接成功！已实测确认可以正常上网。" -ForegroundColor Green
} elseif ($loggedIn) {
    Write-Host ">>> 登录接口返回成功，但暂时还上不了外网。" -ForegroundColor Yellow
    Write-Host "    可能网络刚连上还没完全就绪：请关掉窗口，等 10 秒后再双击一次。" -ForegroundColor Yellow
} else {
    Write-Host ">>> 登录失败。" -ForegroundColor Red
    if ($new.Count -gt 0) {
        Write-Host "    详细信息：" -ForegroundColor DarkGray
        $new | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor DarkGray }
    }
    Write-Host "    请把这段文字截图发给我。" -ForegroundColor Red
}
Write-Host ""
Read-Host "按回车关闭窗口"
