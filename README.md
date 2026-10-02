# DGX Spark · Qwen3.8 本地部署工具集

在单台 NVIDIA DGX Spark（GB10）上部署 **Qwen3.8 系列**模型的完整可复现工具集：安装、权重下载加速、验证、基准与诊断脚本。

> **想先看故事？** 面向非专业读者的完整实录（做错了什么、为什么这么配、实测多少速度）：
> [`docs/deployment-story.md`](docs/deployment-story.md) —— 大白话版，无需背景知识。

> 部署引擎与安装逻辑来自 [hasso5703/dgx-spark-qwen38](https://github.com/hasso5703/dgx-spark-qwen38)（MIT）。本仓库是**围绕它的部署封装与实测记录**，不含对方源码的修改版。

## 当前部署：Qwen3.8-Flash-Next 176B MoE NVFP4（SGLang v0.5.21）

| | |
|---|---|
| 目标模型 | `RadixArk/Qwen3.8-Flash-Next-NVFP4` @ `7b719225…`（176B 混合 MoE，激活仅 6B；NVFP4） |
| 投机 draft | NEXTN/MTP（MTP 头内置于 target checkpoint，无独立 draft）；**QSA 锁死 `steps=3 / topk=1 / draft=4`**，draft 词表裁剪到 65,536（`token-map-65536.pt`） |
| 引擎 | **`lmsysorg/sglang:v0.5.21`（官方稳定版，`e00930c548`）**；首部署用的是预览分支 `dev-qwen38-next-local`，A/B 实测两版打平后已固化升级到稳定版 |
| 关键机制 | **47.7 GiB FP8 PLE/n-gram 表走 NVMe file-backed mmap**——这是 Flash-Next 能塞进单张 GB10 的前提（`--ple-offload-backend file`） |
| 服务 | `qwen38-flash.service`（:30000）+ `qwen38-keepalive.service`（:30001） |
| 上下文 | **262,144 tokens（原生，无 YaRN 扩展）** |
| 并发 | **4**（`FLASH_TIER=context`；mamba 状态池决定，非算力） |
| 内存 | `--mem-fraction-static 0.85`；KV 池 ~46–47 万 token（随开机波动）；开机约 10–15 分钟 |
| 模型名 | `qwen3.8-flash-next` |

**实测**（贪心、关闭 thinking）：

| 场景 | 结果 |
|---|---|
| 单流 · 代码 / 数学 / 说明文（2026-09-10 首部署） | **36.5 / 44.6 / 25.0** tok/s |
| 单流 greedy median（2026-10-02 用 `bench.sh` 复测，v0.5.21） | **约 42–43** tok/s |
| 4 路并发聚合 | **68.3** tok/s（8 路 71.5，第 5 路起排队） |
| 长上下文 | 25k 首字 12.1 s / 83k 首字 33.9 s，检索均命中 |

> ⚠️ **关于"47.9"**：`bench.sh` 自己就警告"刚开机一批只有 38.8、后几批才 47.7–49.1"——同一台参考机跨 boot 从 28.6 飘到 49.1，**"稳定 47.9" 并不存在**。本机常年 42 上下本就在波动带内；方差来自 PLE 表页缓存冷暖（开机彩票），**不是版本、也不是可再调的参数**（投机解码早被 QSA 锁死）。

完整交付说明与实时运维见 [`docs/archive/handover-flashnext-176b.md`](docs/archive/handover-flashnext-176b.md)（含 2026-10-02 升 v0.5.21 的更新记录）；调优取舍全故事见
[`docs/deployment-story.md`](docs/deployment-story.md)。

<details>
<summary>另一条保留的 lane：Qwen3.8-27B-NVFP4 + DFlash2（仍装在机上，可一键切回）</summary>

27B lane **未卸载**，unit 与权重都保留在机器上，`./switch-model.sh stock` + `systemctl` 即可切回。其优势：
**8 路并发、YaRN 可扩到 52 万上下文、启动 6–9 分钟、磁盘 ~70 GB、mainline 镜像（可维护性好）**。
其完整交付说明见 [`docs/handover.md`](docs/handover.md)。

实测（贪心、关闭 thinking）：单流 代码 43.2 / 数学 51.3 / 说明文 22.1 tok/s；8 路聚合 157.7。

**为何 Flash-Next 参数没得调、27B 有**：Flash-Next 用 Qwen QSA 稀疏注意力，引擎硬性要求
`speculative_num_draft_tokens ≤ 4`、`eagle_topk = 1`，有效 draft 宽度 = `max(steps+1, draft_tokens)`——
投机解码被锁死在唯一合法点 `steps=3 / topk=1 / draft=4`。27B 是普通 dense + GDN 混合，无此约束，
故可用 DFLASH 的 8 draft tokens。
</details>

## 基线环境

| 项目 | 值 |
|---|---|
| 机器 | NVIDIA DGX Spark（GB10，aarch64），统一内存 121.6 GiB |
| 系统 | Ubuntu 24.04.5（DGX OS），内核 6.17.0-1032-nvidia |
| 驱动 / CUDA | 580.173.02 / CUDA 13.0 |
| Docker | 29.2.1 + NVIDIA Container Toolkit 1.20.0 |
| 磁盘需求 | flash lane ≈ 204 GB（权重 126 + PLE 表 48 + 镜像 30）；27B lane ≈ 70 GB；两条并存则相加 |

## 快速重装

```bash
# 1. 前置（一次）
sudo usermod -aG docker "$USER"        # 重新登录后生效
docker info >/dev/null && echo ok      # 安装脚本的前置检查

# 2. 权重：经 ModelScope 拉取并逐文件 sha256 校验（flash lane，135.3 GB）
#    Flash-Next 没有独立 draft checkpoint——MTP 头内置在 target 里，所以只 seed 一个
SEED_REPO=RadixArk/Qwen3.8-Flash-Next-NVFP4 \
SEED_REV=7b719225242aacd3dbd3f9407468c2ee9a9d2594 \
SEED_TAG=flash-target python3 scripts/seed_hf_cache.py

# 3. 安装（flash lane）
git clone https://github.com/hasso5703/dgx-spark-qwen38.git ~/dsh-work/repo
cd ~/dsh-work/repo
MODEL_CHOICE=flash ./install.sh
```

预置好权重后，安装脚本的下载步骤会**秒过**（实测 419 个文件在镜像内约 0.9 秒解析、零下载）。

<details>
<summary>切到 27B lane 的重装命令</summary>

```bash
SEED_REPO=RadixArk/Qwen3.8-27B-NVFP4 \
SEED_REV=52d1adc5f38aa5ebf099c29ed7025ba34cfbb854 \
SEED_TAG=27b-target python3 scripts/seed_hf_cache.py
SEED_REPO=z-lab/Qwen3.8-27B-DFlash2 \
SEED_REV=50307d4c4cde6860d4eee73e2547cd786fe8e8a4 \
SEED_TAG=27b-draft python3 scripts/seed_hf_cache.py
MODEL_CHOICE=stock CONTEXT_MODE=native ./install.sh     # 1M 模式改 CONTEXT_MODE=1m
```
</details>

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
  deployment-story.md     大白话全实录（含 176B→27B→又换回 176B 的完整故事 + v0.5.21 升级）
  handover.md             27B lane（保留、可一键切回）的完整交付说明
  archive/handover-flashnext-176b.md   **当前在跑的 Flash-Next** 完整交付 + 2026-10-02 升 v0.5.21 更新记录
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
systemctl status qwen38-flash qwen38-keepalive     # 当前跑 flash；27B 换成 qwen38-sglang
sudo systemctl restart qwen38-flash                # flash ≈10–15 分钟（重写 PLE 表）
journalctl -u qwen38-flash -f
./bench.sh ; ./bench-matrix.sh ; ./needle.sh ; ./bench-agent.py
FLASH_TIER=concurrency ./install.sh                # flash 换并发档位
./switch-model.sh <target> ; ./uninstall.sh        # 只改配置不重启，改完手动 restart
```

## 安全注意

- 本仓库所有脚本**不含任何凭据**；API Key 从 `~/.config/qwen38/api-key` 读取，SSH 密码从环境变量读取。
- 服务默认监听 `0.0.0.0`，请用防火墙限制来源网段。
- `anliang` 同时属于 `sudo` 与 `docker` 组，两者都等价于 root。

## 许可与致谢

部署引擎、systemd 单元、DFlash2 overlay 等来自 [hasso5703/dgx-spark-qwen38](https://github.com/hasso5703/dgx-spark-qwen38)（MIT）；
模型权重来自 [RadixArk](https://huggingface.co/RadixArk)、[Qwen](https://huggingface.co/Qwen) 与 [z-lab](https://huggingface.co/z-lab)；
推理引擎为 [SGLang](https://github.com/sgl-project/sglang)。本仓库仅包含围绕它们的部署封装与实测记录。
