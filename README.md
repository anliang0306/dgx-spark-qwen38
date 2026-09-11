# DGX Spark · Qwen3.8-Flash-Next 176B MoE NVFP4 部署工具集

在单台 NVIDIA DGX Spark（GB10）上部署 **Qwen3.8-Flash-Next 176B 混合 MoE（6B 激活）NVFP4** 的完整可复现工具集：安装、下载加速、验证、诊断、基准与运维脚本。

> 部署引擎与安装逻辑来自 [hasso5703/dgx-spark-qwen38](https://github.com/hasso5703/dgx-spark-qwen38)（MIT）。本仓库是**围绕它的部署封装与实测记录**，不含对方源码的修改版。

---

## 已验证的基线环境

| 项目 | 值 |
|---|---|
| 机器 | NVIDIA DGX Spark（GB10，aarch64），统一内存 121.6 GiB |
| 系统 | Ubuntu 24.04.5（DGX OS），内核 6.17.0-1032-nvidia |
| 驱动 / CUDA | 580.173.02 / CUDA 13.0 |
| Docker | 29.2.1 + NVIDIA Container Toolkit 1.20.0 |
| 磁盘需求 | ≥ 230 GB 可用（权重 135 GB + PLE 表 48 GB + 镜像 30 GB） |

## 部署结果

| 项目 | 值 |
|---|---|
| 模型 | `RadixArk/Qwen3.8-Flash-Next-NVFP4` @ `7b719225242aacd3dbd3f9407468c2ee9a9d2594` |
| 引擎镜像 | `lmsysorg/sglang@sha256:9d2a843c706c74bc259c0d9abf360551eb2734e1e7d255ab012a6965f10480b6` |
| 服务 | `qwen38-flash.service`（引擎 :30000）、`qwen38-keepalive.service`（代理 :30001） |
| 上下文 / 并发 | 262,144 tokens / 4 路（context 档位） |
| 首次启动 | ~10.3 分钟（每次启动都重写 47.7 GiB PLE 表） |

**实测（单流，贪心，关闭 thinking）**：代码 36.5、数学 44.6、说明文 25.0 tok/s；4 路聚合 68–76 tok/s；84k token 长上下文检索命中，decode 38.7 tok/s。

完整交付说明见 [`docs/handover.md`](docs/handover.md)。

---

## 快速重装

### 1. 前置（一次）

```bash
sudo usermod -aG docker "$USER"      # 重新登录后生效
docker info >/dev/null && echo ok    # 安装脚本的前置检查
```

### 2. 拉取权重（可选但强烈建议，能省 2 小时）

HuggingFace 直连/hf-mirror 在部分网络下只有 ~12.5 MB/s（135 GB ≈ 3 小时），而 ModelScope 可达 40+ MB/s。本仓库的 seeder 从 ModelScope 下载，**逐文件与 HF 的 LFS sha256（或 git blob sha1）比对**后再写入标准 HF 缓存布局，因此内容与官方固定 revision 完全一致：

```bash
python3 scripts/seed_hf_cache.py        # 可重复运行，已完成的文件会跳过
```

### 3. 安装

```bash
git clone https://github.com/hasso5703/dgx-spark-qwen38.git ~/dsh-work/repo
cd ~/dsh-work/repo
MODEL_CHOICE=flash FLASH_TIER=context ./install.sh
```

若权重已被第 2 步预置，安装脚本的下载步骤会秒过（实测镜像内 `huggingface_hub` 0.9 s 解析 419 个文件、零下载）。

## 目录结构

```
scripts/
  seed_hf_cache.py        权重下载器（ModelScope → HF 缓存，逐文件哈希校验）
  verify.py               端到端验证（单流/并发 tok/s、工具调用、长上下文检索）
  bench_spec.py           固定基准仪器（5 提示 × 2 次 + 4 路并发），用于 A/B
  conc8.py                8 路并发聚合探测
  set-tier.sh             修改投机解码参数（改前请读 handover 第 9 章）
  bench-after-restart.sh  等引擎恢复后自动跑基准并抓取 accept len/rate
  check-cache.sh          校验预置缓存完整性 + 是否被 huggingface_hub 接受
  status.sh / boot-status.sh   一键看进度与健康
  launch-install.sh / launch-seed.sh   后台启动安装 / 下载
  cleanup-sudoers.sh      删除部署期临时 NOPASSWD sudoers
  recon*.sh / *probe*.sh / diag*.sh    环境侦察、链路测速、故障定位
  facts.sh / metrics.sh   交付信息采集、引擎内部指标（accept len / accept rate）
tools/
  sshx.js                 无依赖密码 SSH 助手（凭据从环境变量读取，不落盘）
docs/
  handover.md             完整交付说明（已脱敏）
```

## 日常运维

```bash
cd ~/dsh-work/repo
systemctl status qwen38-flash qwen38-keepalive
sudo systemctl restart qwen38-flash          # ≈10–15 分钟
journalctl -u qwen38-flash -f
./bench-matrix.sh ; ./needle.sh ; ./bench-agent.py
FLASH_TIER=concurrency ./install.sh          # 换并发档位（8 路）
./switch-model.sh <target> ; ./uninstall.sh
```

## 关键实测结论

1. **投机解码参数被引擎锁死**：`Qwen QSA requires speculative_num_draft_tokens <= the QSA compress ratio (4)`、有效宽度 = `max(steps+1, draft_tokens)`、且 `Qwen4-Exp QSA MTP currently supports speculative_eagle_topk=1` ⇒ 唯一合法点是 `steps=3 / topk=1 / draft=4`，正是官方配方。**draft 调优没有空间**（详见 handover 第 9 章）。
2. **接受率决定单流速度**：代码/数学类文本 accept rate 0.7–0.85，自由文本降到 0.05–0.3，对应 44 tok/s 与 13 tok/s 的差距。提升方向是给 token-map 喂领域语料，不是加深 draft。
3. **并发是唯一的成倍杠杆**：context 档位 mamba 状态池把并发钳在 4，后到的请求排队；要聚合吞吐就切 `concurrency`。
4. **非法投机参数不会在启动时报错**，而是在权重加载完成（约 10 分钟）后抛异常；因 `Restart=always` 会变成每 10 分钟一轮的崩溃重启循环——改参数前务必先 `systemctl stop`。

## 安全注意

- 本仓库所有脚本**不含任何凭据**，API Key 与主机地址从 `~/.config/qwen38/api-key` 和环境变量读取。
- `docs/handover.md` 为脱敏版；含真实凭据的版本只保留在部署机上。
- 服务默认监听 `0.0.0.0`，请用防火墙限制来源网段；`anliang` 同时属于 `sudo` 与 `docker` 组，两者都等价于 root。

## 许可与致谢

部署引擎、systemd 单元、PLE 文件后端等核心逻辑来自 [hasso5703/dgx-spark-qwen38](https://github.com/hasso5703/dgx-spark-qwen38)（MIT）；模型权重来自 [RadixArk](https://huggingface.co/RadixArk) 与 [Qwen](https://huggingface.co/Qwen/Qwen3.8-Flash-Next)；推理引擎为 [SGLang](https://github.com/sgl-project/sglang)。本仓库仅包含围绕它们的部署封装与实测记录。
