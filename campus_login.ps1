# ============================================================
#  Campus Network Auto Login  (Srun / Shenlan portal)
#  Works with Chinese campus networks that use the Srun
#  (Shenlan) captive portal, e.g. SWPU / SWPU-EDU.
#
#  Pure Windows PowerShell 5.1, no third-party dependencies.
#  Account settings are read from config.json (NOT committed).
#
#  Features:
#    - auto-connect to the campus WiFi SSID (netsh)
#    - XXTEA + custom base64 + HMAC-MD5 authentication
#    - one-shot login (-Once) or background guard
# ============================================================

param(
    [int]$MaxAttempts = 60,
    [switch]$SelfTest,
    [switch]$Once,
    [int]$IntervalSeconds = 60,
    [string]$ConfigPath = ""
)

# ---- Load account config (config.json next to this script) ----
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot "config.json" }
if (-not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: config.json not found." -ForegroundColor Red
    Write-Host "Copy config.example.json to config.json and fill in your account." -ForegroundColor Red
    exit 1
}
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$PORTAL   = [string]$cfg.portal
$USERNAME = [string]$cfg.username
$PASSWORD = [string]$cfg.password
$AC_ID    = [string]$cfg.acId
$SSID     = [string]$cfg.ssid
$N        = 200
$TYPE     = 1

$LOG_FILE = Join-Path $PSScriptRoot "campus_login.log"

$cs = @"
using System;
using System.Text;
using System.Security.Cryptography;

public static class Srun {
    public static string Md5(string s) {
        using (var h = MD5.Create()) {
            var b = h.ComputeHash(Encoding.UTF8.GetBytes(s));
            var sb = new StringBuilder();
            foreach (var x in b) sb.Append(x.ToString("x2"));
            return sb.ToString();
        }
    }
    public static string Sha1(string s) {
        using (var h = SHA1.Create()) {
            var b = h.ComputeHash(Encoding.UTF8.GetBytes(s));
            var sb = new StringBuilder();
            foreach (var x in b) sb.Append(x.ToString("x2"));
            return sb.ToString();
        }
    }
    public static string Hmac(string key, string msg) {
        using (var h = new HMACMD5(Encoding.UTF8.GetBytes(key))) {
            var b = h.ComputeHash(Encoding.UTF8.GetBytes(msg));
            var sb = new StringBuilder();
            foreach (var x in b) sb.Append(x.ToString("x2"));
            return sb.ToString();
        }
    }
    static uint[] Pack(string str, bool appendLen) {
        int c = str.Length;
        int words = (c + 3) / 4;
        var v = new uint[words + (appendLen ? 1 : 0)];
        for (int i = 0; i < c; i += 4) {
            uint w = (uint)str[i];
            if (i + 1 < c) w |= (uint)str[i + 1] << 8;
            if (i + 2 < c) w |= (uint)str[i + 2] << 16;
            if (i + 3 < c) w |= (uint)str[i + 3] << 24;
            v[i >> 2] = w;
        }
        if (appendLen) v[words] = (uint)c;
        return v;
    }
    static string Unpack(uint[] a) {
        var sb = new StringBuilder();
        for (int i = 0; i < a.Length; i++) {
            sb.Append((char)(a[i] & 0xff));
            sb.Append((char)((a[i] >> 8) & 0xff));
            sb.Append((char)((a[i] >> 16) & 0xff));
            sb.Append((char)((a[i] >> 24) & 0xff));
        }
        return sb.ToString();
    }
    public static string Encode(string str, string key) {
        if (str == "") return "";
        var v = Pack(str, true);
        var k = Pack(key, false);
        var kk = new uint[4];
        for (int i = 0; i < 4; i++) kk[i] = i < k.Length ? k[i] : 0u;
        int n = v.Length - 1;
        uint z = v[n], y = v[0];
        uint delta = 0x86014019u | 0x183639A0u;
        int q = (int)Math.Floor(6.0 + 52.0 / (n + 1));
        uint d = 0;
        int p;
        while (q-- > 0) {
            d = (d + delta) & (0x8CE0D9BFu | 0x731F2640u);
            int e = (int)((d >> 2) & 3);
            for (p = 0; p < n; p++) {
                y = v[p + 1];
                uint m = ((z >> 5) ^ (y << 2)) + (((y >> 3) ^ (z << 4)) ^ (d ^ y));
                m += (kk[(p & 3) ^ e] ^ z);
                z = v[p] = (v[p] + m) & (0xEFB8D130u | 0x10472ECFu);
            }
            y = v[0];
            uint m2 = ((z >> 5) ^ (y << 2)) + (((y >> 3) ^ (z << 4)) ^ (d ^ y));
            m2 += (kk[(p & 3) ^ e] ^ z);
            z = v[n] = (v[n] + m2) & (0xBB390742u | 0x44C6F8BDu);
        }
        return Unpack(v);
    }
    public static string B64(string str) {
        var bytes = new byte[str.Length];
        for (int i = 0; i < str.Length; i++) bytes[i] = (byte)(str[i] & 0xff);
        string std = Convert.ToBase64String(bytes);
        string custom = "LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA";
        string stdA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        var sb = new StringBuilder();
        foreach (char ch in std) {
            int idx = stdA.IndexOf(ch);
            sb.Append(idx >= 0 ? custom[idx] : ch);
        }
        return sb.ToString();
    }
}
"@

if (-not ("Srun" -as [type])) { Add-Type -TypeDefinition $cs -Language CSharp }

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Host $line
    try { Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8 } catch {}
}

function Get-CurSsid {
    try {
        $out = netsh wlan show interfaces 2>$null
        $line = $out | Where-Object { $_ -match '^\s*SSID\s*:' } | Select-Object -First 1
        if ($line) { return ($line -split ':', 2)[1].Trim() }
    } catch {}
    return ""
}

function Ensure-Wifi([string]$target) {
    if (-not $target) { return $true }
    $cur = Get-CurSsid
    if ($cur -eq $target) { return $true }
    Write-Log ("WiFi current SSID is '{0}', trying to connect to '{1}' ..." -f $cur, $target)
    for ($i = 1; $i -le 5; $i++) {
        try { & netsh wlan connect "name=$target" 2>$null | Out-Null } catch {}
        Start-Sleep -Seconds 3
        if ((Get-CurSsid) -eq $target) {
            Write-Log ("WiFi connected: {0}" -f $target)
            return $true
        }
    }
    Write-Log ("WiFi connect to '{0}' failed." -f $target)
    return $false
}

function Get-Challenge {
    $ts = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    $u = "http://$PORTAL/cgi-bin/get_challenge?callback=jQuery&username=$USERNAME&ip=&_=$ts"
    $raw = (Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 8).Content
    $a = $raw.IndexOf("(") + 1
    $b = $raw.LastIndexOf(")")
    return ($raw.Substring($a, $b - $a) | ConvertFrom-Json)
}

function Invoke-Login {
    $ch = Get-Challenge
    $token = $ch.challenge
    $ip = $ch.client_ip
    $hmd5 = [Srun]::Hmac($token, $PASSWORD)
    $infoJson = '{"username":"' + $USERNAME + '","password":"' + $PASSWORD + '","ip":"' + $ip + '","acid":"' + $AC_ID + '","enc_ver":"srun_bx1"}'
    $info = '{SRBX1}' + [Srun]::B64([Srun]::Encode($infoJson, $token))
    $str = $token + $USERNAME + $token + $hmd5 + $token + $AC_ID + $token + $ip + $token + $N + $token + $TYPE + $token + $info
    $chksum = [Srun]::Sha1($str)
    $params = [ordered]@{
        callback     = "jQuery"
        action       = "login"
        username     = $USERNAME
        password     = "{MD5}" + $hmd5
        os           = "Windows 10"
        name         = "Windows"
        double_stack = 0
        chksum       = $chksum
        info         = $info
        ac_id        = $AC_ID
        ip           = $ip
        n            = $N
        type         = $TYPE
        client_type  = 1
        nas_ip       = ""
        mac          = ""
        captchaId    = ""
        captchaVal   = ""
        ap_id        = ""
        ap_ip        = ""
    }
    $qs = ($params.GetEnumerator() | ForEach-Object { $_.Key + "=" + [Uri]::EscapeDataString([string]$_.Value) }) -join "&"
    $u = "http://$PORTAL/cgi-bin/srun_portal?" + $qs
    $raw = (Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 8).Content
    $a = $raw.IndexOf("(") + 1
    $b = $raw.LastIndexOf(")")
    return ($raw.Substring($a, $b - $a) | ConvertFrom-Json)
}

if ($SelfTest) {
    $token = "5b697e0e2bd102dd3bb963bcc5f83374f33785f20bef319e234435959b1a7583"
    $ip = "10.0.0.1"
    $hmd5 = [Srun]::Hmac($token, $PASSWORD)
    $infoJson = '{"username":"' + $USERNAME + '","password":"' + $PASSWORD + '","ip":"' + $ip + '","acid":"' + $AC_ID + '","enc_ver":"srun_bx1"}'
    $info = '{SRBX1}' + [Srun]::B64([Srun]::Encode($infoJson, $token))
    $str = $token + $USERNAME + $token + $hmd5 + $token + $AC_ID + $token + $ip + $token + $N + $token + $TYPE + $token + $info
    $chksum = [Srun]::Sha1($str)
    "INFO   = " + $info
    "CHKSUM = " + $chksum
    return
}

function Test-Online {
    # Real internet check: fetch a public HTTPS site.
    # Fail or redirect to the campus portal => treat as offline.
    try {
        $r = Invoke-WebRequest -Uri "https://www.baidu.com" -UseBasicParsing -TimeoutSec 6
        if ($r.StatusCode -ne 200) { return $false }
        $host = ""
        try { $host = [string]$r.BaseResponse.ResponseUri.Host } catch {}
        if ($host -like "*baidu*") { return $true }
        if ($r.Content -match "baidu") { return $true }
        return $false
    } catch {
        return $false
    }
}

function Try-Login([int]$tries) {
    for ($attempt = 1; $attempt -le $tries; $attempt++) {
        try {
            $res = Invoke-Login
            $resv   = [string]$res.res
            $err    = [string]$res.error
            $sucMsg = [string]$res.suc_msg
            if ($resv -eq "ok" -or $err -eq "ok" -or $sucMsg -match "ok|success|already") {
                Write-Log ("Login success! (attempt {0}; res={1}; suc_msg={2})" -f $attempt, $resv, $sucMsg)
                return $true
            }
            Write-Log ("Attempt {0} failed: res={1} error={2} msg={3}" -f $attempt, $resv, $err, [string]$res.error_msg)
        } catch {
            Write-Log ("Attempt {0} error: {1}" -f $attempt, $_.Exception.Message)
        }
        if ($attempt -lt $tries) { Start-Sleep -Seconds 10 }
    }
    return $false
}

if ($Once) {
    Write-Log "One-shot login ..."
    $null = Ensure-Wifi $SSID
    $null = Try-Login $MaxAttempts
    return
}

Write-Log ("Guard started, check every {0}s." -f $IntervalSeconds)
while ($true) {
    try {
        if (-not (Test-Online)) {
            $null = Ensure-Wifi $SSID
            Write-Log "Offline detected, trying to login ..."
            $null = Try-Login 3
        }
    } catch {
        Write-Log ("Guard error: {0}" -f $_.Exception.Message)
    }
    Start-Sleep -Seconds $IntervalSeconds
}
