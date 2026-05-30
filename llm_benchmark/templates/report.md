# LLM 性能测试报告

## 测试环境

| 项目 | 配置 |
|------|------|
| 硬件 | {{HARDWARE}} |
| 模型 | {{MODEL_NAME}} |
| 模型大小 | {{MODEL_SIZE}} |
| 推理引擎 | llama.cpp (llama-server) |
| 测试日期 | {{TEST_DATE}} |

## llama-server 启动参数

```bash
{{STARTUP_COMMAND}}
```

## 性能测试结果

### 配置：{{CONFIG_NAME}}

| 测试 | 生成 Tokens | Prompt Tokens | 耗时 | 吞吐量 |
|------|-------------|---------------|------|--------|
| 1 - 短文本 | {{TEST1_TOKENS}} | {{TEST1_PROMPT}} | {{TEST1_TIME}} | {{TEST1_TPS}} tok/s |
| 2 - 中等文本 | {{TEST2_TOKENS}} | {{TEST2_PROMPT}} | {{TEST2_TIME}} | {{TEST2_TPS}} tok/s |
| 3 - 长文本 | {{TEST3_TOKENS}} | {{TEST3_PROMPT}} | {{TEST3_TIME}} | {{TEST3_TPS}} tok/s |

### 平均吞吐量

**{{AVG_TPS}} tok/s**

## 性能分析

### 优点

1. **{{ADVANTAGE_1}}**
2. **{{ADVANTAGE_2}}**
3. **{{ADVANTAGE_3}}**

### 优化建议

针对 {{GPU_MODEL}}：

#### 1. 最大吞吐量配置

```bash
# 适用场景：批量推理
{{MAX_THROUGHPUT_CONFIG}}
```

#### 2. 最低延迟配置

```bash
# 适用场景：实时对话
{{MIN_LATENCY_CONFIG}}
```

#### 3. 平衡配置（推荐）

```bash
# 适用场景：一般用途
{{BALANCED_CONFIG}}
```

## 显存明细

| 阶段 | 显存占用 | 说明 |
|------|----------|------|
| 模型加载 | {{MODEL_VRAM}} | Q6_K 量化 |
| KV 缓存 | {{CACHE_VRAM}} | q8_0 精度 |
| 运行时总占用 | {{TOTAL_VRAM}} | - |
| 可用显存 | {{FREE_VRAM}} | - |
| 利用率 | {{VRAM_USAGE}}% | - |

## 结论

{{CONCLUSION}}

---

**测试日期**: {{TEST_DATE}}  
**测试工具**: llm_bench_remote.sh  
**测试执行**: {{EXECUTOR}}