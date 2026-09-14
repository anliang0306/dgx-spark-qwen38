# DGX Spark · Qwen3.8 本地部署工具集

在单台 NVIDIA DGX Spark（GB10）上部署 **Qwen3.8 系列**模型的完整可复现工具集：安装、权重下载加速、验证、基准与诊断脚本。

> **想先看故事？** 面向非专业读者的完整实录（做错了什么、为什么这么配、实测多少速度）：
> [`docs/deployment-story.md`](docs/deployment-story.md) —— 大白话版，无需背景知识。

> 部署引擎与安装逻辑来自 [hasso5703/dgx-spark-qwen38](https://github.com/hasso5703/dgx-spark-qwen38)（MIT）。本仓库是**围绕它的部署封装与实测记录**，不含对方源码的修改版。

## 当前部署：Qwen3.8-27B-NVFP4 + DFlash2

| | |
|---|---|
| 目标模型 | `RadixArk/Qwen3.8-27B-NVFP4` @ `52d1adc5…`（NVFP4 W4A4：MLP+lm_head 4bit，attention FP8） |
| 投机 draft | `z-lab/Qwen3.8-27B-DFlash2` @ `50307d4c…`，**DFLASH，8 draft tokens**（块大小由 draft 模型决定） |
| 引擎 | 本地构建 overlay `qwen38-dflash2:v1.2.3`（基线 `lmsysorg/sglang@sha256:febfb971…`） |
| 服务 | `qwen38-sglang.service`（:30000）+ `qwen38-keepalive.service`（:30001） |
| 上下文 | **524,288 tokens**（YaRN 静态缩放，`factor 2.0`；原生 262,144） |
| 并发 | **8**（`--max-running-requests 8` / `--cuda-graph-max-bs 8`） |
| 内存 | `--mem-fraction-static 0.60`；KV 池 728,017 tokens |
| 模型名 | `qwen3.8-27b` |

**实测**（贪心、关闭 thinking）：

| 场景 | 结果 |
|---|---|
| 单流 · 代码 / 数学 / 说明文 | **43.2 / 51.3 / 22.1** tok/s |
| 8 路并发聚合 | **157.7** tok/s（10 轮 soak 均值 143.5–168.4，**0 错误**） |
| 16 / 32 路请求 | 161.4 / 176.2 tok/s，但首字等待劣化到 7.6 s / 25.6 s |
| 长上下文 | 84k prompt 首字 65.6 s，检索命中 |
| 上下文上限实测 | 340,012 token 的请求成功处理 |

完整交付说明见 [`docs/handover.md`](docs/handover.md)；调优取舍（哪些有用、哪些白费）见
[`docs/deployment-story.md`](docs/deployment-story.md) 第 5 章。

<details>
<summary>已归档：Qwen3.8-Flash-Next 176B MoE NVFP4（2026-09-11 卸载）</summary>

该 lane 曾部署并实测通过（代码 36.5 / 数学 44.6 tok/s，4 路聚合 68.3，84k 检索命中），
后按用户要求完整卸载并回收 204 GB 磁盘。

其记录（含一条重要的引擎级硬约束结论）见
[`docs/archive/handover-flashnext-176b.md`](docs/archive/handover-flashnext-176b.md)。

**要点**：Flash-Next 使用 Qwen QSA 稀疏注意力，引擎硬性要求
`speculative_num_draft_tokens ≤ 4`、`eagle_topk = 1`，且有效 draft 宽度 = `max(steps+1, draft_tokens)`——
投机解码参数空间被锁死在唯一合法点 `steps=3 / topk=1 / draft=4`。**draft 调优没有空间。**
27B lane 是普通 dense + GDN 混合，没有该约束，因此可以用 DFLASH 的 8 draft tokens。
</details>

## 基线环境

| 项目 | 值 |
|---|---|
| 机器 | NVIDIA DGX Spark（GB10，aarch64），统一内存 121.6 GiB |
| 系统 | Ubuntu 24.04.5（DGX OS），内核 6.17.0-1032-nvidia |
| 驱动 / CUDA | 580.173.02 / CUDA 13.0 |
| Docker | 29.2.1 + NVIDIA Container Toolkit 1.20.0 |
| 磁盘需求 | 27B lane ≈ 70 GB（镜像 39 GB + 权重 25 GB） |

## 快速重装

```bash
# 1. 前置（一次）
sudo usermod -aG docker "$USER"        # 重新登录后生效
docker info >/dev/null && echo ok      # 安装脚本的前置检查

# 2. 权重：经 ModelScope 拉取并逐文件 sha256 校验（可选，但见下方说明）
SEED_REPO=RadixArk/Qwen3.8-27B-NVFP4 \
SEED_REV=52d1adc5f38aa5ebf099c29ed7025ba34cfbb854 \
SEED_TAG=27b-target python3 scripts/seed_hf_cache.py
SEED_REPO=z-lab/Qwen3.8-27B-DFlash2 \
SEED_REV=50307d4c4cde6860d4eee73e2547cd786fe8e8a4 \
SEED_TAG=27b-draft python3 scripts/seed_hf_cache.py

# 3. 安装
git clone https://github.com/hasso5703/dgx-spark-qwen38.git ~/dsh-work/repo
cd ~/dsh-work/repo
MODEL_CHOICE=stock CONTEXT_MODE=native ./install.sh
```

预置好权重后，安装脚本的下载步骤会**秒过**（实测 22+5 个文件在镜像内 0 秒解析、零下载）。

## 目录结构

```
scripts/
  seed_hf_cache.py        权重下载器：ModelScope 传输 → HF 缓存，逐文件 sha256/git-blob 校验
  verify.py               端到端验证（单流/并发 tok/s、工具调用、长上下文检索）
  bench_spec.py           固定基准仪器（5 提示 × 2 次 + 4 路并发），用于 A/B
  conc8.py                8 路并发聚合探测
  facts-27b.sh / facts.sh 交付信息与引擎内部指标（accept len / accept rate）采集
  status.sh / boot-status.sh   一键看进度与健康
  check-cache.sh          校验预置缓存完整性 + 是否被 huggingface_hub 接受
  launch-install.sh / seed-27b.sh / retry-seed.sh   后台启动安装 / 下载
  cleanup-sudoers.sh      删除部署期临时 NOPASSWD sudoers
  uninstall-flash.sh      卸载 flash lane 并回收磁盘
  recon*.sh / *probe*.sh / diag*.sh / audit-seed.sh   环境侦察、链路测速、故障定位
tools/
  sshx.js                 密码 SSH 助手（凭据从环境变量读取，不落盘）
docs/
  handover.md             当前 27B 部署的完整交付说明
  archive/                已卸载 lane 的历史记录
```

## 关键经验（踩过的坑）

1. **链路选择决定部署时长**：HuggingFace 直连与 hf-mirror 在部分网络下只有 ~12.5 MB/s，ModelScope 可达 40+ MB/s。`seed_hf_cache.py` 用 ModelScope 传输、**逐文件与 HF 的 LFS sha256（或 git blob sha1）比对**后才写入缓存——传输通道可换，内容不可换。
2. **缓存命中判定**：`huggingface_hub 1.x` 的 `_hf_hub_download_to_cache_dir` 只要 snapshot 指针（符号链接）存在就直接命中，不再比对 etag。因此预置 `blobs/<etag>` + `snapshots/<rev>/…` 即可让 `snapshot_download` 零下载返回。
3. **嵌套文件的符号链接深度**：`snapshots/<rev>/sub/file` 需要 `../../../blobs/<etag>`，写死 `../../blobs` 会产生**静默的断链**（在 `z-lab/Qwen3.8-27B-DFlash2` 的 `assets/` 目录上暴露）。现用 `os.path.relpath` 按实际深度计算。
4. **非法投机参数不会在启动时报错**：flash lane 的错误配置在权重加载完成（约 10 分钟）后才抛异常，配合 `Restart=always` 会变成崩溃重启循环。**改参数前先 `systemctl stop`**，并保留 launcher 备份。
5. **`uninstall.sh` 从不删数据**：它只卸服务与配置，镜像/权重/PLE 表的回收命令需自己执行。

## 日常运维

```bash
cd ~/dsh-work/repo
systemctl status qwen38-sglang qwen38-keepalive
sudo systemctl restart qwen38-sglang        # ≈6–9 分钟
journalctl -u qwen38-sglang -f
./bench.sh ; ./bench-matrix.sh ; ./needle.sh ; ./bench-agent.py
CONTEXT_MODE=1m ./install.sh                # 1M 上下文（YaRN）
./switch-model.sh <target> ; ./uninstall.sh
```

## 安全注意

- 本仓库所有脚本**不含任何凭据**；API Key 从 `~/.config/qwen38/api-key` 读取，SSH 密码从环境变量读取。
- 服务默认监听 `0.0.0.0`，请用防火墙限制来源网段。
- `anliang` 同时属于 `sudo` 与 `docker` 组，两者都等价于 root。

## 许可与致谢

部署引擎、systemd 单元、DFlash2 overlay 等来自 [hasso5703/dgx-spark-qwen38](https://github.com/hasso5703/dgx-spark-qwen38)（MIT）；
模型权重来自 [RadixArk](https://huggingface.co/RadixArk)、[Qwen](https://huggingface.co/Qwen) 与 [z-lab](https://huggingface.co/z-lab)；
推理引擎为 [SGLang](https://github.com/sgl-project/sglang)。本仓库仅包含围绕它们的部署封装与实测记录。
