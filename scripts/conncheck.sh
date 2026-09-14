#!/usr/bin/env bash
set -uo pipefail
echo "=== 服务状态 ==="
systemctl is-active qwen38-sglang.service qwen38-keepalive.service | tr '\n' ' '; echo
systemctl is-enabled qwen38-sglang.service qwen38-keepalive.service | tr '\n' ' '; echo
echo "启动于: $(systemctl show -p ActiveEnterTimestamp --value qwen38-sglang.service)"
echo "重启次数: $(systemctl show -p NRestarts --value qwen38-sglang.service)"

echo
echo "=== 容器 ==="
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' | head -5

echo
echo "=== 监听端口 ==="
ss -tlnp 2>/dev/null | grep -E ':(30000|30001)' || echo "!!! 30000/30001 未监听 !!!"

echo
echo "=== 本机回环测试 ==="
curl -s -m 8 -o /dev/null -w '  127.0.0.1:30000/health      -> %{http_code}\n' http://127.0.0.1:30000/health
curl -s -m 8 -o /dev/null -w '  127.0.0.1:30001/health      -> %{http_code}\n' http://127.0.0.1:30001/health

echo
echo "=== 用主机实际 IP 测试（走网卡，不是回环）==="
for ip in $(hostname -I); do
  curl -s -m 8 -o /dev/null -w "  $ip:30000/health -> %{http_code}\n" "http://$ip:30000/health" || echo "  $ip 连接失败"
done

echo
echo "=== 鉴权 ==="
KEY=$(cat "$HOME/.config/qwen38/api-key")
curl -s -m 8 -o /dev/null -w '  带 key  /v1/models -> %{http_code}\n' http://127.0.0.1:30000/v1/models -H "Authorization: Bearer $KEY"
curl -s -m 8 -o /dev/null -w '  无 key  /v1/models -> %{http_code}\n' http://127.0.0.1:30000/v1/models

echo
echo "=== 防火墙 ==="
if command -v ufw >/dev/null 2>&1; then ufw status 2>/dev/null | head -6; else echo "(无 ufw)"; fi
iptables -L INPUT -n 2>/dev/null | head -8 || echo "(iptables 需要 root，跳过)"

echo
echo "=== 最近错误（若有）==="
journalctl -u qwen38-sglang --since '-30 min' --no-pager 2>/dev/null | grep -iE 'traceback|exception|OOM|killed|CUDA error' | tail -5 || echo "(无)"
echo "--- 最后 5 行 ---"
journalctl -u qwen38-sglang -n 5 --no-pager 2>/dev/null | tail -5
