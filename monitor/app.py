#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Telegram Files 监控面板 - 后端 API 服务
提供系统监控、同步状态、文件统计等功能
"""

import os
import json
import psutil
import subprocess
import re
from datetime import datetime, timedelta
from pathlib import Path
from flask import Flask, render_template, jsonify, request, session, redirect, url_for
from flask_cors import CORS
from functools import wraps

# 配置
app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'change-this-to-a-random-secret-key-in-production')
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(hours=24)
CORS(app)

# 默认用户配置（请修改密码）
USERS = {
    'admin': 'WZYwzy258852!'  # ⚠️ 请立即修改此密码
}

# 日志文件路径
SYNC_LOG_FILE = '/var/log/telegram-files-sync.log'
RCLONE_LOG_FILE = '/var/log/rclone-sync.log'
CONFIG_FILE = '/etc/telegram-files-sync.conf'
SOURCE_DIR = '/mnt/tg/telegram-files/data/downloads'

# 流量统计缓存
_last_net_io = None
_last_net_io_time = None

# ==================== 辅助函数 ====================

def login_required(f):
    """登录验证装饰器"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'username' not in session:
            return jsonify({'error': '未登录', 'code': 401}), 401
        return f(*args, **kwargs)
    return decorated_function


def read_config():
    """读取配置文件"""
    config = {}
    try:
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip().strip('"\'')
                    config[key] = value
    except Exception as e:
        print(f"读取配置文件失败: {e}")
    return config


def parse_log_file(file_path, max_lines=1000):
    """解析日志文件"""
    logs = []
    try:
        if os.path.exists(file_path):
            with open(file_path, 'r') as f:
                lines = f.readlines()
                for line in lines[-max_lines:]:
                    logs.append(line.strip())
    except Exception as e:
        print(f"读取日志文件失败: {e}")
    return logs


def get_system_info():
    """获取系统信息"""
    try:
        # CPU 信息
        cpu_percent = psutil.cpu_percent(interval=1)
        cpu_count = psutil.cpu_count()

        # 内存信息
        mem = psutil.virtual_memory()

        # 磁盘信息
        disk = psutil.disk_usage('/mnt/tg')

        # 网络信息
        net_io = psutil.net_io_counters()

        # 负载平均值
        try:
            load_avg = os.getloadavg()
        except:
            load_avg = [0, 0, 0]

        return {
            'cpu': {
                'percent': round(cpu_percent, 1),
                'count': cpu_count,
                'load_avg': [round(x, 2) for x in load_avg]
            },
            'memory': {
                'total': mem.total,
                'available': mem.available,
                'used': mem.used,
                'percent': round(mem.percent, 1),
                'total_gb': round(mem.total / (1024**3), 2),
                'used_gb': round(mem.used / (1024**3), 2),
                'available_gb': round(mem.available / (1024**3), 2)
            },
            'disk': {
                'total': disk.total,
                'used': disk.used,
                'free': disk.free,
                'percent': round(disk.percent, 1),
                'total_gb': round(disk.total / (1024**3), 2),
                'used_gb': round(disk.used / (1024**3), 2),
                'free_gb': round(disk.free / (1024**3), 2)
            },
            'network': {
                'bytes_sent': net_io.bytes_sent,
                'bytes_recv': net_io.bytes_recv,
                'bytes_sent_mb': round(net_io.bytes_sent / (1024**2), 2),
                'bytes_recv_mb': round(net_io.bytes_recv / (1024**2), 2)
            }
        }
    except Exception as e:
        print(f"获取系统信息失败: {e}")
        return {}


def get_service_status(service_name):
    """获取systemd服务状态"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', service_name],
            capture_output=True,
            text=True,
            timeout=5
        )
        is_active = result.stdout.strip() == 'active'

        # 获取详细状态
        result = subprocess.run(
            ['systemctl', 'status', service_name, '--no-pager'],
            capture_output=True,
            text=True,
            timeout=5
        )

        status_text = result.stdout

        # 提取 PID
        pid_match = re.search(r'Main PID: (\d+)', status_text)
        pid = int(pid_match.group(1)) if pid_match else None

        # 提取内存使用
        mem_match = re.search(r'Memory: ([\d.]+)([KMG])', status_text)
        memory = mem_match.group(1) + mem_match.group(2) if mem_match else 'N/A'

        # 提取运行时间
        uptime_match = re.search(r'Active: active \([^)]+\) since ([^;]+);', status_text)
        uptime = uptime_match.group(1) if uptime_match else 'N/A'

        return {
            'active': is_active,
            'status': 'running' if is_active else 'stopped',
            'pid': pid,
            'memory': memory,
            'uptime': uptime
        }
    except Exception as e:
        print(f"获取服务状态失败: {e}")
        return {'active': False, 'status': 'unknown', 'error': str(e)}


def get_sync_stats():
    """获取同步统计信息"""
    stats = {
        'total_synced': 0,
        'total_size_mb': 0,
        'success_count': 0,
        'error_count': 0,
        'last_sync': None,
        'recent_files': []
    }

    try:
        logs = parse_log_file(SYNC_LOG_FILE, max_lines=500)

        for log in logs:
            # 统计成功同步
            if '同步成功' in log:
                stats['success_count'] += 1
                # 提取文件大小
                match = re.search(r'已移动 (\d+)MB.*?(\d+) 个文件', log)
                if match:
                    size_mb = int(match.group(1))
                    file_count = int(match.group(2))
                    stats['total_synced'] += file_count
                    stats['total_size_mb'] += size_mb

                # 提取时间
                time_match = re.search(r'\[([^\]]+)\]', log)
                if time_match and not stats['last_sync']:
                    stats['last_sync'] = time_match.group(1)

            # 统计错误
            if 'ERROR' in log:
                stats['error_count'] += 1

        # 解析 rclone 日志获取最近文件
        rclone_logs = parse_log_file(RCLONE_LOG_FILE, max_lines=100)
        for log in reversed(rclone_logs):
            if 'INFO' in log and ('Copied' in log or 'Moved' in log):
                match = re.search(r': ([^:]+): (Copied|Moved)', log)
                if match:
                    filename = match.group(1).strip()
                    if len(stats['recent_files']) < 10:
                        stats['recent_files'].append({
                            'name': filename,
                            'action': match.group(2)
                        })

    except Exception as e:
        print(f"获取同步统计失败: {e}")

    return stats


def get_cloud_stats():
    """获取云端统计（使用 rclone）"""
    try:
        result = subprocess.run(
            ['rclone', 'size', 'gd:/Media/tg files/data', '--json'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            return {
                'total_files': data.get('count', 0),
                'total_size': data.get('bytes', 0),
                'total_size_gb': round(data.get('bytes', 0) / (1024**3), 2)
            }
    except Exception as e:
        print(f"获取云端统计失败: {e}")

    return {'total_files': 0, 'total_size': 0, 'total_size_gb': 0}


def get_network_stats():
    """获取网络流量统计（实时速率和历史总量）"""
    global _last_net_io, _last_net_io_time

    try:
        # 获取当前网络统计
        current_net_io = psutil.net_io_counters()
        current_time = datetime.now()

        # 历史总量（系统启动以来）
        stats = {
            'total_sent': current_net_io.bytes_sent,
            'total_recv': current_net_io.bytes_recv,
            'total_sent_gb': round(current_net_io.bytes_sent / (1024**3), 2),
            'total_recv_gb': round(current_net_io.bytes_recv / (1024**3), 2),
            'upload_speed': 0,
            'download_speed': 0,
            'upload_speed_mbps': 0,
            'download_speed_mbps': 0
        }

        # 计算实时速率（需要两次采样）
        if _last_net_io is not None and _last_net_io_time is not None:
            time_delta = (current_time - _last_net_io_time).total_seconds()
            if time_delta > 0:
                # 计算速率（字节/秒）
                upload_speed = (current_net_io.bytes_sent - _last_net_io.bytes_sent) / time_delta
                download_speed = (current_net_io.bytes_recv - _last_net_io.bytes_recv) / time_delta

                stats['upload_speed'] = int(upload_speed)
                stats['download_speed'] = int(download_speed)
                # 转换为 Mbps
                stats['upload_speed_mbps'] = round(upload_speed * 8 / (1024 * 1024), 2)
                stats['download_speed_mbps'] = round(download_speed * 8 / (1024 * 1024), 2)

        # 更新缓存
        _last_net_io = current_net_io
        _last_net_io_time = current_time

        return stats
    except Exception as e:
        print(f"获取网络统计失败: {e}")
        return {
            'total_sent': 0, 'total_recv': 0,
            'total_sent_gb': 0, 'total_recv_gb': 0,
            'upload_speed': 0, 'download_speed': 0,
            'upload_speed_mbps': 0, 'download_speed_mbps': 0
        }


def get_cloud_quota():
    """获取云存储配额信息（总容量、已使用、可用）"""
    try:
        result = subprocess.run(
            ['rclone', 'about', 'gd:', '--json'],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            total = data.get('total', 0)
            used = data.get('used', 0)
            free = data.get('free', 0)

            return {
                'total': total,
                'used': used,
                'free': free,
                'total_gb': round(total / (1024**3), 2) if total else 0,
                'used_gb': round(used / (1024**3), 2) if used else 0,
                'free_gb': round(free / (1024**3), 2) if free else 0,
                'used_percent': round((used / total * 100), 2) if total and used else 0
            }
    except Exception as e:
        print(f"获取云存储配额失败: {e}")

    return {
        'total': 0, 'used': 0, 'free': 0,
        'total_gb': 0, 'used_gb': 0, 'free_gb': 0, 'used_percent': 0
    }


def get_upload_progress():
    """获取当前上传进度"""
    try:
        # 检查 rclone 进程
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            if proc.info['name'] == 'rclone':
                cmdline = proc.info.get('cmdline', [])
                if 'move' in cmdline or 'copy' in cmdline or 'sync' in cmdline:
                    # 解析 rclone 日志获取进度
                    logs = parse_log_file(RCLONE_LOG_FILE, max_lines=50)

                    current_file = None
                    progress = None
                    speed = None
                    eta = None

                    # 从日志中提取进度信息
                    for log in reversed(logs):
                        # 查找正在传输的文件
                        if 'Transferred:' in log:
                            # 解析传输进度
                            # 格式示例: "Transferred: 1.234 GiB / 2.345 GiB, 52%, 10.5 MiB/s, ETA 1m30s"
                            match = re.search(r'Transferred:\s+([^,]+),\s+(\d+)%,\s+([^,]+)', log)
                            if match:
                                progress = int(match.group(2))
                                speed = match.group(3).strip()

                        # 查找当前文件名
                        if 'INFO' in log and ('Copied' in log or 'Moved' in log or ':' in log):
                            match = re.search(r': ([^:]+):', log)
                            if match and not current_file:
                                current_file = match.group(1).strip()

                    if current_file or progress:
                        return {
                            'is_uploading': True,
                            'current_file': current_file or '处理中...',
                            'progress': progress or 0,
                            'speed': speed or 'N/A',
                            'status': '正在上传'
                        }

        # 没有找到活动的 rclone 进程
        return {
            'is_uploading': False,
            'current_file': None,
            'progress': 0,
            'speed': 'N/A',
            'status': '空闲'
        }
    except Exception as e:
        print(f"获取上传进度失败: {e}")
        return {
            'is_uploading': False,
            'current_file': None,
            'progress': 0,
            'speed': 'N/A',
            'status': '未知'
        }


# ==================== 路由 ====================

@app.route('/')
def index():
    """首页"""
    if 'username' in session:
        return render_template('dashboard.html', username=session['username'])
    return render_template('login.html')


@app.route('/login', methods=['POST'])
def login():
    """登录"""
    data = request.json
    username = data.get('username')
    password = data.get('password')

    if username in USERS and USERS[username] == password:
        session['username'] = username
        session.permanent = True
        return jsonify({'success': True, 'message': '登录成功'})

    return jsonify({'success': False, 'message': '用户名或密码错误'}), 401


@app.route('/logout', methods=['POST'])
def logout():
    """登出"""
    session.pop('username', None)
    return jsonify({'success': True, 'message': '已登出'})


@app.route('/change-password', methods=['POST'])
@login_required
def change_password():
    """修改密码"""
    data = request.json
    old_password = data.get('old_password')
    new_password = data.get('new_password')

    username = session.get('username')

    # 验证旧密码
    if username not in USERS or USERS[username] != old_password:
        return jsonify({'success': False, 'message': '原密码错误'}), 400

    # 验证新密码
    if not new_password or len(new_password) < 6:
        return jsonify({'success': False, 'message': '新密码至少需要 6 个字符'}), 400

    # 更新密码到文件
    try:
        with open(__file__, 'r', encoding='utf-8') as f:
            content = f.read()

        # 替换密码
        import re
        pattern = f"'{username}'\\s*:\\s*'[^']*'"
        replacement = f"'{username}': '{new_password}'"
        new_content = re.sub(pattern, replacement, content)

        with open(__file__, 'w', encoding='utf-8') as f:
            f.write(new_content)

        # 更新内存中的密码
        USERS[username] = new_password

        return jsonify({'success': True, 'message': '密码修改成功，建议重启服务以确保生效'})
    except Exception as e:
        return jsonify({'success': False, 'message': f'修改失败: {str(e)}'}), 500


@app.route('/api/system')
@login_required
def api_system():
    """获取系统信息"""
    return jsonify(get_system_info())


@app.route('/api/services')
@login_required
def api_services():
    """获取服务状态"""
    services = {
        'telegram_files': get_service_status('docker'),
        'sync_service': get_service_status('telegram-files-sync'),
    }

    # 检查 Docker 容器
    try:
        result = subprocess.run(
            ['docker', 'ps', '--filter', 'name=telegram-files', '--format', '{{.Status}}'],
            capture_output=True,
            text=True,
            timeout=5
        )
        services['telegram_files']['docker_status'] = result.stdout.strip()
    except:
        services['telegram_files']['docker_status'] = 'Unknown'

    return jsonify(services)


@app.route('/api/sync/stats')
@login_required
def api_sync_stats():
    """获取同步统计"""
    return jsonify(get_sync_stats())


@app.route('/api/cloud/stats')
@login_required
def api_cloud_stats():
    """获取云端统计"""
    return jsonify(get_cloud_stats())


@app.route('/api/config')
@login_required
def api_config():
    """获取配置"""
    config = read_config()
    return jsonify(config)


@app.route('/api/logs/sync')
@login_required
def api_logs_sync():
    """获取同步日志"""
    lines = request.args.get('lines', 100, type=int)
    logs = parse_log_file(SYNC_LOG_FILE, max_lines=lines)
    return jsonify({'logs': logs})


@app.route('/api/logs/rclone')
@login_required
def api_logs_rclone():
    """获取 rclone 日志"""
    lines = request.args.get('lines', 100, type=int)
    logs = parse_log_file(RCLONE_LOG_FILE, max_lines=lines)
    return jsonify({'logs': logs})


@app.route('/api/dashboard')
@login_required
def api_dashboard():
    """获取仪表板所有数据"""
    return jsonify({
        'system': get_system_info(),
        'services': {
            'telegram_files': get_service_status('docker'),
            'sync_service': get_service_status('telegram-files-sync'),
        },
        'sync_stats': get_sync_stats(),
        'cloud_stats': get_cloud_stats(),
        'cloud_quota': get_cloud_quota(),
        'network_stats': get_network_stats(),
        'upload_progress': get_upload_progress(),
        'config': read_config(),
        'timestamp': datetime.now().isoformat()
    })


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
