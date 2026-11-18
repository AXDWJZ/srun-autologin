# 校园网自动登录（深澜 / Srun 认证）

一个**零依赖**的 Windows 校园网登录脚本，适用于使用**深澜（Srun / Shenlan）**认证系统的学校（示例为西南石油大学 `SWPU-EDU`）。

只用 Windows 自带的 **PowerShell 5.1**，不需要安装 Python、Node 或任何第三方库。

---

## 功能

- 自动完成深澜认证（XXTEA 加密 + 自定义 base64 + HMAC-MD5 校验）
- 双击一个快捷方式即可连接（会**真实验证**能否上网，而不是只看接口返回）
- 支持手动模式 / 后台守护模式
- 自动适配 IP 变化（换 AP、换网段）
- 日志记录，方便排查

## 环境要求

- Windows 10 / 11
- Windows PowerShell 5.1（系统自带，无需安装）

## 快速开始

1. 把本仓库所有文件下载/克隆到本地任意目录。
2. 复制 `config.example.json` 为 `config.json`，填入你自己的账号信息：

   ```json
   {
     "portal": "172.16.245.50",
     "username": "YOUR_STUDENT_ID@dxwx",
     "password": "YOUR_PASSWORD",
     "acId": "1"
   }
   ```

3. 双击 `connect.ps1` 即可连接（或右键 → 使用 PowerShell 运行）。

> 如果双击 `.ps1` 打不开，可在该目录打开 PowerShell 后执行：
> ```powershell
> powershell -NoProfile -ExecutionPolicy Bypass -File .\connect.ps1
> ```

## 配置说明

| 字段 | 说明 |
|---|---|
| `portal` | 认证服务器地址（学校门户 IP，可在浏览器登录页地址栏看到） |
| `username` | 学号 + 运营商域名，例如 `202600000000@dxwx`（域名见下方说明） |
| `password` | 校园网密码 |
| `acId` | 认证接入点 ID，一般门户页 `ac_id=1` 就是 `1` |

### 关于运营商域名（`@xxx`）

很多学校的"电信/移动/联通"套餐，登录用户名需要带运营商后缀。获取方法：

1. 先用浏览器正常登录校园网；
2. 访问认证服务器的在线信息接口，例如
   `http://172.16.245.50/cgi-bin/rad_user_info?callback=jQuery`
3. 返回的 JSON 里 `"domain"` 就是后缀（如 `"dxwx"`），拼成 `学号@dxwx`。

如果该字段为空，就不需要后缀。

## 使用方法

### 方式一：手动双击（推荐，简单可靠）

- 双击 `connect.ps1` / 或你自己创建的快捷方式
- 看到 `>>> 连接成功！已实测确认可以正常上网。` 即表示可以上网

### 方式二：命令行

```powershell
# 登录一次
powershell -NoProfile -ExecutionPolicy Bypass -File .\campus_login.ps1 -Once

# 只输出调试信息（自检，不联网）
powershell -NoProfile -ExecutionPolicy Bypass -File .\campus_login.ps1 -SelfTest
```

### 方式三：后台守护（可选）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\campus_login.ps1
```

守护模式会常驻后台，每 `IntervalSeconds` 秒检查一次，掉线后自动重连。
> 注意：部分安全软件可能对"隐藏窗口 + 常驻 + 周期性网络请求"比较敏感，可按需添加信任/排除。

## 工作原理（简述）

1. `GET /cgi-bin/get_challenge` 获取一次性 `challenge` 令牌和客户端 IP；
2. 用 `HMAC-MD5(token, password)` 生成密码摘要；
3. 用 **XXTEA** 加密用户信息 JSON，再用**自定义字母表**做 base64，得到 `{SRBX1}...`；
4. 拼接参数计算 `chksum = SHA1(...)`；
5. `GET /cgi-bin/srun_portal?action=login&...` 完成认证。

代码里内嵌了一小段 C#（通过 `Add-Type` 编译）来实现 32 位 XXTEA 运算，保证在 PowerShell 5.1 下也能正确计算。

## 安全提醒

- `config.json` 里有**明文密码**，已在 `.gitignore` 中排除，**切勿提交**。
- 请只用于**你自己的账号**；不要用来登录他人账号或绕过网络管理策略。
- 本脚本仅与学校认证服务器通信，不收集、不上传任何其他数据。

## 免责声明

本项目仅供学习与个人便利使用。使用本脚本所产生的一切后果（包括但不限于违反学校网络管理规定、账号异常等）由使用者自行承担。

## License

[MIT](LICENSE)
