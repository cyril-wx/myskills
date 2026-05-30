#!/bin/bash
# ============================================================
# LLM 远程自动化性能测试脚本
# 
# 功能：
#   - 自动 SSH 连接到远程服务器
#   - 启动/停止 llama-server
#   - 自动调优参数组合
#   - 执行性能测试
#   - 回收结果并汇总分析
#
# 远程配置：
#   SSH: cyril@192.168.66.65 (免密登录)
#   模型: /home/cyril/.lmstudio/models/.../Qwen3.6-27B-Omnimerge-v4-Q6_K.gguf
#   命令: /usr/local/bin/llama-server
#
# 用法: ./llm_bench_remote.sh [mode]
#   mode: quick|compare|scan|tune
#
# 作者: QwenPaw QA Agent
# 日期: 2026-05-30
# ============================================================

set -euo pipefail

# ==================== 全局配置 ====================
readonly SCRIPT_NAME="llm_bench_remote"
readonly VERSION="3.0.0"

# 远程服务器配置
REMOTE_HOST="${REMOTE_HOST:-192.168.66.65}"
REMOTE_USER="${REMOTE_USER:-cyril}"
REMOTE_SSH="${REMOTE_USER}@${REMOTE_HOST}"

# 远程路径配置
REMOTE_MODEL_PATH="/home/cyril/.lmstudio/models/ManniX-ITA/Qwen3.6-27B-Omnimerge-v4-MTP-GGUF/Qwen3.6-27B-Omnimerge-v4-Q6_K.gguf"
REMOTE_LLAMA_BIN="/usr/local/bin/llama-server"
REMOTE_WORK_DIR="/home/cyril/llm_bench"
REMOTE_RESULTS_DIR="${REMOTE_WORK_DIR}/results"

# 本地配置
LOCAL_WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_RESULTS_DIR="${LOCAL_WORK_DIR}/remote_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 服务器配置
SERVER_PORT="${SERVER_PORT:-8099}"
GPU_INFO="${GPU_INFO:-4090D-48GB}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ==================== 日志函数 ====================
log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
log_remote()  { echo -e "${BLUE}[REMOTE]${NC} $*"; }
log_test()    { echo -e "${MAGENTA}[TEST]${NC} $*"; }
log_result()  { echo -e "${BOLD}${GREEN}[RESULT]${NC} $*"; }

# ==================== 工具函数 ====================

# 执行远程命令
ssh_exec() {
    ssh "${REMOTE_SSH}" "$@"
}

# 检查远程命令是否存在
ssh_check_cmd() {
    ssh_exec "command -v $1 &>/dev/null"
}

# 安全清理远程进程
ssh_cleanup_server() {
    log_remote "清理远程服务器进程..."
    ssh_exec "pkill -f 'llama-server.*--port ${SERVER_PORT}' || true"
    sleep 2
}

# ==================== 初始化 ====================
init_directories() {
    log_section "初始化目录结构"
    
    # 本地目录
    mkdir -p "${LOCAL_RESULTS_DIR}/${TIMESTAMP}"
    mkdir -p "${LOCAL_RESULTS_DIR}/${TIMESTAMP}/logs"
    mkdir -p "${LOCAL_RESULTS_DIR}/${TIMESTAMP}/csv"
    
    # 远程目录
    ssh_exec "mkdir -p ${REMOTE_WORK_DIR}"
    ssh_exec "mkdir -p ${REMOTE_RESULTS_DIR}"
    
    log_info "本地结果目录: ${LOCAL_RESULTS_DIR}/${TIMESTAMP}"
    log_info "远程工作目录: ${REMOTE_WORK_DIR}"
}

# ==================== 连接测试 ====================
test_ssh_connection() {
    log_section "测试 SSH 连接"
    
    log_info "目标: ${REMOTE_SSH}"
    
    if ssh_exec "echo 'SSH 连接成功'" &>/dev/null; then
        log_info "${GREEN}✓${NC} SSH 连接正常"
        return 0
    else
        log_error "SSH 连接失败"
        log_error "请确认已配置免密登录: ssh ${REMOTE_SSH}"
        return 1
    fi
}

check_remote_dependencies() {
    log_section "检查远程依赖"
    
    local missing=()
    
    # 检查 llama-server
    if ! ssh_check_cmd "llama-server" && ! ssh_exec "test -x ${REMOTE_LLAMA_BIN}"; then
        missing+=("llama-server (${REMOTE_LLAMA_BIN})")
    else
        log_info "${GREEN}✓${NC} llama-server: ${REMOTE_LLAMA_BIN}"
    fi
    
    # 检查模型文件
    if ! ssh_exec "test -f ${REMOTE_MODEL_PATH}"; then
        missing+=("模型文件 (${REMOTE_MODEL_PATH})")
    else
        local model_size=$(ssh_exec "du -h ${REMOTE_MODEL_PATH} | cut -f1")
        log_info "${GREEN}✓${NC} 模型文件: ${REMOTE_MODEL_PATH} (${model_size})"
    fi
    
    # 检查必要工具
    for cmd in curl jq bc; do
        if ! ssh_check_cmd "$cmd"; then
            missing+=("$cmd")
        else
            log_info "${GREEN}✓${NC} $cmd 已安装"
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "缺少依赖: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# ==================== 服务器管理 ====================

# 启动远程 llama-server
start_remote_server() {
    local ctx=$1
    local parallel=$2
    local batch=$3
    local ubatch=$4
    local cache_k=$5
    local cache_v=$6
    local spec_draft=$7
    local reasoning_budget=$8
    
    log_section "启动远程 llama-server"
    log_remote "配置: ctx=${ctx}, parallel=${parallel}, batch=${batch}, ubatch=${ubatch}"
    log_remote "缓存: K=${cache_k}, V=${cache_v}, MTP=${spec_draft}, budget=${reasoning_budget}"
    
    # 先清理可能存在的进程
    ssh_cleanup_server
    
    # 启动命令
    local start_cmd="${REMOTE_LLAMA_BIN} \
        -m ${REMOTE_MODEL_PATH} \
        -c ${ctx} \
        -ngl 99 \
        --parallel ${parallel} \
        --batch-size ${batch} \
        --ubatch-size ${ubatch} \
        --cache-type-k ${cache_k} \
        --cache-type-v ${cache_v} \
        --reasoning-format deepseek \
        --reasoning-budget ${reasoning_budget} \
        --spec-type draft-mtp \
        --spec-draft-n-max ${spec_draft} \
        --port ${SERVER_PORT} \
        --log-disable \
        > ${REMOTE_RESULTS_DIR}/server_${TIMESTAMP}.log 2>&1 &"
    
    # 执行
    ssh_exec "$start_cmd"
    
    log_info "等待服务器启动..."
    
    # 等待就绪
    local max_wait=60
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if ssh_exec "curl -s http://localhost:${SERVER_PORT}/health" &>/dev/null; then
            log_info "${GREEN}✓${NC} 服务器已就绪 (端口 ${SERVER_PORT})"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    log_error "服务器启动超时"
    log_remote "日志内容:"
    ssh_exec "tail -20 ${REMOTE_RESULTS_DIR}/server_${TIMESTAMP}.log" || true
    return 1
}

# 停止远程 llama-server
stop_remote_server() {
    log_remote "停止远程服务器..."
    ssh_cleanup_server
    log_info "${GREEN}✓${NC} 服务器已停止"
}

# ==================== 性能测试 ====================

# 在远程服务器执行单个测试
run_remote_test() {
    local test_id=$1
    local max_tokens=$2
    
    log_test "测试 #${test_id}: max_tokens=${max_tokens}"
    
    # 测试提示词
    local prompt="请详细解释快速排序算法的原理，包括时间复杂度、空间复杂度分析。然后给出一个完整的 Python 实现，包含类型注解和详细的中文注释。最后提供 3 个测试用例验证实现的正确性。"
    
    # 在远程执行测试
    local result_json=$(ssh_exec "curl -s --connect-timeout 30 --max-time 300 \
        -X POST \
        http://localhost:${SERVER_PORT}/v1/chat/completions \
        -H 'Content-Type: application/json' \
        -d '{
            \"model\": \"test\",
            \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}],
            \"max_tokens\": ${max_tokens},
            \"temperature\": 0.7,
            \"stream\": false
        }' 2>&1")
    
    # 解析结果
    local prompt_tokens=$(echo "$result_json" | ssh_exec "jq -r '.usage.prompt_tokens // 0'" 2>/dev/null || echo "0")
    local completion_tokens=$(echo "$result_json" | ssh_exec "jq -r '.usage.completion_tokens // 0'" 2>/dev/null || echo "0")
    local total_tokens=$(echo "$result_json" | ssh_exec "jq -r '.usage.total_tokens // 0'" 2>/dev/null || echo "0")
    
    echo "$result_json" | head -c 100
    echo ""
    
    log_result "tokens: prompt=${prompt_tokens}, completion=${completion_tokens}, total=${total_tokens}"
}

# 本地通过 SSH 执行测试（更可靠的方式）
run_test_via_local_ssh() {
    local test_id=$1
    local max_tokens=$2
    local config_json=$3
    
    log_test "测试 #${test_id}: max_tokens=${max_tokens}"
    
    # 测试提示词
    local prompt="请详细解释快速排序算法的原理，包括时间复杂度、空间复杂度分析。然后给出一个完整的 Python 实现，包含类型注解和详细的中文注释。"
    
    # 通过 SSH 隧道访问远程 API（使用秒级时间戳，兼容 macOS）
    local start_time=$(date +%s)
    
    local result=$(ssh_exec "curl -s --connect-timeout 30 --max-time 300 \
        -X POST \
        http://localhost:${SERVER_PORT}/v1/chat/completions \
        -H 'Content-Type: application/json' \
        -d '{
            \"model\": \"test\",
            \"messages\": [{\"role\": \"user\", \"content\": \"${prompt}\"}],
            \"max_tokens\": ${max_tokens},
            \"temperature\": 0.7,
            \"stream\": false
        }' 2>&1")
    
    local end_time=$(date +%s)
    local total_time_ms=$(( (end_time - start_time) * 1000 ))
    
    # 解析结果（在远程执行 jq）
    local prompt_tokens=$(echo "$result" | ssh_exec "jq -r '.usage.prompt_tokens // 0'" 2>/dev/null || echo "0")
    local completion_tokens=$(echo "$result" | ssh_exec "jq -r '.usage.completion_tokens // 0'" 2>/dev/null || echo "0")
    local total_tokens=$(echo "$result" | ssh_exec "jq -r '.usage.total_tokens // 0'" 2>/dev/null || echo "0")
    
    # 计算吞吐量
    local tok_per_sec="0"
    if [ "$total_time_ms" -gt 0 ] && [ "$completion_tokens" -gt 0 ] 2>/dev/null; then
        tok_per_sec=$(echo "scale=2; $completion_tokens / ($total_time_ms / 1000)" | bc)
    fi
    
    log_result "生成: ${completion_tokens} tok | 吞吐: ${tok_per_sec} tok/s | 延迟: ${total_time_ms}ms"
    
    # 返回结果
    echo "${test_id},${max_tokens},${prompt_tokens},${completion_tokens},${total_tokens},${total_time_ms},${tok_per_sec}"
}

# ==================== 测试模式 ====================

# 快速测试模式
mode_quick() {
    log_section "快速测试模式"
    log_info "预计耗时: 3-5 分钟"
    
    # 初始化 CSV
    local csv_file="${LOCAL_RESULTS_DIR}/${TIMESTAMP}/csv/quick_results.csv"
    echo "config_id,ctx,parallel,batch,cache_k,cache_v,spec_draft,max_tokens,prompt_tokens,completion_tokens,total_tokens,time_ms,tok_per_sec" > "$csv_file"
    
    # 测试配置：默认推荐配置
    local ctx=32768
    local parallel=2
    local batch=2048
    local ubatch=512
    local cache_k="q8_0"
    local cache_v="q8_0"
    local spec_draft=3
    local reasoning_budget=8192
    
    # 启动服务器
    if ! start_remote_server "$ctx" "$parallel" "$batch" "$ubatch" "$cache_k" "$cache_v" "$spec_draft" "$reasoning_budget"; then
        log_error "服务器启动失败，跳过测试"
        return 1
    fi
    
    # 执行测试
    local test_id=1
    for max_tokens in 256 512 1024; do
        local result=$(run_test_via_local_ssh "$test_id" "$max_tokens" "")
        echo "${result}" >> "$csv_file"
        ((test_id++))
        sleep 2
    done
    
    # 停止服务器
    stop_remote_server
    
    log_info "快速测试完成"
    log_info "结果保存到: ${csv_file}"
}

# 对比测试模式
mode_compare() {
    log_section "对比测试模式"
    log_info "测试 5 种配置组合进行对比"
    
    # 初始化 CSV
    local csv_file="${LOCAL_RESULTS_DIR}/${TIMESTAMP}/csv/compare_results.csv"
    echo "config_id,name,ctx,parallel,batch,cache_k,cache_v,spec_draft,max_tokens,prompt_tokens,completion_tokens,total_tokens,time_ms,tok_per_sec" > "$csv_file"
    
    # 配置列表: name, ctx, parallel, batch, ubatch, cache_k, cache_v, spec_draft, budget
    local configs=(
        "默认配置|32768|2|2048|512|q8_0|q8_0|3|8192"
        "轻量配置|16384|1|1024|256|q8_0|q8_0|3|4096"
        "大上下文|65536|4|4096|512|q8_0|q8_0|5|16384"
        "高吞吐|32768|8|4096|1024|q8_0|q8_0|8|8192"
        "高精度|32768|2|2048|512|f16|f16|3|8192"
    )
    
    local test_id=1
    local max_tokens=512
    
    for config in "${configs[@]}"; do
        IFS='|' read -r name ctx parallel batch ubatch cache_k cache_v spec_draft budget <<< "$config"
        
        log_info "\n━━━ 配置 ${test_id}: ${name} ━━━"
        log_remote "ctx=${ctx}, parallel=${parallel}, batch=${batch}, spec_draft=${spec_draft}"
        
        # 启动服务器
        if ! start_remote_server "$ctx" "$parallel" "$batch" "$ubatch" "$cache_k" "$cache_v" "$spec_draft" "$budget"; then
            log_warn "配置 ${test_id} 启动失败，跳过"
            ((test_id++))
            continue
        fi
        
        sleep 3  # 等待稳定
        
        # 执行测试
        local result=$(run_test_via_local_ssh "${test_id}" "$max_tokens" "")
        
        # 保存结果
        echo "${result},${name}" | awk -F',' 'BEGIN{OFS=","} {print $1,$NF,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13}' >> "$csv_file"
        
        # 停止服务器
        stop_remote_server
        
        ((test_id++))
        sleep 5  # 冷却时间
    done
    
    log_info "对比测试完成"
    log_info "结果保存到: ${csv_file}"
}

# 自动调优模式
mode_tune() {
    log_section "自动调优模式"
    log_warn "此模式将测试多种参数组合，预计耗时 20-40 分钟"
    
    # 初始化 CSV
    local csv_file="${LOCAL_RESULTS_DIR}/${TIMESTAMP}/csv/tune_results.csv"
    echo "config_id,ctx,parallel,batch,ubatch,cache_k,cache_v,spec_draft,budget,max_tokens,prompt_tokens,completion_tokens,total_tokens,time_ms,tok_per_sec" > "$csv_file"
    
    # 参数搜索空间
    local ctx_values=(16384 32768 65536)
    local parallel_values=(2 4 8)
    local batch_values=(1024 2048 4096)
    
    local test_id=1
    local max_tokens=512
    local ubatch=512
    local cache_k="q8_0"
    local cache_v="q8_0"
    local spec_draft=3
    local budget=8192
    
    # 计算总测试数
    local total_tests=$((${#ctx_values[@]} * ${#parallel_values[@]} * ${#batch_values[@]}))
    log_info "共 ${total_tests} 种配置组合"
    
    for ctx in "${ctx_values[@]}"; do
        for parallel in "${parallel_values[@]}"; do
            for batch in "${batch_values[@]}"; do
                log_info "\n━━━ 测试 ${test_id}/${total_tests} ━━━"
                log_remote "ctx=${ctx}, parallel=${parallel}, batch=${batch}"
                
                # 启动服务器
                if ! start_remote_server "$ctx" "$parallel" "$batch" "$ubatch" "$cache_k" "$cache_v" "$spec_draft" "$budget"; then
                    log_warn "配置 ${test_id} 启动失败，跳过"
                    ((test_id++))
                    continue
                fi
                
                sleep 3
                
                # 执行测试
                local result=$(run_test_via_local_ssh "${test_id}" "$max_tokens" "")
                
                # 保存结果
                echo "${test_id},${ctx},${parallel},${batch},${ubatch},${cache_k},${cache_v},${spec_draft},${budget},${result}" >> "$csv_file"
                
                # 停止服务器
                stop_remote_server
                
                ((test_id++))
                sleep 5  # 冷却时间
            done
        done
    done
    
    log_info "自动调优完成"
    log_info "结果保存到: ${csv_file}"
}

# 完整扫描模式
mode_scan() {
    log_section "完整扫描模式"
    log_warn "此模式将进行深度参数扫描，预计耗时 60-120 分钟"
    log_warn "建议使用 nohup 或 tmux 运行"
    
    # 简化为调优模式
    mode_tune
}

# ==================== 结果分析 ====================

# 收集远程结果
collect_results() {
    log_section "收集远程结果"
    
    # 同步远程日志
    log_remote "传输服务器日志..."
    scp -q "${REMOTE_SSH}:${REMOTE_RESULTS_DIR}/server_${TIMESTAMP}.log" \
        "${LOCAL_RESULTS_DIR}/${TIMESTAMP}/logs/" 2>/dev/null || true
    
    # 列出远程结果文件
    log_remote "检查远程结果文件..."
    ssh_exec "ls -la ${REMOTE_RESULTS_DIR}/" 2>/dev/null || true
}

# 生成分析报告
generate_analysis() {
    log_section "生成分析报告"
    
    local report_file="${LOCAL_RESULTS_DIR}/${TIMESTAMP}/analysis_report.txt"
    local json_file="${LOCAL_RESULTS_DIR}/${TIMESTAMP}/summary.json"
    
    # 查找结果 CSV
    local csv_file=$(find "${LOCAL_RESULTS_DIR}/${TIMESTAMP}/csv" -name "*.csv" -type f 2>/dev/null | head -1)
    
    if [ -z "$csv_file" ] || [ ! -f "$csv_file" ]; then
        log_warn "未找到结果文件，跳过分析"
        return
    fi
    
    log_info "分析文件: ${csv_file}"
    
    # 统计数据
    local total_tests=$(tail -n +2 "$csv_file" | wc -l | tr -d ' ')
    local successful_tests=$(tail -n +2 "$csv_file" | awk -F',' '$13 > 0' | wc -l | tr -d ' ')
    
    # 平均吞吐量
    local avg_tps=$(tail -n +2 "$csv_file" | awk -F',' '$13 > 0 {sum+=$13; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
    
    # 最大吞吐量
    local max_tps=$(tail -n +2 "$csv_file" | awk -F',' '$13 > 0 {print $13}' | sort -rn | head -1)
    
    # 最佳配置
    local best_config=$(tail -n +2 "$csv_file" | awk -F',' '$13 > 0 {print $0}' | sort -t',' -k13 -rn | head -1)
    
    # 生成报告
    {
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  LLM 远程性能测试分析报告"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "远程服务器: ${REMOTE_SSH}"
        echo "硬件: ${GPU_INFO}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  测试统计"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "总测试数: ${total_tests}"
        echo "成功测试: ${successful_tests}"
        echo "平均吞吐量: ${avg_tps} tok/s"
        echo "最大吞吐量: ${max_tps} tok/s"
        echo ""
        
        if [ -n "$best_config" ]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  最佳配置"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "$best_config" | awk -F',' '{
                printf "配置 ID: %s\n", $1
                if (NF >= 14) {
                    printf "配置名称: %s\n", $14
                }
                printf "ctx=%s, parallel=%s, batch=%s\n", $2, $3, $4
                printf "吞吐量: %s tok/s\n", $13
                printf "生成 tokens: %s\n", $11
                printf "延迟: %s ms\n", $12
            }'
            echo ""
        fi
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  针对 4090D 48GB 的优化建议"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "基于测试结果，推荐以下启动参数："
        echo ""
        echo "${REMOTE_LLAMA_BIN} \\"
        echo "    -m ${REMOTE_MODEL_PATH} \\"
        echo "    -c 32768 \\"
        echo "    -ngl 99 \\"
        echo "    --parallel 4 \\"
        echo "    --batch-size 4096 \\"
        echo "    --ubatch-size 512 \\"
        echo "    --cache-type-k q8_0 \\"
        echo "    --cache-type-v q8_0 \\"
        echo "    --reasoning-format deepseek \\"
        echo "    --reasoning-budget 8192 \\"
        echo "    --spec-type draft-mtp \\"
        echo "    --spec-draft-n-max 3 \\"
        echo "    --port ${SERVER_PORT}"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  详细结果"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "CSV 文件: ${csv_file}"
        echo ""
        
    } > "$report_file"
    
    # 生成 JSON 摘要
    cat > "$json_file" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "remote_host": "${REMOTE_HOST}",
  "hardware": "${GPU_INFO}",
  "summary": {
    "total_tests": ${total_tests},
    "successful_tests": ${successful_tests},
    "avg_tokens_per_sec": ${avg_tps:-0},
    "max_tokens_per_sec": ${max_tps:-0}
  },
  "remote_paths": {
    "model": "${REMOTE_MODEL_PATH}",
    "llama_server": "${REMOTE_LLAMA_BIN}",
    "work_dir": "${REMOTE_WORK_DIR}"
  }
}
EOF
    
    # 显示报告
    cat "$report_file"
    
    log_info "报告已保存到: ${report_file}"
    log_info "JSON 摘要已保存到: ${json_file}"
}

# ==================== 清理 ====================
cleanup() {
    log_warn "收到中断信号，正在清理..."
    stop_remote_server
    log_info "清理完成"
    exit 1
}

# ==================== 主流程 ====================
show_usage() {
    cat << EOF
用法: $0 [mode]

模式:
  quick     快速测试 (3-5 分钟，测试关键配置)
  compare   对比测试 (10-15 分钟，对比 5 种配置)
  tune      自动调优 (20-40 分钟，寻找最优配置)
  scan      完整扫描 (60-120 分钟，深度优化)

环境变量:
  REMOTE_HOST    远程服务器 IP (默认: 192.168.66.65)
  REMOTE_USER    远程用户名 (默认: cyril)
  SERVER_PORT    服务器端口 (默认: 8099)
  GPU_INFO       GPU 信息 (默认: 4090D-48GB)

远程配置:
  SSH:        ${REMOTE_USER}@${REMOTE_HOST}
  模型路径:   ${REMOTE_MODEL_PATH}
  命令路径:   ${REMOTE_LLAMA_BIN}

示例:
  # 快速测试
  $0 quick

  # 对比测试
  $0 compare

  # 自动调优
  $0 tune

  # 后台运行完整扫描
  nohup $0 scan > scan.log 2>&1 &
EOF
}

main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════╗"
    echo "║   LLM Remote Auto-Tuning Script         ║"
    echo "║   Qwen3.6-27B @ 4090D 48GB (Remote)     ║"
    echo "║   Version ${VERSION}                           ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # 设置清理陷阱
    trap cleanup INT TERM
    
    # 检查参数
    local mode="${1:-quick}"
    
    if [ "$mode" = "-h" ] || [ "$mode" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    # 初始化
    init_directories
    
    # 连接测试
    if ! test_ssh_connection; then
        exit 1
    fi
    
    # 依赖检查
    if ! check_remote_dependencies; then
        exit 1
    fi
    
    # 执行测试
    case "$mode" in
        quick)
            mode_quick
            ;;
        compare)
            mode_compare
            ;;
        tune)
            mode_tune
            ;;
        scan)
            mode_scan
            ;;
        *)
            log_error "未知模式: $mode"
            show_usage
            exit 1
            ;;
    esac
    
    # 收集结果
    collect_results
    
    # 生成分析
    generate_analysis
    
    log_section "测试完成"
    log_info "所有结果已保存到: ${LOCAL_RESULTS_DIR}/${TIMESTAMP}"
}

# 执行主程序
main "$@"