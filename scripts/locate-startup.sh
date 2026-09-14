#!/usr/bin/env bash
# Locate every file involved in STARTING the currently running model.
set -uo pipefail

echo "############ 1. 正在生效的启动定义：systemd unit ############"
for u in qwen38-sglang qwen38-keepalive; do
  p="/etc/systemd/system/$u.service"
  if [ -f "$p" ]; then
    printf '  %-46s %8s bytes  %s\n' "$p" "$(stat -c %s "$p")" "$(stat -c %y "$p" | cut -d. -f1)"
  else
    echo "  $p  (缺失)"
  fi
done

echo
echo "############ 2. 启用状态与软链 ############"
ls -l /etc/systemd/system/multi-user.target.wants/ 2>/dev/null | grep qwen38 | sed 's/^/  /'

echo
echo "############ 3. unit 里的启动命令行（前 12 行）############"
grep -nE 'ExecStart|ExecStop|WorkingDirectory|Restart' /etc/systemd/system/qwen38-sglang.service | head -12 | sed 's/^/  /'

echo
echo "############ 4. 是否还有独立的 launch 脚本？############"
ls -la "$HOME/.config/qwen38/" 2>/dev/null | sed 's/^/  /'
echo "  --- 找 launch*.sh ---"
find "$HOME/.config/qwen38" -maxdepth 1 -name 'launch*' 2>/dev/null | sed 's/^/  /' || true
echo "  （以上为空则说明 27B lane 不使用独立启动脚本）"

echo
echo "############ 5. 仓库里的模板与安装脚本（生成上述 unit 的源头）############"
for f in qwen38-sglang.service.template qwen38-keepalive.service.template install.sh switch-model.sh; do
  p="$HOME/dsh-work/repo/$f"
  [ -f "$p" ] && printf '  %-46s %8s bytes\n' "$p" "$(stat -c %s "$p")"
done

echo
echo "############ 6. 备份文件 ############"
ls -l "$HOME/.config/qwen38/"*.bak* /etc/systemd/system/*.bak* 2>/dev/null | sed 's/^/  /' || echo "  (无)"
ls -l "$HOME/.config/qwen38/"*preupdate* 2>/dev/null | sed 's/^/  /' || true

echo
echo "############ 7. 生效中的关键参数（1M 模式是否落地）############"
grep -oE '\-\-context-length [0-9]+|\-\-mem-fraction-static [0-9.]+|\-\-max-running-requests [0-9]+' \
  /etc/systemd/system/qwen38-sglang.service | sort -u | sed 's/^/  /'
