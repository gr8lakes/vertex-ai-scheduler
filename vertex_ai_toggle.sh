#!/bin/bash
#
# Agent Platform 定时开关脚本
# 功能：在指定时间窗口内随机选择一个时间点 enable/disable Agent Platform API
# 用法：
#   ./vertex_ai_toggle.sh enable   # 随机延迟后启用
#   ./vertex_ai_toggle.sh disable  # 随机延迟后禁用
#
# ============================================================
# 配置区域 - 根据实际情况修改
# ============================================================

# GCP Project ID（必须修改）
PROJECT_ID="${AGENT_PLATFORM_PROJECT_ID:-${VERTEX_PROJECT_ID:-zm-vertexai-test01}}"

# 随机延迟窗口（分钟）- 在 0 到 MAX_DELAY_MINUTES 之间随机等待
# cron 在整点触发，脚本会随机延迟 0-30 分钟再执行
MAX_DELAY_MINUTES=30

# Agent Platform API 服务名
SERVICE_NAME="aiplatform.googleapis.com"

# 日志文件
LOG_DIR="$(dirname "$0")/logs"
LOG_FILE="${LOG_DIR}/agent_platform_toggle.log"

# ============================================================
# 逻辑区域
# ============================================================

mkdir -p "${LOG_DIR}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*" | tee -a "${LOG_FILE}"
}

# 参数检查
ACTION="$1"
if [[ "${ACTION}" != "enable" && "${ACTION}" != "disable" ]]; then
    echo "用法: $0 {enable|disable}"
    echo "  enable  - 随机延迟后启用 Agent Platform API"
    echo "  disable - 随机延迟后禁用 Agent Platform API"
    exit 1
fi

# 检查 Project ID
if [[ "${PROJECT_ID}" == "your-project-id-here" ]]; then
    log "❌ 错误: 请先设置 PROJECT_ID 或环境变量 AGENT_PLATFORM_PROJECT_ID"
    exit 1
fi

# 检查 gcloud 是否可用
if ! command -v gcloud &> /dev/null; then
    log "❌ 错误: gcloud CLI 未安装或不在 PATH 中"
    exit 1
fi

# 生成随机延迟（0 到 MAX_DELAY_MINUTES 分钟）
DELAY_MINUTES=$((RANDOM % MAX_DELAY_MINUTES))
DELAY_SECONDS=$((DELAY_MINUTES * 60))

log "🎲 计划在 ${DELAY_MINUTES} 分钟后执行 ${ACTION} (项目: ${PROJECT_ID})"

# 等待随机时间
sleep "${DELAY_SECONDS}"

log "⏳ 开始执行: gcloud services ${ACTION} ${SERVICE_NAME} --project=${PROJECT_ID}"

# 执行 enable/disable
if [[ "${ACTION}" == "disable" ]]; then
    # disable 需要 --force 跳过确认
    OUTPUT=$(gcloud services disable "${SERVICE_NAME}" \
        --project="${PROJECT_ID}" \
        --force \
        2>&1)
else
    OUTPUT=$(gcloud services enable "${SERVICE_NAME}" \
        --project="${PROJECT_ID}" \
        2>&1)
fi

EXIT_CODE=$?

if [[ ${EXIT_CODE} -eq 0 ]]; then
    log "✅ 成功: Agent Platform API 已 ${ACTION} (项目: ${PROJECT_ID})"
else
    log "❌ 失败 (exit code: ${EXIT_CODE}): ${OUTPUT}"
fi

# 验证当前状态
log "🔍 验证 API 状态..."
STATUS=$(gcloud services list --project="${PROJECT_ID}" \
    --filter="config.name=${SERVICE_NAME}" \
    --format="value(config.name)" 2>&1)

if [[ -n "${STATUS}" ]]; then
    log "📊 当前状态: Agent Platform API 已启用"
else
    log "📊 当前状态: Agent Platform API 已禁用"
fi

log "---"
