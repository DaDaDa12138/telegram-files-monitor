#!/bin/bash

################################################################################
# Telegram Files Monitor - 一键安装脚本
# 支持 Debian/Ubuntu 系统
# 功能：安装 Docker、rclone、Caddy、监控面板等所有组件
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}==== $1 ====${NC}\n"
}

# 错误处理
error_exit() {
    log_error "$1"
    exit 1
}

# 检查是否以 root 运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "请使用 root 用户运行此脚本！(使用 sudo)"
    fi
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        log_info "检测到操作系统: $PRETTY_NAME"
    else
        error_exit "无法检测操作系统"
    fi

    # 检查是否支持
    case $OS in
        debian|ubuntu)
            log_info "操作系统支持！"
            ;;
        *)
            log_warn "未经测试的操作系统: $OS，可能会遇到问题"
            read -p "是否继续？(y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
            ;;
    esac
}

# 更新系统包
update_system() {
    log_step "更新系统包"
    apt-get update
    apt-get install -y curl wget gnupg2 ca-certificates lsb-release apt-transport-https software-properties-common
}

# 安装 Docker
install_docker() {
    log_step "安装 Docker"

    if command -v docker &> /dev/null; then
        log_info "Docker 已安装: $(docker --version)"
        return 0
    fi

    log_info "开始安装 Docker..."

    # 添加 Docker 官方 GPG 密钥
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # 添加 Docker 仓库
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装 Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # 启动并启用 Docker
    systemctl start docker
    systemctl enable docker

    log_info "Docker 安装完成: $(docker --version)"
}

# 安装 rclone
install_rclone() {
    log_step "安装 rclone"

    if command -v rclone &> /dev/null; then
        log_info "rclone 已安装: $(rclone --version | head -1)"
        return 0
    fi

    log_info "开始安装 rclone..."
    curl https://rclone.org/install.sh | bash

    log_info "rclone 安装完成: $(rclone --version | head -1)"
}

# 安装 Caddy
install_caddy() {
    log_step "安装 Caddy"

    if command -v caddy &> /dev/null; then
        log_info "Caddy 已安装: $(caddy version)"
        return 0
    fi

    log_info "开始安装 Caddy..."

    # 添加 Caddy 官方仓库
    apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list

    # 安装 Caddy
    apt update
    apt install -y caddy

    # 创建日志目录
    mkdir -p /var/log/caddy
    chown -R caddy:caddy /var/log/caddy
    chmod 755 /var/log/caddy

    log_info "Caddy 安装完成: $(caddy version)"
}

# 安装 Python 和依赖
install_python() {
    log_step "安装 Python 环境"

    apt-get install -y python3 python3-pip python3-venv
    pip3 install --upgrade pip

    # 安装 Flask 和其他依赖
    pip3 install flask flask-cors psutil

    log_info "Python 环境安装完成"
}

# 交互式配置
interactive_config() {
    log_step "交互式配置"

    echo ""
    echo "请输入以下配置信息："
    echo ""

    # Docker 配置
    echo -e "${BLUE}=== Docker 容器配置 ===${NC}"
    read -p "Docker 容器端口 (默认: 6543): " DOCKER_PORT
    DOCKER_PORT=${DOCKER_PORT:-6543}

    read -p "Docker 数据挂载目录 (默认: /opt/telegram-files/data): " DOCKER_DATA_DIR
    DOCKER_DATA_DIR=${DOCKER_DATA_DIR:-/opt/telegram-files/data}

    read -p "Telegram API ID: " TELEGRAM_API_ID
    while [[ -z "$TELEGRAM_API_ID" ]]; do
        log_error "API ID 不能为空"
        read -p "Telegram API ID: " TELEGRAM_API_ID
    done

    read -p "Telegram API Hash: " TELEGRAM_API_HASH
    while [[ -z "$TELEGRAM_API_HASH" ]]; do
        log_error "API Hash 不能为空"
        read -p "Telegram API Hash: " TELEGRAM_API_HASH
    done

    # rclone 同步配置
    echo ""
    echo -e "${BLUE}=== rclone 同步配置 ===${NC}"

    read -p "本地同步源目录 (默认: ${DOCKER_DATA_DIR}/downloads): " SOURCE_DIR
    SOURCE_DIR=${SOURCE_DIR:-${DOCKER_DATA_DIR}/downloads}

    read -p "rclone 远程名称 (默认: gd): " RCLONE_REMOTE
    RCLONE_REMOTE=${RCLONE_REMOTE:-gd}

    read -p "远程目录路径 (默认: /Media/tg files/data): " REMOTE_PATH
    REMOTE_PATH=${REMOTE_PATH:-/Media/tg files/data}

    read -p "上传带宽限制 (默认: 5M): " BANDWIDTH_LIMIT
    BANDWIDTH_LIMIT=${BANDWIDTH_LIMIT:-5M}

    read -p "并发传输数 (默认: 2): " CONCURRENT_TRANSFERS
    CONCURRENT_TRANSFERS=${CONCURRENT_TRANSFERS:-2}

    # 监控面板配置
    echo ""
    echo -e "${BLUE}=== 监控面板配置 ===${NC}"

    read -p "监控面板端口 (默认: 5000): " MONITOR_PORT
    MONITOR_PORT=${MONITOR_PORT:-5000}

    read -p "监控面板管理员密码: " ADMIN_PASSWORD
    while [[ -z "$ADMIN_PASSWORD" || ${#ADMIN_PASSWORD} -lt 6 ]]; do
        log_error "密码不能为空且至少6个字符"
        read -p "监控面板管理员密码: " ADMIN_PASSWORD
    done

    # Caddy 域名配置
    echo ""
    echo -e "${BLUE}=== Caddy HTTPS 配置 ===${NC}"
    log_info "如果不需要配置域名，直接按回车跳过"

    read -p "Telegram Files 域名 (如: tgfile.example.com): " TGFILE_DOMAIN
    read -p "监控面板域名 (如: tgdash.example.com): " TGDASH_DOMAIN

    if [[ -n "$TGFILE_DOMAIN" ]]; then
        read -p "Telegram Files 访问密码用户名 (默认: admin): " TGFILE_USER
        TGFILE_USER=${TGFILE_USER:-admin}

        read -p "Telegram Files 访问密码: " TGFILE_PASSWORD
        while [[ -z "$TGFILE_PASSWORD" || ${#TGFILE_PASSWORD} -lt 6 ]]; then
            log_error "密码不能为空且至少6个字符"
            read -p "Telegram Files 访问密码: " TGFILE_PASSWORD
        done
    fi

    # 保存配置到文件
    cat > /tmp/install-config.env <<EOF
# Docker 配置
DOCKER_PORT=$DOCKER_PORT
DOCKER_DATA_DIR=$DOCKER_DATA_DIR
TELEGRAM_API_ID=$TELEGRAM_API_ID
TELEGRAM_API_HASH=$TELEGRAM_API_HASH

# rclone 配置
SOURCE_DIR=$SOURCE_DIR
RCLONE_REMOTE=$RCLONE_REMOTE
REMOTE_PATH=$REMOTE_PATH
BANDWIDTH_LIMIT=$BANDWIDTH_LIMIT
CONCURRENT_TRANSFERS=$CONCURRENT_TRANSFERS

# 监控面板配置
MONITOR_PORT=$MONITOR_PORT
ADMIN_PASSWORD=$ADMIN_PASSWORD

# Caddy 配置
TGFILE_DOMAIN=$TGFILE_DOMAIN
TGDASH_DOMAIN=$TGDASH_DOMAIN
TGFILE_USER=$TGFILE_USER
TGFILE_PASSWORD=$TGFILE_PASSWORD
EOF

    log_info "配置已保存到 /tmp/install-config.env"
}

# 配置 rclone
configure_rclone() {
    log_step "配置 rclone"

    if rclone listremotes | grep -q "^${RCLONE_REMOTE}:"; then
        log_info "rclone 远程 '${RCLONE_REMOTE}' 已配置"
        read -p "是否重新配置？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    log_warn "请按照提示配置 rclone 远程存储"
    log_info "1. 选择 'n' 创建新的远程"
    log_info "2. 输入名称: ${RCLONE_REMOTE}"
    log_info "3. 选择存储类型 (Google Drive 通常是 15)"
    log_info "4. 按照提示完成 OAuth 授权"

    rclone config
}

# 部署 Docker 容器
deploy_docker() {
    log_step "部署 Docker 容器"

    # 创建工作目录
    mkdir -p "$DOCKER_DATA_DIR"
    DOCKER_ROOT=$(dirname "$DOCKER_DATA_DIR")

    # 创建 docker-compose.yml
    cat > "$DOCKER_ROOT/docker-compose.yaml" <<EOF
services:
  telegram-files:
    container_name: telegram-files
    image: ghcr.io/jarvis2f/telegram-files:latest
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://127.0.0.1/api/health"]
      interval: 10s
      retries: 3
      timeout: 10s
      start_period: 10s
    environment:
      APP_ENV: "prod"
      APP_ROOT: "/app/data"
      TELEGRAM_API_ID: ${TELEGRAM_API_ID}
      TELEGRAM_API_HASH: ${TELEGRAM_API_HASH}
    ports:
      - "127.0.0.1:${DOCKER_PORT}:80"
    volumes:
      - ${DOCKER_DATA_DIR}:/app/data
EOF

    # 创建 .env 文件
    cat > "$DOCKER_ROOT/.env" <<EOF
TELEGRAM_API_ID=${TELEGRAM_API_ID}
TELEGRAM_API_HASH=${TELEGRAM_API_HASH}
EOF

    # 启动容器
    cd "$DOCKER_ROOT"
    docker compose up -d

    log_info "Docker 容器已启动"
    sleep 5
    docker ps --filter name=telegram-files
}

# 部署同步服务
deploy_sync_service() {
    log_step "部署同步服务"

    # 复制同步脚本
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    cp "$SCRIPT_DIR/scripts/sync.sh" /usr/local/bin/telegram-files-sync.sh
    chmod +x /usr/local/bin/telegram-files-sync.sh

    # 创建配置文件
    cat > /etc/telegram-files-sync.conf <<EOF
# Telegram Files 同步配置
SOURCE_DIR="${SOURCE_DIR}"
DEST_DIR="${RCLONE_REMOTE}:${REMOTE_PATH}"
LOG_FILE="/var/log/telegram-files-sync.log"
RCLONE_LOG_FILE="/var/log/rclone-sync.log"
DISK_THRESHOLD=80
MIN_FREE_SPACE_GB=2
BANDWIDTH_LIMIT="${BANDWIDTH_LIMIT}"
CONCURRENT_TRANSFERS=${CONCURRENT_TRANSFERS}
CONCURRENT_CHECKERS=4
MAX_FILES_PER_SYNC=50
TRANSFER_DELAY=30
MONITOR_INTERVAL=60
FILE_MIN_AGE=60
EOF

    # 创建 systemd 服务
    cp "$SCRIPT_DIR/systemd/telegram-files-sync.service" /etc/systemd/system/

    # 启动服务
    systemctl daemon-reload
    systemctl enable telegram-files-sync
    systemctl start telegram-files-sync

    log_info "同步服务已启动"
}

# 部署监控面板
deploy_monitor() {
    log_step "部署监控面板"

    # 创建监控面板目录
    MONITOR_DIR="/opt/tg-monitor"
    mkdir -p "$MONITOR_DIR"
    mkdir -p "$MONITOR_DIR/templates"
    mkdir -p "$MONITOR_DIR/static"

    # 复制文件
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    cp "$SCRIPT_DIR/monitor/app.py" "$MONITOR_DIR/"
    cp "$SCRIPT_DIR/monitor/templates/"* "$MONITOR_DIR/templates/" 2>/dev/null || true
    cp "$SCRIPT_DIR/monitor/static/"* "$MONITOR_DIR/static/" 2>/dev/null || true

    # 更新密码
    sed -i "s/'admin': '[^']*'/'admin': '$ADMIN_PASSWORD'/g" "$MONITOR_DIR/app.py"

    # 更新配置路径
    sed -i "s|SOURCE_DIR = '.*'|SOURCE_DIR = '${SOURCE_DIR}'|g" "$MONITOR_DIR/app.py"

    # 更新端口
    sed -i "s/port=5000/port=${MONITOR_PORT}/g" "$MONITOR_DIR/app.py"

    # 创建 systemd 服务
    cp "$SCRIPT_DIR/systemd/tg-monitor.service" /etc/systemd/system/
    sed -i "s|WorkingDirectory=.*|WorkingDirectory=$MONITOR_DIR|g" /etc/systemd/system/tg-monitor.service
    sed -i "s|ExecStart=.*|ExecStart=/usr/bin/python3 $MONITOR_DIR/app.py|g" /etc/systemd/system/tg-monitor.service

    # 启动服务
    systemctl daemon-reload
    systemctl enable tg-monitor
    systemctl start tg-monitor

    log_info "监控面板已启动在端口 $MONITOR_PORT"
}

# 配置 Caddy
configure_caddy() {
    if [[ -z "$TGFILE_DOMAIN" && -z "$TGDASH_DOMAIN" ]]; then
        log_info "未配置域名，跳过 Caddy 配置"
        return 0
    fi

    log_step "配置 Caddy"

    # 生成 Basic Auth 密码哈希
    if [[ -n "$TGFILE_PASSWORD" ]]; then
        TGFILE_PASSWORD_HASH=$(caddy hash-password --plaintext "$TGFILE_PASSWORD")
    fi

    # 创建 Caddyfile
    cat > /etc/caddy/Caddyfile <<EOF
# Caddy 配置文件 - 自动生成
EOF

    # 监控面板配置
    if [[ -n "$TGDASH_DOMAIN" ]]; then
        cat >> /etc/caddy/Caddyfile <<EOF

# 监控面板 - HTTPS
$TGDASH_DOMAIN {
	reverse_proxy 127.0.0.1:${MONITOR_PORT} {
		header_up Host {host}
		header_up X-Real-IP {remote_host}
	}

	log {
		output file /var/log/caddy/tgdash.log {
			roll_size 10mb
			roll_keep 5
		}
	}

	encode gzip
}
EOF
    fi

    # Telegram Files 配置
    if [[ -n "$TGFILE_DOMAIN" ]]; then
        cat >> /etc/caddy/Caddyfile <<EOF

# Telegram Files - HTTPS + 密码保护
$TGFILE_DOMAIN {
	# 检测WebSocket连接
	@websockets {
		header Connection *Upgrade*
		header Upgrade websocket
	}

	# WebSocket路径 - 需要认证但不压缩
	handle @websockets {
		basic_auth {
			${TGFILE_USER} ${TGFILE_PASSWORD_HASH}
		}
		reverse_proxy 127.0.0.1:${DOCKER_PORT} {
			header_up Host {host}
			header_up X-Real-IP {remote_host}
			header_up X-Forwarded-For {remote_host}
			header_up X-Forwarded-Proto {scheme}
			header_up Connection {http.request.header.Connection}
			header_up Upgrade {http.request.header.Upgrade}
			header_up Sec-Websocket-Key {http.request.header.Sec-Websocket-Key}
			header_up Sec-Websocket-Version {http.request.header.Sec-Websocket-Version}
			header_up Sec-Websocket-Extensions {http.request.header.Sec-Websocket-Extensions}
			flush_interval -1
			transport http {
				read_timeout 600s
				write_timeout 600s
			}
		}
	}

	# 普通HTTP请求 - 需要认证并压缩
	handle {
		basic_auth {
			${TGFILE_USER} ${TGFILE_PASSWORD_HASH}
		}
		reverse_proxy 127.0.0.1:${DOCKER_PORT} {
			header_up Host {host}
			header_up X-Real-IP {remote_host}
			header_up X-Forwarded-For {remote_host}
			header_up X-Forwarded-Proto {scheme}
		}
		encode gzip
	}

	log {
		output file /var/log/caddy/tgfile.log {
			roll_size 10mb
			roll_keep 5
		}
	}
}
EOF
    fi

    # 重新加载 Caddy
    systemctl reload caddy

    log_info "Caddy 配置完成"
}

# 显示完成信息
show_completion() {
    log_step "安装完成！"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Telegram Files Monitor 安装成功！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    echo -e "${BLUE}访问信息：${NC}"

    if [[ -n "$TGDASH_DOMAIN" ]]; then
        echo -e "  监控面板: ${GREEN}https://$TGDASH_DOMAIN${NC}"
    else
        echo -e "  监控面板: ${GREEN}http://$(hostname -I | awk '{print $1}'):$MONITOR_PORT${NC}"
    fi
    echo -e "  用户名: ${YELLOW}admin${NC}"
    echo -e "  密码: ${YELLOW}$ADMIN_PASSWORD${NC}"
    echo ""

    if [[ -n "$TGFILE_DOMAIN" ]]; then
        echo -e "  Telegram Files: ${GREEN}https://$TGFILE_DOMAIN${NC}"
        echo -e "  用户名: ${YELLOW}$TGFILE_USER${NC}"
        echo -e "  密码: ${YELLOW}$TGFILE_PASSWORD${NC}"
    else
        echo -e "  Telegram Files: ${GREEN}http://$(hostname -I | awk '{print $1}'):$DOCKER_PORT${NC}"
    fi
    echo ""

    echo -e "${BLUE}服务状态：${NC}"
    echo -e "  Docker 容器: $(systemctl is-active docker)"
    echo -e "  同步服务: $(systemctl is-active telegram-files-sync)"
    echo -e "  监控面板: $(systemctl is-active tg-monitor)"
    if [[ -n "$TGFILE_DOMAIN" || -n "$TGDASH_DOMAIN" ]]; then
        echo -e "  Caddy: $(systemctl is-active caddy)"
    fi
    echo ""

    echo -e "${BLUE}常用命令：${NC}"
    echo -e "  查看同步日志: ${YELLOW}tail -f /var/log/telegram-files-sync.log${NC}"
    echo -e "  查看容器日志: ${YELLOW}docker logs telegram-files${NC}"
    echo -e "  重启同步服务: ${YELLOW}systemctl restart telegram-files-sync${NC}"
    echo -e "  重启监控面板: ${YELLOW}systemctl restart tg-monitor${NC}"
    echo ""

    echo -e "${BLUE}数据目录：${NC}"
    echo -e "  Docker 数据: ${YELLOW}$DOCKER_DATA_DIR${NC}"
    echo -e "  同步源目录: ${YELLOW}$SOURCE_DIR${NC}"
    echo ""

    log_warn "重要提示："
    log_warn "1. 请确保已完成 rclone 配置并测试连接"
    log_warn "2. 请在 Telegram Files Web 界面登录您的 Telegram 账号"
    log_warn "3. 配置文件位于 /etc/telegram-files-sync.conf"
    log_warn "4. 如需修改配置，请编辑配置文件后重启相应服务"
    echo ""
}

# 主函数
main() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
╔════════════════════════════════════════════════════╗
║   Telegram Files Monitor - 一键安装脚本           ║
║   自动化部署 Docker + rclone + Caddy + 监控面板   ║
╚════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    check_root
    detect_os

    # 更新系统
    update_system

    # 安装依赖
    install_docker
    install_rclone
    install_caddy
    install_python

    # 交互式配置
    interactive_config

    # 加载配置
    source /tmp/install-config.env

    # 配置 rclone
    configure_rclone

    # 部署服务
    deploy_docker
    deploy_sync_service
    deploy_monitor
    configure_caddy

    # 显示完成信息
    show_completion

    # 清理临时文件
    rm -f /tmp/install-config.env
}

# 执行主函数
main "$@"
