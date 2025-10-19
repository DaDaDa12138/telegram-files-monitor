# Telegram Files Monitor

🚀 一键部署 Telegram 文件监控与云同步系统

自动化监控 Telegram 频道/群组文件，实时同步到云存储（Google Drive等），并提供 Web 监控面板。

## ✨ 功能特性

- 📦 **Docker 容器化部署** - 使用 [telegram-files](https://github.com/jarvis2f/telegram-files) 管理 Telegram 文件
- ☁️ **自动云同步** - rclone 智能同步到 Google Drive/OneDrive 等云存储
- 📊 **实时监控面板** - Flask Web 界面实时显示系统状态
- 🔒 **HTTPS 安全访问** - Caddy 自动配置 SSL 证书
- 🔐 **双重认证保护** - Basic Auth + 登录系统
- 📈 **详细统计信息** - 网络流量、云存储配额、上传进度
- 🎯 **智能速率控制** - 带宽限制、并发控制、磁盘保护
- 🔄 **WebSocket 实时通信** - 文件下载进度实时更新

## 📋 系统要求

- 操作系统: Debian 11+ 或 Ubuntu 20.04+
- 内存: 最少 1GB RAM（推荐 2GB+）
- 磁盘: 最少 10GB 可用空间
- 网络: 稳定的互联网连接
- Root 权限

## 🚀 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/DaDaDa12138/telegram-files-monitor.git
cd telegram-files-monitor
```

### 2. 运行安装脚本

```bash
sudo bash install.sh
```

### 3. 按照提示配置

安装脚本会交互式询问以下信息：

#### Docker 容器配置
- **Docker 端口**: 默认 6543
- **数据目录**: 默认 `/opt/telegram-files/data`
- **Telegram API ID**: 从 [my.telegram.org](https://my.telegram.org/apps) 获取
- **Telegram API Hash**: 从 [my.telegram.org](https://my.telegram.org/apps) 获取

#### rclone 同步配置
- **本地源目录**: Docker 下载目录
- **rclone 远程名称**: 默认 `gd`（Google Drive）
- **远程路径**: 云存储中的目标路径
- **带宽限制**: 默认 5M
- **并发数**: 默认 2

#### 监控面板配置
- **端口**: 默认 5000
- **管理员密码**: 自定义密码（至少6位）

#### Caddy HTTPS 配置（可选）
- **Telegram Files 域名**: 如 `tgfile.example.com`
- **监控面板域名**: 如 `tgdash.example.com`
- **Basic Auth 用户名和密码**: 保护 Telegram Files 访问

### 4. 配置 rclone

安装过程中会自动启动 rclone 配置向导：

```bash
# 1. 选择 'n' 创建新远程
# 2. 输入远程名称（如: gd）
# 3. 选择存储类型:
#    - Google Drive: 15
#    - OneDrive: 26
#    - 其他请查看列表
# 4. 按照提示完成 OAuth 授权
```

#### Google Drive 配置示例

```
Current remotes:

e) Edit existing remote
n) New remote
d) Delete remote
q) Quit config
e/n/d/q> n

name> gd
Type of storage to configure.
Choose a number from below:
15 / Google Drive
Storage> 15

Google Application Client Id
client_id> (直接回车)

Google Application Client Secret
client_secret> (直接回车)

Scope that rclone should use:
1 / Full access
scope> 1

Use auto config?
y) Yes
n) No
y/n> y

(浏览器会自动打开进行授权)
```

### 5. 登录 Telegram 账号

安装完成后，访问 Telegram Files Web 界面：

1. 打开浏览器访问配置的域名或 `http://服务器IP:6543`
2. 如配置了 Basic Auth，输入用户名和密码
3. 点击 "Add Account" 添加 Telegram 账号
4. 按照提示完成手机验证

### 6. 配置自动下载

在 Telegram Files 界面中：

1. 进入要监控的频道/群组
2. 点击 "Auto Download" 启用自动下载
3. 选择文件类型（图片、视频、文档等）
4. 设置下载条件（大小限制、时间范围等）

## 📊 监控面板功能

访问监控面板查看实时状态：

- **系统信息**: CPU、内存、磁盘使用率
- **服务状态**: Docker、同步服务、监控面板状态
- **网络流量**: 实时上传/下载速率和历史总量
- **云存储**: 总容量、已使用、可用空间
- **上传进度**: 当前文件、进度百分比、传输速度
- **同步统计**: 已同步文件数、总大小、最近文件
- **日志查看**: 同步日志、rclone 日志

### 默认登录信息

- 用户名: `admin`
- 密码: 安装时设置的管理员密码

## 🔧 配置文件

### 主配置文件

**位置**: `/etc/telegram-files-sync.conf`

```bash
# 同步配置
SOURCE_DIR="/opt/telegram-files/data/downloads"
DEST_DIR="gd:/Media/tg files/data"

# 性能配置
BANDWIDTH_LIMIT="5M"
CONCURRENT_TRANSFERS=2
CONCURRENT_CHECKERS=4

# 磁盘保护
DISK_THRESHOLD=80
MIN_FREE_SPACE_GB=2

# 监控配置
MONITOR_INTERVAL=60
FILE_MIN_AGE=60
```

### Docker Compose 配置

**位置**: `/opt/telegram-files/docker-compose.yaml`

修改后需要重启容器：
```bash
cd /opt/telegram-files
docker compose restart
```

### Caddy 配置

**位置**: `/etc/caddy/Caddyfile`

修改后需要重新加载：
```bash
systemctl reload caddy
```

## 🛠️ 常用命令

### 查看服务状态

```bash
# 查看所有服务状态
systemctl status docker
systemctl status telegram-files-sync
systemctl status tg-monitor
systemctl status caddy

# 查看 Docker 容器
docker ps
docker logs telegram-files
```

### 查看日志

```bash
# 同步服务日志
tail -f /var/log/telegram-files-sync.log

# rclone 日志
tail -f /var/log/rclone-sync.log

# 监控面板日志
journalctl -u tg-monitor -f

# Docker 容器日志
docker logs -f telegram-files
```

### 重启服务

```bash
# 重启同步服务
systemctl restart telegram-files-sync

# 重启监控面板
systemctl restart tg-monitor

# 重启 Docker 容器
cd /opt/telegram-files
docker compose restart

# 重启 Caddy
systemctl restart caddy
```

### 手动触发同步

```bash
# 停止自动同步服务
systemctl stop telegram-files-sync

# 手动执行同步
rclone move /opt/telegram-files/data/downloads gd:/Media/tg\ files/data \
  --transfers 2 \
  --checkers 4 \
  --bwlimit 5M \
  --delete-empty-src-dirs \
  --progress

# 重新启动自动同步
systemctl start telegram-files-sync
```

## 📁 目录结构

```
telegram-files-monitor/
├── install.sh              # 主安装脚本
├── README.md              # 本文档
├── LICENSE                # MIT 许可证
├── scripts/
│   └── sync.sh           # rclone 同步脚本
├── systemd/
│   ├── telegram-files-sync.service    # 同步服务
│   └── tg-monitor.service            # 监控面板服务
├── monitor/
│   ├── app.py            # Flask 后端
│   ├── templates/        # HTML 模板
│   │   ├── dashboard.html
│   │   └── login.html
│   └── static/          # 静态资源
├── templates/
│   ├── docker-compose.yaml      # Docker Compose 模板
│   ├── .env.example            # 环境变量示例
│   └── sync.conf.example       # 同步配置示例
└── config/              # 配置文件目录
```

## 🔍 故障排除

### Docker 容器无法启动

```bash
# 检查日志
docker logs telegram-files

# 检查端口占用
netstat -tuln | grep 6543

# 重新创建容器
cd /opt/telegram-files
docker compose down
docker compose up -d
```

### rclone 同步失败

```bash
# 测试 rclone 连接
rclone lsd gd:

# 检查配置
rclone config show

# 查看详细日志
tail -f /var/log/rclone-sync.log
```

### WebSocket 连接失败

```bash
# 检查 Caddy 配置
caddy validate --config /etc/caddy/Caddyfile

# 重新加载 Caddy
systemctl reload caddy

# 检查日志
tail -f /var/log/caddy/tgfile.log
```

### 磁盘空间不足

```bash
# 检查磁盘使用
df -h

# 手动清理已同步文件
rm -rf /opt/telegram-files/data/downloads/*

# 调整磁盘阈值
nano /etc/telegram-files-sync.conf
# 修改 DISK_THRESHOLD 和 MIN_FREE_SPACE_GB
systemctl restart telegram-files-sync
```

## 🔒 安全建议

1. **修改默认密码**: 安装完成后立即修改所有默认密码
2. **配置防火墙**: 仅开放必要端口（80, 443）
3. **定期更新**: 保持系统和 Docker 镜像更新
4. **备份配置**: 定期备份配置文件和数据库
5. **使用 HTTPS**: 为所有 Web 界面配置域名和 SSL
6. **限制访问**: 使用 Basic Auth 或 VPN 限制访问

## 🔄 更新

### 更新 Docker 镜像

```bash
cd /opt/telegram-files
docker compose pull
docker compose up -d
```

### 更新监控面板

```bash
cd /root/telegram-files-monitor
git pull
cp monitor/app.py /opt/tg-monitor/
cp monitor/templates/* /opt/tg-monitor/templates/
systemctl restart tg-monitor
```

### 更新同步脚本

```bash
cd /root/telegram-files-monitor
git pull
cp scripts/sync.sh /usr/local/bin/telegram-files-sync.sh
chmod +x /usr/local/bin/telegram-files-sync.sh
systemctl restart telegram-files-sync
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

### 开发环境设置

```bash
# 克隆仓库
git clone https://github.com/DaDaDa12138/telegram-files-monitor.git
cd telegram-files-monitor

# 测试安装脚本
bash install.sh

# 测试监控面板
cd monitor
python3 app.py
```

## 📝 更新日志

### v1.0.0 (2025-10-19)

- ✅ 首次发布
- ✅ 一键安装脚本
- ✅ Docker 容器化部署
- ✅ rclone 自动同步
- ✅ Web 监控面板
- ✅ Caddy HTTPS 配置
- ✅ WebSocket 实时通信
- ✅ 详细文档

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- [telegram-files](https://github.com/jarvis2f/telegram-files) - Telegram 文件管理核心
- [rclone](https://rclone.org/) - 云存储同步工具
- [Caddy](https://caddyserver.com/) - 现代 Web 服务器
- [Flask](https://flask.palletsprojects.com/) - Python Web 框架

## 📧 联系方式

- GitHub: [@DaDaDa12138](https://github.com/DaDaDa12138)
- Issues: [提交问题](https://github.com/DaDaDa12138/telegram-files-monitor/issues)

---

⭐ 如果这个项目对你有帮助，请给个 Star！
