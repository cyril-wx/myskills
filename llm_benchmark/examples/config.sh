#!/bin/bash
# ============================================================
# LLM 性能测试配置示例
# ============================================================

# ==================== 远程服务器配置 ====================
REMOTE_HOST="${REMOTE_HOST:-192.168.66.65}"
REMOTE_USER="${REMOTE_USER:-cyril}"
SERVER_PORT="${SERVER_PORT:-8099}"

# ==================== 模型配置 ====================
REMOTE_MODEL_PATH="${REMOTE_MODEL_PATH:-/home/cyril/.lmstudio/models/ManniX-ITA/Qwen3.6-27B-Omnimerge-v4-MTP-GGUF/Qwen3.6-27B-Omnimerge-v4-Q6_K.gguf}"
REMOTE_LLAMA_BIN="${REMOTE_LLAMA_BIN:-/usr/local/bin/llama-server}"

# ==================== 测试参数配置 ====================

# 基础配置
CTX_SIZE="${CTX_SIZE:-32768}"
PARALLEL="${PARALLEL:-2}"
BATCH_SIZE="${BATCH_SIZE:-2048}"
UBATCH_SIZE="${UBATCH_SIZE:-512}"
CACHE_TYPE_K="${CACHE_TYPE_K:-q8_0}"
CACHE_TYPE_V="${CACHE_TYPE_V:-q8_0}"

# MTP 投机解码配置
SPEC_TYPE="${SPEC_TYPE:-draft-mtp}"
SPEC_DRAFT_N_MAX="${SPEC_DRAFT_N_MAX:-3}"

# 推理配置
REASONING_FORMAT="${REASONING_FORMAT:-deepseek}"
REASONING_BUDGET="${REASONING_BUDGET:-8192}"

# ==================== 预设配置方案 ====================

# 方案1: 最大吞吐量
preset_max_throughput() {
    CTX_SIZE=32768
    PARALLEL=4
    BATCH_SIZE=4096
    UBATCH_SIZE=1024
    SPEC_DRAFT_N_MAX=5
}

# 方案2: 最低延迟
preset_min_latency() {
    CTX_SIZE=16384
    PARALLEL=2
    BATCH_SIZE=1024
    UBATCH_SIZE=256
    SPEC_DRAFT_N_MAX=3
}

# 方案3: 大上下文
preset_large_context() {
    CTX_SIZE=65536
    PARALLEL=4
    BATCH_SIZE=4096
    UBATCH_SIZE=1024
    SPEC_DRAFT_N_MAX=5
}

# 方案4: 节省显存
preset_low_memory() {
    CTX_SIZE=16384
    PARALLEL=2
    BATCH_SIZE=1024
    UBATCH_SIZE=256
    SPEC_DRAFT_N_MAX=3
}

# 方案5: 长上下文 128K
preset_long_context_128k() {
    CTX_SIZE=131072
    PARALLEL=2
    BATCH_SIZE=512
    UBATCH_SIZE=128
    CACHE_TYPE_K="q4_0"
    CACHE_TYPE_V="q4_0"
    SPEC_DRAFT_N_MAX=3
}

# 方案6: 长上下文 200K
preset_long_context_200k() {
    CTX_SIZE=204800
    PARALLEL=2
    BATCH_SIZE=512
    UBATCH_SIZE=128
    CACHE_TYPE_K="q4_0"
    CACHE_TYPE_V="q4_0"
    SPEC_DRAFT_N_MAX=3
}

# 方案7: 长上下文 256K
preset_long_context_256k() {
    CTX_SIZE=262144
    PARALLEL=2
    BATCH_SIZE=512
    UBATCH_SIZE=128
    CACHE_TYPE_K="q4_0"
    CACHE_TYPE_V="q4_0"
    SPEC_DRAFT_N_MAX=3
}

# ==================== 生成启动命令 ====================
generate_server_command() {
    echo "${REMOTE_LLAMA_BIN} \\
    -m ${REMOTE_MODEL_PATH} \\
    -c ${CTX_SIZE} \\
    -ngl 99 \\
    --parallel ${PARALLEL} \\
    --batch-size ${BATCH_SIZE} \\
    --ubatch-size ${UBATCH_SIZE} \\
    --cache-type-k ${CACHE_TYPE_K} \\
    --cache-type-v ${CACHE_TYPE_V} \\
    --reasoning-format ${REASONING_FORMAT} \\
    --reasoning-budget ${REASONING_BUDGET} \\
    --spec-type ${SPEC_TYPE} \\
    --spec-draft-n-max ${SPEC_DRAFT_N_MAX} \\
    --port ${SERVER_PORT}"
}

# 使用示例:
# source config.sh
# preset_max_throughput
# generate_server_command