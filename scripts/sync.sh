#!/bin/bash

##############################################################################
# Telegram Files 自动同步脚本
# 功能：监控本地下载目录，自动将文件同步到 Google Drive
# 特性：速率限制、并发控制、磁盘空间保护
# 作者：Auto-generated
# 日期：2025-10-18
##############################################################################

set -euo pipefail

# ==================== 配置文件 ====================

CONFIG_FILE="/etc/telegram-files-sync.conf"

# 默认配置
SOURCE_DIR="/mnt/tg/telegram-files/data/downloads"
DEST_DIR="gd:/Media/tg files/data"
LOG_FILE="/var/log/telegram-files-sync.log"
RCLONE_LOG_FILE="/var/log/rclone-sync.log"
DISK_THRESHOLD=80
MIN_FREE_SPACE_GB=2
BANDWIDTH_LIMIT="5M"
CONCURRENT_TRANSFERS=2
CONCURRENT_CHECKERS=4
MAX_FILES_PER_SYNC=50
TRANSFER_DELAY=30
MONITOR_INTERVAL=60
FILE_MIN_AGE=60

# 锁文件
LOCK_FILE="/var/run/telegram-files-sync.lock"
SYNC_LOCK_FILE="/var/run/telegram-files-sync-running.lock"

# 读取配置文件（如果存在）
if [ -f "$CONFIG_FILE" ]; then
    # 只读取非注释的配置行
    while IFS='=' read -r key value; do
        # 跳过注释和空行
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        # 去除前后空格和引号
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed 's/^["'\'']\(.*\)["'\'']$/\1/')
        # 设置变量
        case "$key" in
            SOURCE_DIR|DEST_DIR|LOG_FILE|RCLONE_LOG_FILE|BANDWIDTH_LIMIT)
                export "$key=$value"
                ;;
            DISK_THRESHOLD|MIN_FREE_SPACE_GB|CONCURRENT_TRANSFERS|CONCURRENT_CHECKERS|MAX_FILES_PER_SYNC|TRANSFER_DELAY|MONITOR_INTERVAL|FILE_MIN_AGE)
                export "$key=$value"
                ;;
        esac
    done < "$CONFIG_FILE"
fi

# ==================== 函数定义 ====================

# 日志函数
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

# 错误处理
error_exit() {
    log "ERROR" "$1"
    cleanup
    exit 1
}

# 清理函数
cleanup() {
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
    fi
    if [ -f "$SYNC_LOCK_FILE" ]; then
        rm -f "$SYNC_LOCK_FILE"
    fi
}

# 捕获退出信号
trap cleanup EXIT INT TERM

# 检查锁文件
check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "WARN" "另一个同步进程正在运行 (PID: $pid)"
            return 1
        else
            log "INFO" "清理过期的锁文件"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    return 0
}

# 检查同步锁
check_sync_lock() {
    if [ -f "$SYNC_LOCK_FILE" ]; then
        local pid=$(cat "$SYNC_LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "DEBUG" "同步正在进行中 (PID: $pid)"
            return 1
        else
            rm -f "$SYNC_LOCK_FILE"
        fi
    fi
    return 0
}

# 设置同步锁
set_sync_lock() {
    echo $$ > "$SYNC_LOCK_FILE"
}

# 释放同步锁
release_sync_lock() {
    rm -f "$SYNC_LOCK_FILE"
}

# 检查磁盘空间
check_disk_space() {
    local disk_usage=$(df -h /mnt/tg | awk 'NR==2 {print $5}' | sed 's/%//')
    local available_gb=$(df -BG /mnt/tg | awk 'NR==2 {print $4}' | sed 's/G//')

    log "DEBUG" "磁盘使用率: ${disk_usage}%, 可用空间: ${available_gb}GB"

    if [ "$disk_usage" -ge "$DISK_THRESHOLD" ] || [ "$available_gb" -le "$MIN_FREE_SPACE_GB" ]; then
        log "WARN" "磁盘空间不足！使用率: ${disk_usage}%, 可用: ${available_gb}GB"
        return 1
    fi
    return 0
}

# 检查目录是否为空
is_dir_empty() {
    [ -z "$(find "$SOURCE_DIR" -type f -name '*' 2>/dev/null | head -1)" ]
}

# 获取目录大小（MB）
get_dir_size() {
    du -sm "$SOURCE_DIR" 2>/dev/null | awk '{print $1}'
}

# 获取文件数量
get_file_count() {
    find "$SOURCE_DIR" -type f 2>/dev/null | wc -l
}

# 同步文件到云端
sync_files() {
    local force=${1:-false}

    # 检查同步锁
    if ! check_sync_lock; then
        log "DEBUG" "跳过同步：上一次同步仍在进行中"
        return 0
    fi

    # 设置同步锁
    set_sync_lock

    # 检查源目录是否存在
    if [ ! -d "$SOURCE_DIR" ]; then
        log "ERROR" "源目录不存在: $SOURCE_DIR"
        release_sync_lock
        return 1
    fi

    # 检查目录是否为空
    if is_dir_empty; then
        log "DEBUG" "源目录为空，跳过同步"
        release_sync_lock
        return 0
    fi

    local dir_size=$(get_dir_size)
    local file_count=$(get_file_count)

    log "INFO" "开始同步文件... 目录大小: ${dir_size}MB, 文件数: ${file_count}"

    # 等待文件写入完成
    if [ "$force" = false ]; then
        log "INFO" "等待 ${TRANSFER_DELAY} 秒确保文件写入完成..."
        sleep "$TRANSFER_DELAY"
    fi

    # 构建 rclone 参数
    local rclone_args=(
        "move"
        "$SOURCE_DIR/"
        "$DEST_DIR/"
        "--transfers" "$CONCURRENT_TRANSFERS"
        "--checkers" "$CONCURRENT_CHECKERS"
        "--bwlimit" "$BANDWIDTH_LIMIT"
        "--drive-chunk-size" "64M"
        "--fast-list"
        "--delete-empty-src-dirs"
        "--create-empty-src-dirs=false"
        "--exclude" ".DS_Store"
        "--exclude" ".*.tmp"
        "--exclude" "*.part"
        "--exclude" "*.crdownload"
        "--exclude" "*.download"
        "--min-age" "${FILE_MIN_AGE}s"
        "--log-file=$RCLONE_LOG_FILE"
        "--log-level" "INFO"
        "--stats" "10s"
        "--stats-one-line"
    )

    # 注意：rclone 没有直接限制文件数量的参数
    # --max-transfer 是限制数据量，如 "100M" 表示最多传输 100MB
    # 这里我们通过监控间隔和批量处理来控制上传速度

    # 执行同步
    if rclone "${rclone_args[@]}"; then
        log "INFO" "同步成功！已移动 ${dir_size}MB (${file_count} 个文件) 到云端"
        log "INFO" "上传速率限制: ${BANDWIDTH_LIMIT}, 并发数: ${CONCURRENT_TRANSFERS}"

        # 检查并清理空目录
        find "$SOURCE_DIR" -type d -empty -delete 2>/dev/null || true

        release_sync_lock
        return 0
    else
        local exit_code=$?
        log "ERROR" "同步失败！rclone 返回错误 (退出码: $exit_code)"
        release_sync_lock
        return 1
    fi
}

# 主监控循环
monitor_and_sync() {
    log "INFO" "==== Telegram Files 同步服务启动 ===="
    log "INFO" "监控目录: $SOURCE_DIR"
    log "INFO" "目标目录: $DEST_DIR"
    log "INFO" "磁盘阈值: ${DISK_THRESHOLD}%"
    log "INFO" "最小可用空间: ${MIN_FREE_SPACE_GB}GB"
    log "INFO" "上传速率限制: ${BANDWIDTH_LIMIT}"
    log "INFO" "并发传输数: ${CONCURRENT_TRANSFERS}"
    log "INFO" "单次最大文件数: ${MAX_FILES_PER_SYNC}"
    log "INFO" "检查间隔: ${MONITOR_INTERVAL}秒"

    # 检查锁文件
    if ! check_lock; then
        error_exit "无法获取锁，可能有另一个实例正在运行"
    fi

    # 创建源目录（如果不存在）
    mkdir -p "$SOURCE_DIR"

    # 首次启动时同步现有文件
    log "INFO" "检查现有文件..."
    if ! is_dir_empty; then
        log "INFO" "发现现有文件，开始首次同步"
        sync_files true
    fi

    # 主循环 - 定期检查文件变化
    log "INFO" "开始监控循环..."
    local last_file_count=0

    while true; do
        sleep "$MONITOR_INTERVAL"

        # 检查磁盘空间
        local need_sync=false
        if ! check_disk_space; then
            log "WARN" "磁盘空间不足，立即执行同步！"
            need_sync=true
        fi

        # 检查是否有新文件
        if ! is_dir_empty; then
            local current_file_count=$(get_file_count)
            local current_dir_size=$(get_dir_size)

            # 如果文件数量变化或目录大小超过阈值
            if [ "$current_file_count" -ne "$last_file_count" ] || [ "$current_dir_size" -gt 100 ]; then
                log "INFO" "检测到文件变化: 文件数 $current_file_count, 大小 ${current_dir_size}MB"
                need_sync=true
            fi

            last_file_count=$current_file_count
        else
            last_file_count=0
        fi

        # 执行同步
        if [ "$need_sync" = true ]; then
            sync_files false
        else
            log "DEBUG" "无需同步，继续监控..."
        fi
    done
}

# ==================== 主程序 ====================

# 检查依赖
if ! command -v rclone &> /dev/null; then
    error_exit "rclone 未安装！"
fi

# 创建日志文件
touch "$LOG_FILE"
touch "$RCLONE_LOG_FILE"

# 测试 rclone 连接
log "INFO" "测试 rclone 连接..."
if ! rclone lsd "$DEST_DIR" &>/dev/null; then
    error_exit "无法连接到 Google Drive！请检查 rclone 配置"
fi
log "INFO" "rclone 连接正常"

# 启动主监控循环
monitor_and_sync

# 清理
cleanup
