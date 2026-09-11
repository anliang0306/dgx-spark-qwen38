# DGX Spark 部署交付：Qwen3.8-27B-NVFP4 + DFlash2（单机）

> 本文档描述**当前**部署。上一版（Qwen3.8-Flash-Next 176B MoE）的记录见
> [`archive/handover-flashnext-176b.md`](archive/handover-flashnext-176b.md)，该模型已于
> 2026-09-11 按用户要求卸载。

- **主机**：DGX Spark（GB10，aarch64），Ubuntu 24.04.5 / DGX OS，内核 6.17.0-1032-nvidia
- **GPU**：NVIDIA GB10，驱动 580.173.02，CUDA 13.0，统一内存 121.6 GiB
- **部署方式**：`hasso5703/dgx-spark-qwen38` 的 27B lane，`MODEL_CHOICE=stock CONTEXT_MODE=native`
- **状态**：服务已安装、已 enabled（开机自启）、已实测通过 ✅
- **完成时间**：2026-09-11 10:13 CST（安装全程约 6.7 分钟，其中首次启动约 6 分钟）

> 本文档**不含凭据**：API Key 在部署机上用 `cat ~/.config/qwen38/api-key` 读取。

---

## 1. 结果摘要

| 项目 | 值 |
|---|---|
| 目标模型 | `RadixArk/Qwen3.8-27B-NVFP4` @ `52d1adc5f38aa5ebf099c29ed7025ba34cfbb854`（21 GB，NVFP4 W4A4：MLP+lm_head 4bit，attention FP8） |
| 投机 draft | `z-lab/Qwen3.8-27B-DFlash2` @ `50307d4c4cde6860d4eee73e2547cd786fe8e8a4`（3.6 GB） |
| 引擎 | SGLang，本地构建 overlay `qwen38-dflash2:v1.2.3`（基线 `lmsysorg/sglang@sha256:febfb971…`） |
| 服务 | `qwen38-sglang.service`（引擎 :30000）、`qwen38-keepalive.service`（代理 :30001） |
| 模型名 | `qwen3.8-27b` |
| 上下文 | 262,144 tokens（native） |
| 并发上限 | **8**（`--max-running-requests 8`） |
| 投机解码 | **DFLASH**，`--speculative-num-draft-tokens 8`，draft 不量化 |
| 内存 | `--mem-fraction-static 0.50`，容器硬上限 `--memory 100g`；实测空闲 44.9 GiB |
| 磁盘 | `/` 已用 101 G / 916 G，剩余 768 G |

### 接口

```bash
KEY=$(cat ~/.config/qwen38/api-key)
# OpenAI 兼容
curl http://127.0.0.1:30000/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"你好"}],"max_tokens":256}'
# Anthropic 协议（只认 Authorization: Bearer，不认 x-api-key）
curl http://127.0.0.1:30000/v1/messages -H "Authorization: Bearer $KEY" ...
# Agent CLI 用 30001（保活代理）
```

局域网访问把 `127.0.0.1` 换成主机地址即可。

## 2. 实测数据（2026-09-11，贪心，关闭 thinking）

单流：

| 负载 | decode | TTFT |
|---|---|---|
| 代码生成 | **43.2 tok/s** | 136 ms |
| 数学推理 | **51.3 tok/s** | 235 ms |
| 技术说明文 | 22.1 tok/s | 232 ms |

仓库自带固定基准（`bench-matrix.sh` v1，两段式差值法、扣除 prefill）：

| 负载 | tok/s |
|---|---|
| math (EN, eval-style) | 42.7 |
| reasoning (FR) | 43.9 |
| code (DE) | 31.2 |
| code (EN) | 28.3 |
| technical explain (FR) | 25.6 |
| free prose (EN / FR / DE) | 20.6 / 17.5 / 15.6 |

并发与队列行为（**重要**：`--max-running-requests 8` 是硬上限，更多并发只排队）：

| 并发 | 聚合吞吐 | TTFT 中位 | 说明 |
|---|---|---|---|
| 4 路 | 62.8 tok/s | — | |
| 8 路 | **157.7 tok/s**（10 轮均值 143.5–168.4） | 477 ms | 打满上限 |
| 16 路 | 161.4 tok/s | **7.6 s** | 后 8 路排队 |
| 32 路 | 176.2 tok/s | **25.6 s** | 后 24 路排队 |

**结论**：8 路已接近本配置的吞吐饱和点（8→32 路仅 +12%），而 TTFT 从 0.48 s 退化到 25.6 s（**慢 50 倍**）。
对外提供多用户服务时应把并发控制在 8 附近；想真正提高聚合吞吐必须同时放宽三个参数
（`--max-running-requests`、`--max-mamba-cache-size`、`--cuda-graph-max-bs` —— 只改第一个无效，
batch 超过 CUDA graph 上限会退回 eager 执行）。

长上下文与功能：

| 测试 | 结果 |
|---|---|
| 25,248 token 提示 | TTFT 15.6 s，decode 26.7 tok/s，**检索命中** |
| 83,648 token 提示 | TTFT 65.6 s，decode 18.2 tok/s，**检索命中** |
| 工具调用 | ✅ `tool_calls` + `finish_reason: tool_calls`（`qwen3_coder`） |
| 引擎侧指标 | accept len 3.7–4.35，accept rate 0.38–0.48，峰值 gen throughput 222 tok/s |
| 稳定性 soak | 8 路 × 10 轮，**0 错误**，宿主可用内存全程恒定 45.0 GiB（无漂移） |

> **关于第三方公开数据**：社区仓库 `hasso5703/dgx-spark-qwen38` 声称 8 路聚合 135–148、32 路 258；
> `darkdatter/gb10-repo` 声称 16 路 480.7（单流 78.6）。本机实测 8 路 157.7（**吻合**）、16 路 161.4、
> 32 路 176.2（**明显低于后两者**）。差异的原因是配置不同：480@16 需要把 `--max-running-requests`
> 提到 16 并同时放宽 mamba 池与 CUDA graph 上限，而本部署保持在验证过的 8 路配置。**引用这些数字时必须连同配置一起引用。**


## 3. 实际运行的引擎参数

```
--trust-remote-code --model-path RadixArk/Qwen3.8-27B-NVFP4 --revision 52d1adc5… --tp-size 1
--served-model-name qwen3.8-27b
--mem-fraction-static 0.50 --attention-backend flashinfer --chunked-prefill-size 8192
--disable-prefill-cuda-graph --cuda-graph-max-bs 8 --disable-flashinfer-autotune
--speculative-algorithm DFLASH --speculative-draft-model-path z-lab/Qwen3.8-27B-DFlash2
--speculative-num-draft-tokens 8 --speculative-draft-model-quantization unquant
--mamba-radix-cache-strategy extra_buffer --mamba-ssm-dtype bfloat16
--max-mamba-cache-size 96 --max-running-requests 8
--enable-torch-compile --torch-compile-max-bs 4
--num-continuous-decode-steps 2 --sleep-on-idle
--reasoning-parser qwen3 --tool-call-parser qwen3_coder
```

**为什么这份配方比 flash lane 宽松**：Flash-Next 用的是 Qwen QSA 稀疏注意力，引擎硬性要求
`speculative_num_draft_tokens ≤ 4`、`eagle_topk = 1`；27B 是普通 dense + GDN 混合，没有这个约束，
所以能用 DFLASH 的 8 draft tokens 和 8 路并发。

## 4. 日常运维

```bash
cd ~/dsh-work/repo

systemctl status qwen38-sglang qwen38-keepalive
sudo systemctl restart qwen38-sglang       # ≈6–9 分钟
journalctl -u qwen38-sglang -f
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30000/health

./bench.sh              # 该 lane 自带的基准
./bench-matrix.sh       # 跨引擎可比的固定基准
./needle.sh             # 长上下文检索测试
./bench-agent.py        # Agent 循环形态（多轮 + 前缀缓存）的 ms/tok

# 换档位 / 换目标（跨 lane 会重新下载并重启）
CONTEXT_MODE=1m ./install.sh          # 1M 上下文（YaRN，mem-fraction 0.70）
MODEL_CHOICE=fp8 ./install.sh         # 换成 Qwen 官方 FP8
./switch-model.sh <target>
./uninstall.sh --list ; ./uninstall.sh
```

## 5. 注意事项

1. **重启要等 6–9 分钟**（权重加载 + CUDA graph 捕获 + torch.compile 缓存）。`Restart=always` 已配置。
2. **不要动 `--mem-fraction-static`**：0.50 是这条 lane 的验证值，它让运行时空闲内存保持在 44.9 GiB；调高会挤压宿主，SGLang 在 GB10 统一内存上的记账会少算 25–40 GB。
3. **每台机器只跑一个引擎**：`qwen38-sglang`（27B）与 `qwen38-flash`（Flash-Next）互斥。
4. **权重以 `HF_HUB_OFFLINE` 方式从本地缓存读取**：`~/.cache/huggingface` 下的
   `models--RadixArk--Qwen3.8-27B-NVFP4`（21 G）与 `models--z-lab--Qwen3.8-27B-DFlash2`（3.6 G）
   不要移动或删除；损坏可用 `python3 ~/dsh-work/seed_hf_cache.py` 修复（逐文件 sha256 校验，只补缺失项）。
5. **`--sleep-on-idle` 已启用**，否则调度器会空转一个 CPU 核。
6. 桌面环境（GNOME）占用统一内存；如需更多余量可切 `multi-user.target`。

## 6. 本次变更记录（2026-09-11）

按用户要求，先把 Flash-Next 176B lane 完整卸载并回收磁盘，再部署 27B：

| 步骤 | 结果 |
|---|---|
| `./uninstall.sh --yes` | 移除 `qwen38-flash` / `qwen38-keepalive` 单元、`~/.config/qwen38`、`oc` 启动器 |
| 数据回收 | 删除 126 G 权重 + 48 G PLE 表 + 30.3 G 镜像，`/` 从 243 G 降至 40 G |
| 预置 27B 权重 | 用 `seed_hf_cache.py` 经 ModelScope 拉取，**22+5 个文件全部通过 sha256 校验**，安装脚本的下载步骤 0 秒完成 |
| 拉取基线镜像 | `lmsysorg/sglang@sha256:febfb971…`（约 39 GB） |
| 安装 | `MODEL_CHOICE=stock CONTEXT_MODE=native ./install.sh`，6.7 分钟完成（含首次启动） |
| 临时免密 sudo | 安装期间创建 `/etc/sudoers.d/99-dsh-temp`，**安装完成后立即删除并校验**（`sudo -n` 已重新要求密码） |

## 7. 安全提醒

- 服务监听 `0.0.0.0`（30000/30001），局域网内可达；建议用防火墙限制来源网段。
- API Key 轮换：编辑 `~/.config/qwen38/api-key` 后 `sudo systemctl restart qwen38-sglang qwen38-keepalive`。
- `anliang` 同时在 `sudo` 与 `docker` 组（都等价于 root），这是安装脚本的前置要求，不需要可自行移除。
