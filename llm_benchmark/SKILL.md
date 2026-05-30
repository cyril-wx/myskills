---
name: llm_benchmark
description: "LLM 性能测试与调优技能。支持远程 SSH 自动化测试、参数扫描、结果分析。适用于 llama.cpp/llama-server 的性能基准测试。"
metadata:
  builtin_skill_version: "1.0"
  qwenpaw:
    emoji: "⚡"
    requires:
      - bash
      - ssh
      - curl
      - jq
      - bc
---

# LLM 性能测试与调优

针对 **llama.cpp/llama-server** 的性能基准测试技能，支持远程 SSH 自动化测试、参数扫描、结果分析与报告生成。

## 功能特点

- ✅ **远程测试**：通过 SSH 自动连接远程服务器
- ✅ **自动调优**：智能参数组合扫描
- ✅ **MTP 优化**：投机解码性能测试
- ✅ **报告生成**：完整的测试报告和优化建议
- ✅ **极限探索**：自动探索硬件极限配置

## 使用场景

| 场景 | 命令示例 |
|------|----------|
| 快速测试 | `./llm_bench_remote.sh quick` |
| 对比测试 | `./llm_bench_remote.sh compare` |
| 自动调优 | `./llm_bench_remote.sh tune` |
| 完整扫描 | `./llm_bench_remote.sh scan` |

## 测试流程

### 1. 环境准备

确保远程服务器满足以下条件：

```bash
# SSH 免密登录已配置
ssh user@remote_host "echo OK"

# llama-server 可用
which llama-server

# 模型文件存在
ls -la /path/to/model.gguf

# 依赖工具已安装
curl --version && jq --version && bc --version
```

### 2. 配置参数

编辑脚本顶部的配置区域：

```bash
# 远程服务器
REMOTE_HOST="192.168.66.65"
REMOTE_USER="cyril"

# 模型路径
REMOTE_MODEL_PATH="/path/to/model.gguf"
REMOTE_LLAMA_BIN="/usr/local/bin/llama-server"

# 服务器端口
SERVER_PORT="8099"
```

### 3. 执行测试

```bash
# 快速测试 (3-5分钟)
./llm_bench_remote.sh quick

# 对比测试 (10-15分钟)
./llm_bench_remote.sh compare

# 自动调优 (20-40分钟)
./llm_bench_remote.sh tune
```

### 4. 查看结果

测试完成后，结果保存在 `remote_results/[timestamp]/` 目录：

```
remote_results/20260530_020000/
├── csv/
│   └── *_results.csv       # 详细测试数据
├── logs/
│   └── server_*.log        # 服务器日志
├── analysis_report.txt     # 分析报告
└── summary.json            # JSON 摘要
```

## 参数优化指南

### llama-server 核心参数

| 参数 | 说明 | 推荐值 |
|------|------|--------|
| `-c` | 上下文大小 | 32768 |
| `--parallel` | 并行解码数 | 4 |
| `--batch-size` | 批处理大小 | 4096 |
| `--ubatch-size` | 微批大小 | 1024 |
| `--cache-type-k/v` | KV 缓存类型 | q8_0 |
| `--spec-type` | 投机解码类型 | draft-mtp |
| `--spec-draft-n-max` | 投机猜测数 | 3-5 |
| `-ngl` | GPU 层数 | 99 (全部) |

### 不同场景推荐

#### 最大吞吐量配置

```bash
llama-server -m model.gguf \
    -c 32768 -ngl 99 \
    --parallel 4 \
    --batch-size 4096 \
    --ubatch-size 1024 \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --spec-type draft-mtp --spec-draft-n-max 5 \
    --port 8099
```

#### 最低延迟配置

```bash
llama-server -m model.gguf \
    -c 16384 -ngl 99 \
    --parallel 2 \
    --batch-size 2048 \
    --ubatch-size 512 \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --spec-type draft-mtp --spec-draft-n-max 3 \
    --port 8099
```

#### 大上下文配置

```bash
llama-server -m model.gguf \
    -c 65536 -ngl 99 \
    --parallel 4 \
    --batch-size 4096 \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --spec-type draft-mtp --spec-draft-n-max 5 \
    --port 8099
```

## 性能指标说明

| 指标 | 英文名 | 说明 |
|------|--------|------|
| 吞吐量 | tokens/s | 每秒生成的 token 数，越高越好 |
| TTFT | Time To First Token | 首 token 延迟，越低越好 |
| 显存占用 | VRAM Usage | GPU 显存使用量 |
| 并发能力 | Concurrency | 同时处理请求数 |

## 常见问题

### Q: 吞吐量达不到预期？

检查以下几点：
1. **spec_draft_n_max** 是否过小或过大（推荐 3-5）
2. **parallel** 是否设置合理（推荐 4）
3. **batch_size** 是否足够大（推荐 4096）
4. 是否启用了 **MTP 投机解码**

### Q: 显存不足？

尝试以下优化：
1. 减小 `-c` 上下文大小
2. 降低 `--batch-size`
3. 使用 `q4_0` 或 `q8_0` 缓存
4. 减少 `--parallel`

### Q: MTP 不生效？

确保：
1. 模型是 MTP 版本（带 MTP 抬头）
2. llama.cpp 版本支持 MTP（PR #22673+）
3. `--spec-type draft-mtp` 参数正确

## 长上下文配置

### 128K 上下文 (长文档处理)

```bash
llama-server -m model.gguf \
    -c 131072 -ngl 99 \
    --parallel 2 --batch-size 512 --ubatch-size 128 \
    --cache-type-k q4_0 --cache-type-v q4_0 \
    --spec-type draft-mtp --spec-draft-n-max 3 \
    --port 8099
```

**显存**: ~25GB | **吞吐量**: ~72 tok/s | **支持输入**: ~55K tokens

### 200K-256K 上下文 (超长文档)

```bash
llama-server -m model.gguf \
    -c 262144 -ngl 99 \
    --parallel 2 --batch-size 512 --ubatch-size 128 \
    --cache-type-k q4_0 --cache-type-v q4_0 \
    --spec-type draft-mtp --spec-draft-n-max 3 \
    --port 8099
```

**显存**: ~27GB | **吞吐量**: ~72 tok/s

### 缓存类型选择

| 缓存类型 | 显存/K | 适用场景 |
|----------|--------|----------|
| q8_0 | ~0.64 MB/K | 32K 以下，质量最优 |
| q4_0 | ~0.11 MB/K | 128K-256K，节省显存 |

### 超长输入处理

| 输入规模 | 处理时间建议 |
|----------|-------------|
| < 10K chars | 正常处理 (< 15s) |
| 10K-40K chars | 可接受 (15-40s) |
| 40K-80K chars | 建议分段 (40-75s) |
| > 80K chars | 强烈建议分段或摘要 (> 75s) |

## 测试最佳实践

1. **首次测试**：使用 `quick` 模式快速验证环境
2. **性能调优**：使用 `tune` 模式自动寻找最优配置
3. **极限探索**：手动调整参数探索极限
4. **长期监控**：定期运行 `compare` 模式对比性能

## 文件清单

| 文件 | 说明 |
|------|------|
| `llm_bench_remote.sh` | 远程自动化测试脚本 |
| `llm_bench_optimized.sh` | 本地 API 测试脚本 |
| `templates/report.md` | 报告模板 |
| `examples/` | 示例配置和脚本 |

## 版本历史
- Github: https://github.com/cyril-wx/myskills/upload/main
- v1.0 (2026-05-30): 初始版本
  - 支持远程 SSH 测试
  - 自动参数调优
  - MTP 性能测试
  - 报告自动生成