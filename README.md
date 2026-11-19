# 校园网自动登录（深澜 / Srun 认证）

一个**零依赖**的 Windows 校园网工具：**自动连上校园网 WiFi + 自动完成认证**，适用于使用**深澜（Srun / Shenlan）**认证系统的学校（示例为西南石油大学 `SWPU-EDU`）。

只用 Windows 自带的 **PowerShell 5.1**，不需要安装 Python、Node 或任何第三方库。

---

## 功能

- ✅ **自动连接校园网 WiFi**（不用先在 WiFi 列表里手动点）
- ✅ 自动完成深澜认证（XXTEA 加密 + 自定义 base64 + HMAC-MD5 校验）
- ✅ 连接后会**真实验证**能否上网（不是只看接口返回）
- ✅ 自动适配 IP 变化（换 AP、换网段）
- ✅ 支持手动双击 / 开机自启
- ✅ 日志记录，方便排查

## 环境要求

- Windows 10 / 11
- Windows PowerShell 5.1（系统自带，无需安装）

## 快速开始

1. 把本仓库所有文件下载到本地任意目录。
2. 复制 `config.example.json` 为 `config.json`，填入你自己的信息：

   ```json
   {
     "portal": "172.16.245.50",
     "ssid": "SWPU-EDU",
     "username": "YOUR_STUDENT_ID@dxwx",
     "password": "YOUR_PASSWORD",
     "acId": "1"
   }
   ```

3. 双击 `connect.ps1` 即可：它会自动连 WiFi → 自动登录 → 验证上网。

> 如果双击 `.ps1` 打不开（被编辑器接走或执行策略拦截），在该目录打开 PowerShell 执行：
> ```powershell
> powershell -NoProfile -ExecutionPolicy Bypass -File .\connect.ps1
> ```

## 配置说明

| 字段 | 说明 |
|---|---|
| `portal` | 认证服务器地址（学校门户 IP，见浏览器登录页地址栏） |
| `ssid` | 校园网 WiFi 名称，例如 `SWPU-EDU`（留空则跳过自动连 WiFi） |
| `username` | 学号 + 运营商域名，例如 `202600000000@dxwx`（见下方说明） |
| `password` | 校园网密码 |
| `acId` | 认证接入点 ID，一般门户 `ac_id=1` 就是 `1` |

### 关于运营商域名（`@xxx`）

很多学校的"电信/移动/联通"套餐要求用户名带运营商后缀。获取方法：

1. 先用浏览器正常登录校园网；
2. 访问认证服务器的在线信息接口，例如
   `http://172.16.245.50/cgi-bin/rad_user_info?callback=jQuery`
3. 返回 JSON 里的 `"domain"` 就是后缀（如 `"dxwx"`），拼成 `学号@dxwx`。

该字段为空则不需要后缀。

## 使用方法

### 方式一：双击连接（推荐）

- 双击 `connect.ps1`（或你创建的快捷方式）
- 看到 `>>> 连接成功！已实测确认可以正常上网。` 即成功

### 方式二：命令行

```powershell
# 登录一次（会自动连 WiFi）
powershell -NoProfile -ExecutionPolicy Bypass -File .\campus_login.ps1 -Once

# 自检（不联网）
powershell -NoProfile -ExecutionPolicy Bypass -File .\campus_login.ps1 -SelfTest
```

### 方式三：开机自启

把下面这条做成快捷方式放进「启动」文件夹（`Win+R` 输入 `shell:startup`）：

```
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<脚本路径>\campus_login.ps1" -Once -MaxAttempts 60
```

开机时它会自动连 WiFi、重试登录（最多约 10 分钟），成功后自动退出，不常驻。

## 工作原理（简述）

1. `netsh wlan connect` 连接校园网 SSID（如未连接）；
2. `GET /cgi-bin/get_challenge` 获取 `challenge` 令牌与客户端 IP；
3. `HMAC-MD5(token, password)` 生成密码摘要；
4. **XXTEA** 加密用户信息 JSON + **自定义字母表 base64** → `{SRBX1}...`；
5. `SHA1(...)` 计算 `chksum`；
6. `GET /cgi-bin/srun_portal?action=login&...` 完成认证。

脚本内嵌一小段 C#（通过 `Add-Type`）实现 32 位 XXTEA，保证 PowerShell 5.1 下计算正确。

## 安全提醒

- `config.json` 内有**明文密码**，已在 `.gitignore` 中排除，**切勿提交**。
- 请只用于**你自己的账号**，不要用于登录他人账号或绕过网络管理策略。
- 本脚本仅与学校认证服务器通信，不收集、不上传任何其他数据。

## 免责声明

本项目仅供学习与个人便利使用。使用本脚本所产生的一切后果（包括但不限于违反学校网络管理规定、账号异常等）由使用者自行承担。

## License

[MIT](LICENSE)
