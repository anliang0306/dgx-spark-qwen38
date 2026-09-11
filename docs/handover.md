# DGX Spark 部署交付：Qwen3.8-Flash-Next 176B MoE NVFP4（单机）

> **发布版说明**：本文件已脱敏——API Key 替换为 `<YOUR_API_KEY>`，主机地址替换为 `<DGX_HOST>`，hostname 替换为 `<HOSTNAME>`。含真实凭据的完整版仅保留在部署机上（`~/dsh-work/DGX-Spark-Qwen3.8-Flash-Next-部署交付.md`）。

- **主机**：`<DGX_HOST>`（hostname `<HOSTNAME>`），Ubuntu 24.04.5 / DGX OS，内核 6.17.0-1032-nvidia，aarch64
- **GPU**：NVIDIA GB10（DGX Spark），驱动 580.173.02，CUDA 13.0，统一内存 121.6 GiB
- **部署方式**：`hasso5703/dgx-spark-qwen38` 的 flash lane（`MODEL_CHOICE=flash`），长上下文档位 `FLASH_TIER=context`
- **状态**：服务已安装、已 enabled（开机自启）、已实测通过 ✅
- **完成时间**：2026-09-10 22:48 CST（首次启动耗时约 10.3 分钟）

---

## 1. 结果摘要

| 项目 | 值 |
|---|---|
| 模型 | `RadixArk/Qwen3.8-Flash-Next-NVFP4` @ `7b719225242aacd3dbd3f9407468c2ee9a9d2594`（176B 混合 MoE，6B 激活） |
| 引擎 | SGLang，镜像 `lmsysorg/sglang@sha256:9d2a843c706c74bc259c0d9abf360551eb2734e1e7d255ab012a6965f10480b6`（`dev-qwen38-next-local`，官方 GB10 镜像，无本地 overlay） |
| 服务名 | `qwen38-flash.service`（引擎）、`qwen38-keepalive.service`（保活代理） |
| OpenAI API | `http://<DGX_HOST>:30000/v1/chat/completions` |
| Anthropic API | `http://<DGX_HOST>:30000/v1/messages`（只认 `Authorization: Bearer`，不认 `x-api-key`） |
| Agent CLI 用端口 | `http://<DGX_HOST>:30001`（保活代理，opencode 等长流式客户端走这里） |
| 模型名 | `qwen3.8-flash-next` |
| API Key | `<YOUR_API_KEY>`（文件：`/home/anliang/.config/qwen38/api-key`） |
| 上下文窗口 | 262,144 tokens（服务端）；代理侧单请求上限 200,000 tokens |
| 并发上限 | **4**（context 档位，`--max-running-requests 4`） |
| 投机解码 | NEXTN/MTP，draft tokens = 4，draft 词表裁剪到 65,536（`token-map-65536.pt`） |
| 内存分数 | `--mem-fraction-static 0.85`，容器硬上限 `--memory 110g` |

## 2. 实测数据（本机，2026-09-10）

单流、`temperature=0`、关闭 thinking：

| 负载 | decode | TTFT | 输出 tokens |
|---|---|---|---|
| 代码生成 | **36.5 tok/s** | 210 ms | 395 |
| 数学推理 | **44.6 tok/s** | 290 ms | 512 |
| 技术说明文 | 25.0 tok/s | 258 ms | 309 |

并发与长上下文：

| 测试 | 结果 |
|---|---|
| 4 路并发 | **68.3 tok/s 聚合** |
| 8 路并发 | 71.5 tok/s 聚合（第 5–8 路排队，见下） |
| 25,248 token 提示 | TTFT 12.1 s，decode 39.2 tok/s，**检索命中** |
| 83,648 token 提示 | TTFT 33.9 s，decode 38.7 tok/s，**检索命中** |
| 工具调用 | ✅ 正确返回 `tool_calls` + `finish_reason: tool_calls`（`qwen3_coder` parser） |
| LAN 客户端访问 | ✅ 从其他机器 `http://<DGX_HOST>:30000` 调用成功 |

> **关于并发**：你选的是「长上下文优先（context）」档位，它的 mamba 状态池是 `--max-mamba-cache-size 20`，SGLang 按每请求 5 槽折算，把 `max_running_requests` 钳在 **4**。所以 8 路并发不会更快，第 5 路起排队。要更高并发需切到 `concurrency`（8 路）或 `throughput`（24 路、关闭投机）档位——见 §5。

> 社区参考值（同一硬件、concurrency 档位）：代码 32–40、数学 41–44、散文 17–22 tok/s，8 路聚合约 135–148。本机单流数值落在同一区间内。

## 3. 本次部署对系统做的改动

| 改动 | 说明 | 如何回滚 |
|---|---|---|
| 安装 systemd 单元 | `qwen38-flash.service`、`qwen38-keepalive.service`，均已 enable（开机自启） | `cd ~/dsh-work/repo && ./uninstall.sh` |
| 生成配置目录 | `~/.config/qwen38/`（API key、渲染出的 `launch-flash.sh`、打过补丁的 chat template、`opencode.json`、token map） | 同上 |
| opencode 集成 | 写了 `~/.config/qwen38/opencode.json`，并装了 `~/.local/bin/oc` 启动器（**该目录不在 PATH 中**） | 同上，或 `./install.sh --no-opencode` 后重装 |
| 模型数据 | `~/.cache/huggingface` 126 GB（HF 缓存格式）、`~/flashnext-ple` 48 GB 稀疏文件 | 手动删除 |
| Docker 镜像 | 30.3 GB | `docker rmi lmsysorg/sglang@sha256:9d2a84…` |
| 用户组 | 把 `anliang` 加入 `docker` 组（安装脚本的前置要求） | `sudo gpasswd -d anliang docker` |
| 管理仓库 | `~/dsh-work/repo`（含 `switch-model.sh`、`uninstall.sh`、`bench-matrix.sh`、`needle.sh` 等） | 保留，建议保留 |
| 临时 sudoers | 部署期间创建的 `/etc/sudoers.d/99-dsh-temp`（NOPASSWD） | **已在部署结束时删除并校验通过** ✅ |

磁盘占用：`/` 已用 243 GB / 916 GB，**剩余 627 GB**。服务运行时空闲内存约 13.4 GiB（该档位的设计工作点，见 §6）。

## 4. 怎么调用

```bash
KEY=$(cat ~/.config/qwen38/api-key)

# OpenAI 兼容
curl http://127.0.0.1:30000/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next","messages":[{"role":"user","content":"你好"}],
       "max_tokens":256,"chat_template_kwargs":{"enable_thinking":false}}'

# Anthropic 协议
curl http://127.0.0.1:30000/v1/messages \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-flash-next","max_tokens":256,
       "messages":[{"role":"user","content":"你好"}]}'
```

Python（OpenAI SDK）：

```python
from openai import OpenAI
c = OpenAI(base_url="http://<DGX_HOST>:30000/v1", api_key="<YOUR_API_KEY>")
r = c.chat.completions.create(model="qwen3.8-flash-next",
                              messages=[{"role": "user", "content": "你好"}],
                              extra_body={"chat_template_kwargs": {"enable_thinking": False}})
print(r.choices[0].message.content)
```

**opencode / Agent CLI**：用 30001 端口（保活代理会填补 SGLang 流式工具调用参数时的静默间隙，否则客户端会在 ~140–180 s 无输出后断流）。配置模板已在 `~/.config/qwen38/opencode.json`：

```bash
mkdir -p ~/.config/opencode && cp ~/.config/qwen38/opencode.json ~/.config/opencode/opencode.json
export PATH="$HOME/.local/bin:$PATH"   # 让 oc 启动器可用
oc                                     # = opencode --yolo，且已抬高输出 token 上限
```

**关于 thinking**：该模型默认开启 thinking。想要快速直答，请在请求里带
`"chat_template_kwargs": {"enable_thinking": false}`；注意 thinking 开启时正文在
`reasoning_content` 字段里，`content` 可能为空——客户端要两个字段都读。

## 5. 日常运维

```bash
cd ~/dsh-work/repo

systemctl status qwen38-flash qwen38-keepalive      # 状态
sudo systemctl restart qwen38-flash                 # 重启（≈10–15 分钟，见 §6）
journalctl -u qwen38-flash -f                       # 引擎日志
journalctl -u qwen38-keepalive -f                   # 代理日志
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30000/health

./bench-matrix.sh        # 该仓库自带的固定基准（跨引擎可比）
./needle.sh              # 长上下文检索测试
./bench-agent.py         # Agent 循环形态（多轮+前缀缓存）的 ms/tok

# 换档位（改并发/上下文取舍；会重新渲染启动脚本并重启）
FLASH_TIER=concurrency ./install.sh     # 8 并发（KV 池约 1/3）
FLASH_TIER=throughput  ./install.sh     # 24 并发，关闭投机解码
FLASH_TIER=context     ./install.sh     # 回到当前档位

# 换模型
./switch-model.sh stock|uncensored|fp8|flash|flash-uncensored
./uninstall.sh --list    # 先看清单
./uninstall.sh           # 卸载服务（数据另行提示）
```

## 6. 必须知道的注意事项

1. **每次重启/开机都要 ~10–15 分钟**：启动时会把 47.7 GiB 的 PLE 表整表重写到 NVMe 稀疏文件，然后做 CUDA graph 捕获。这是该 lane 的设计行为，不是故障。`Restart=always` 已配置。
2. **不要在启动时占用统一内存**：启动脚本要求 `MemAvailable ≥ 96 GiB`（最多等 180 s）。SGLang 是按「profiling 那一刻」的可用内存决定 KV 池大小的，启动时跑编译/其它 GPU 任务会让这次启动的 KV 池偏小。
3. **绝不要调高 `--mem-fraction-static`**：0.85 是当前值，**≥0.90 会把整机拖死到需要断电**（GB10 统一内存被 SGLang 少算 25–40 GB 瞬时分配）。1M 上下文模式在官方仓库里用 0.70。
4. **一台机器只能跑一个引擎**：`qwen38-sglang`（27B lane）与 `qwen38-flash` 互斥。
5. **不要移动/删除 `~/.cache/huggingface`**：服务端以 `HF_HUB_OFFLINE=1` 运行，靠 `--revision 7b719225…` 从该缓存解析权重。缓存损坏可用 `python3 ~/dsh-work/seed_hf_cache.py` 修复（它会逐文件 sha256 校验、只补缺失项）。
6. **空闲功耗**：启动参数已带 `--sleep-on-idle`，否则 SGLang 调度器会空转一个 CPU 核（+10~12 W）。
7. **桌面环境占用统一内存**：当前是 `graphical.target`（GNOME 在跑）。若想给 KV 池腾内存，可 `sudo systemctl set-default multi-user.target` 后重启——但会让整机失去图形界面。
8. **别在 100k+ 提示上用 262k 硬上限**：官方仓库在 200k 提示处测得仅剩 12.6 GiB 余量、贴近 ~10 GiB 的 livelock 边界；代理侧因此把单请求上限设为 200,000 tokens。

## 7. 性能调优建议

- **想要更高并发**：切 `FLASH_TIER=concurrency`（8 路）。context 档位的 4 路是 mamba 状态池决定的，与算力无关。
- **单流再快一点**：调 `--speculative-num-draft-tokens`（当前 4）。该 lane 的官方建议是先做 3–5 的扫描；过大反而掉速。
- **降低长提示 TTFT**：当前 `--chunked-prefill-size 4096`；配合 radix 前缀缓存复用。固定前缀的 Agent 场景收益最大（用 `bench-agent.py` 看 TTFT/1k 新增 token 是否接近 0）。
- **量化再往下走没有收益**：GB10/SM121 上 4-bit 的收益完全来自「每 token 少读字节」，不是 FP4 算力；再压位宽只会掉精度。

## 8. 本次部署的关键决策记录（为什么这么快）

HuggingFace 直连与 hf-mirror 在本机实测都只有 **~12.5 MB/s**（135 GB 要 ~3 小时），而 **ModelScope 上有同一个 checkpoint，实测 40+ MB/s**。因此：

1. 用 `~/dsh-work/seed_hf_cache.py` 从 ModelScope 并行拉取，**每个文件与 HuggingFace 的 LFS sha256（或 git blob sha1）逐一比对**，校验通过才写入 HF 缓存布局（`blobs/<etag>` + `snapshots/<rev>/…` 符号链接 + `refs/main`）；
2. 419 个文件全部校验通过（其中 1 个文件因连接截断失败，重试后通过），135.3 GB；
3. 官方 `install.sh` 第 4 步因此**秒过**，未触发 HF 重下——实测镜像内 `huggingface_hub 1.30.0` 的 `snapshot_download` 在 0.9 s 内解析 419 个文件、零下载。

传输通道可换，内容不可换：交付的权重与官方固定 revision 的 sha256 完全一致。

## 9. 投机解码（draft）调优结论：参数空间已被引擎锁死

2026-09-11 凌晨做了一轮 draft 深度扫描，结论是**没有可调空间**——官方配方的 `steps=3 / topk=1 / draft=4` 不是保守取值，而是这个模型在当前引擎上的唯一合法点。三条硬约束（均为引擎抛出的原始报错）：

| 尝试 | 引擎报错 | 结论 |
|---|---|---|
| `steps=5, draft=6` | `Qwen QSA requires speculative_num_draft_tokens <= the QSA compress ratio (4): the pending index-key ring holds one group; got 6` | draft tokens 上限 = 4（QSA 压缩比） |
| `steps=4, draft=4` | 同上，`got 5` | 有效 draft 宽度 = `max(steps+1, draft_tokens)` ⇒ **num_steps ≤ 3** |
| `steps=3, topk=2, draft=4` | `Qwen4-Exp QSA MTP currently supports speculative_eagle_topk=1` | **eagle topk 只能是 1** |

实测数据也印证了它已经吃满：单流 accept len 最高到 **3.55**（接受率 0.85），而上限是 4，即**剩余理论空间仅约 13%**，且那 13% 要靠提高接受率而非加深 draft 才能拿到。

固定基准（`~/dsh-work/bench_spec.py`，5 提示 × 2 次 + 4 路并发，贪心、关闭 thinking）：

| 配置 | 单流均值 | 单流中位 | 4 路聚合 |
|---|---|---|---|
| `steps=3 / topk=1 / draft=4`（基准） | 37.7 | 38.4 | 76.2 |
| `steps=3 / topk=1 / draft=4`（扫描后恢复复核） | 37.3 | 36.8 | 76.5 |

两者落在运行间噪声内（±1–4%），确认已恢复原状态、且无可提升空间。

**⚠️ 重要操作提醒**：这三个非法配置都**不在启动时立即报错**，而是在权重加载完成后（约 10 分钟）的调度器初始化阶段才抛异常；由于服务是 `Restart=always`，会进入**每 10 分钟一轮的崩溃重启循环**。所以今后若再改这些标志：

1. 先 `sudo systemctl stop qwen38-flash`，改完再 `start`，避免无谓的循环；
2. 原始 launcher 已备份在 `~/.config/qwen38/launch-flash.sh.orig`，一条 `cp` 即可回滚；
3. 每次改动要预留 ~12 分钟的启动时间。

**因此，剩下真正有效的优化只有这几项**（都不在 draft 参数上）：切并发档位（聚合吞吐）、用领域语料重建 token-map（提高接受率，对上面 accept len 未吃满的部分最对路）、token-map 尺寸 A/B、以及调用侧关 thinking / 降 reasoning effort。

## 10. 安全提醒

- **建议更换 `anliang` 的登录密码，并改用 SSH 公钥登录**：本次部署过程中该密码以明文出现过。
- **API Key 可随时轮换**：编辑 `~/.config/qwen38/api-key` 后 `sudo systemctl restart qwen38-flash qwen38-keepalive`（重启需 10–15 分钟）。
- **服务监听 `0.0.0.0`**（30000/30001），局域网内任何机器都可达；如需收紧，请用防火墙（`ufw`）限制来源网段。
- `anliang` 现同时在 `sudo` 与 `docker` 组（两者都等价于 root 权限）；这是安装脚本的前置要求，不需要可自行移除。
