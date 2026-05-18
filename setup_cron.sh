#!/bin/bash
#
# 安装/卸载 Agent Platform 定时开关的 cron job
# 用法：
#   ./setup_cron.sh install   # 安装 cron job
#   ./setup_cron.sh uninstall # 卸载 cron job
#   ./setup_cron.sh status    # 查看当前 cron 状态
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOGGLE_SCRIPT="${SCRIPT_DIR}/vertex_ai_toggle.sh"
CRON_TAG="# AGENT_PLATFORM_SCHEDULER"
LEGACY_CRON_TAG="# VERTEX_AI_SCHEDULER"

# ============================================================
# 配置区域 - 根据实际情况修改
# ============================================================

# GCP Project ID（必须修改）
PROJECT_ID="${AGENT_PLATFORM_PROJECT_ID:-${VERTEX_PROJECT_ID:-your-project-id-here}}"

# 晚上关闭的 cron 时间（整点触发，脚本内部再随机延迟 0-30 分钟）
# 默认：每天晚上 7 点（19:00）触发，实际执行时间在 19:00-19:30 之间随机
DISABLE_CRON_HOUR=19
DISABLE_CRON_MIN=0

# 早上开启的 cron 时间
# 默认：每天早上 10 点（10:00）触发，实际执行时间在 10:00-10:30 之间随机
ENABLE_CRON_HOUR=10
ENABLE_CRON_MIN=0

# gcloud 路径（cron 环境下可能找不到 gcloud，需要指定完整路径）
GCLOUD_PATH=$(which gcloud 2>/dev/null)

# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

install_cron() {
    # 检查 Project ID
    if [[ "${PROJECT_ID}" == "your-project-id-here" ]]; then
        error "请先设置 PROJECT_ID："
        echo "  方式1: 编辑此脚本中的 PROJECT_ID"
        echo "  方式2: export AGENT_PLATFORM_PROJECT_ID=your-project-id"
        exit 1
    fi

    # 检查 toggle 脚本
    if [[ ! -f "${TOGGLE_SCRIPT}" ]]; then
        error "找不到 ${TOGGLE_SCRIPT}"
        exit 1
    fi

    # 确保脚本可执行
    chmod +x "${TOGGLE_SCRIPT}"

    # 获取 gcloud 所在目录，加入 PATH
    GCLOUD_DIR=""
    if [[ -n "${GCLOUD_PATH}" ]]; then
        GCLOUD_DIR="$(dirname "${GCLOUD_PATH}")"
    else
        # 常见 gcloud 安装路径
        for p in "$HOME/google-cloud-sdk/bin" "/usr/local/bin" "/usr/lib/google-cloud-sdk/bin" "/opt/homebrew/bin"; do
            if [[ -x "${p}/gcloud" ]]; then
                GCLOUD_DIR="${p}"
                break
            fi
        done
    fi

    if [[ -z "${GCLOUD_DIR}" ]]; then
        error "找不到 gcloud，请确认 Google Cloud SDK 已安装"
        exit 1
    fi

    info "gcloud 路径: ${GCLOUD_DIR}/gcloud"

    # 构建 cron 命令（设置 PATH 确保 cron 环境能找到 gcloud）
    DISABLE_CMD="${DISABLE_CRON_MIN} ${DISABLE_CRON_HOUR} * * * PATH=${GCLOUD_DIR}:\$PATH AGENT_PLATFORM_PROJECT_ID=${PROJECT_ID} ${TOGGLE_SCRIPT} disable ${CRON_TAG}_DISABLE"
    ENABLE_CMD="${ENABLE_CRON_MIN} ${ENABLE_CRON_HOUR} * * * PATH=${GCLOUD_DIR}:\$PATH AGENT_PLATFORM_PROJECT_ID=${PROJECT_ID} ${TOGGLE_SCRIPT} enable ${CRON_TAG}_ENABLE"

    # 先移除旧的 cron job（如果有）
    EXISTING_CRON=$(crontab -l 2>/dev/null || true)
    NEW_CRON=$(echo "${EXISTING_CRON}" | grep -v "${CRON_TAG}" | grep -v "${LEGACY_CRON_TAG}" || true)

    # 添加新的 cron job
    if [[ -n "${NEW_CRON}" ]]; then
        NEW_CRON="${NEW_CRON}
${DISABLE_CMD}
${ENABLE_CMD}"
    else
        NEW_CRON="${DISABLE_CMD}
${ENABLE_CMD}"
    fi

    echo "${NEW_CRON}" | crontab -

    info "✅ Cron job 已安装！"
    echo ""
    echo "  📋 配置详情："
    echo "  ├── 项目:     ${PROJECT_ID}"
    echo "  ├── 晚上关闭: ${DISABLE_CRON_HOUR}:$(printf '%02d' ${DISABLE_CRON_MIN}) 触发, 随机延迟 0-60 分钟后执行"
    echo "  ├── 早上开启: ${ENABLE_CRON_HOUR}:$(printf '%02d' ${ENABLE_CRON_MIN}) 触发, 随机延迟 0-60 分钟后执行"
    echo "  ├── 日志文件: ${SCRIPT_DIR}/logs/agent_platform_toggle.log"
    echo "  └── gcloud:   ${GCLOUD_DIR}/gcloud"
    echo ""
    echo "  🔍 查看 cron: crontab -l | grep AGENT_PLATFORM"
    echo "  🗑️  卸载:      $0 uninstall"
}

uninstall_cron() {
    EXISTING_CRON=$(crontab -l 2>/dev/null || true)

    if echo "${EXISTING_CRON}" | grep -q -e "${CRON_TAG}" -e "${LEGACY_CRON_TAG}"; then
        NEW_CRON=$(echo "${EXISTING_CRON}" | grep -v "${CRON_TAG}" | grep -v "${LEGACY_CRON_TAG}")
        if [[ -n "${NEW_CRON}" ]]; then
            echo "${NEW_CRON}" | crontab -
        else
            crontab -r 2>/dev/null || true
        fi
        info "✅ Cron job 已卸载"
    else
        warn "未找到已安装的 Agent Platform cron job"
    fi
}

show_status() {
    echo "📋 当前 Agent Platform 相关 cron job："
    echo ""
    JOBS=$(crontab -l 2>/dev/null | grep -e "${CRON_TAG}" -e "${LEGACY_CRON_TAG}" || true)
    if [[ -n "${JOBS}" ]]; then
        echo "${JOBS}" | while read -r line; do
            echo "  ${line}"
        done
    else
        echo "  (无)"
    fi

    echo ""
    echo "📊 最近日志："
    LOG="${SCRIPT_DIR}/logs/agent_platform_toggle.log"
    if [[ -f "${LOG}" ]]; then
        tail -10 "${LOG}" | while read -r line; do
            echo "  ${line}"
        done
    else
        echo "  (无日志)"
    fi
}

# 主逻辑
case "${1}" in
    install)
        install_cron
        ;;
    uninstall)
        uninstall_cron
        ;;
    status)
        show_status
        ;;
    *)
        echo "用法: $0 {install|uninstall|status}"
        echo ""
        echo "  install   - 安装 cron job (晚关早开)"
        echo "  uninstall - 卸载 cron job"
        echo "  status    - 查看当前状态和最近日志"
        exit 1
        ;;
esac
