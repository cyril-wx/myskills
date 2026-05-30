# LLM Performance Benchmark Skill

针对 llama.cpp/llama-server 的性能基准测试技能包。

## 📦 内容

```
llm_benchmark/
├── SKILL.md                    # 技能文档
├── README.md                   # 本文件
├── llm_bench_remote.sh         # 远程自动化测试脚本
├── examples/
│   └── config.sh               # 配置示例
└── templates/
    ├── report.md               # 报告模板
    └── result_schema.json      # 结果数据结构
```

## 🚀 快速开始

### 1. 配置远程服务器

编辑 `llm_bench_remote.sh` 顶部的配置：

```bash
REMOTE_HOST="192.168.66.65"
REMOTE_USER="cyril"
REMOTE_MODEL_PATH="/path/to/model.gguf"
REMOTE_LLAMA_BIN="/usr/local/bin/llama-server"
```

### 2. 运行测试

```bash
# 快速测试
./llm_bench_remote.sh quick

# 对比测试
./llm_bench_remote.sh compare

# 自动调优
./llm_bench_remote.sh tune
```

### 3. 查看结果

测试结果保存在 `remote_results/[timestamp]/` 目录。

## 📊 测试模式

| 模式 | 耗时 | 测试内容 |
|------|------|----------|
| quick | 3-5 分钟 | 基本性能验证 |
| compare | 10-15 分钟 | 5 种配置对比 |
| tune | 20-40 分钟 | 自动寻找最优配置 |
| scan | 60-120 分钟 | 完整参数扫描 |

## 🏆 最优配置（基于 Qwen3.6-27B @ 4090D 48GB）

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

**预期吞吐量**: 76+ tok/s

## 📋试结果示例

| 配置 | 显存 | 吞吐量 |
|------|------|--------|
| parallel=2, spec=3 | 23GB | 69 tok/s |
| parallel=4, spec=5 | 28GB | 77 tok/s |
| parallel=8, spec=5 | 34GB | 72 tok/s |

## 📝 关键发现

1. **MTP 是关键**: `spec_draft=5` 带来最大提升
2. **parallel=4 最佳**: 超过 4 边际收益递减
3. **Q8 缓存足够**: f16 对性能无帮助
4. **不要过度猜测**: spec_draft=8 反而降低性能

## 🔗 相关资源

- [llama.cpp MTP 支持](https://github.com/ggerganov/llama.cpp/pull/22673)
- [Qwen3.6 模型](https://huggingface.co/Qwen)
- [llama.cpp 文档](https://github.com/ggerganov/llama.cpp)

## 📜 版本
- Github: https://github.com/cyril-wx/myskills/upload/main
- v1.0 (2026-05-30): 初始版本
  - 基于 Qwen3.6-27B @ 4090D 48GB 测试
  - 包含完整的参数调优指南
  - 自动化远程测试脚本