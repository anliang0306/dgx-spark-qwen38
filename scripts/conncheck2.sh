#!/usr/bin/env bash
set -uo pipefail
echo "=== 主机全部 IP ==="
ip -4 -o addr show | awk '{print "  "$2": "$4}'

echo
echo "=== 默认路由 / 网卡 ==="
ip -4 route | head -8

echo
echo "=== ufw 状态 ==="
sudo -n ufw status verbose 2>/dev/null || echo "  (需要密码，用 --sudo 单独查)"

echo
echo "=== nftables / iptables 计数 ==="
sudo -n iptables -L INPUT -n -v 2>/dev/null | head -10 || echo "  (需要密码)"

echo
echo "=== 监听是否绑定到 0.0.0.0（而非仅回环）==="
ss -tln | awk 'NR==1 || /:(30000|30001)/'

echo
echo "=== 是否有 Docker 端口映射干扰 ==="
docker port qwen38-sglang 2>/dev/null || echo "  (host 网络模式，无映射)"

echo
echo "=== 当前服务名与模型 id ==="
KEY=$(cat "$HOME/.config/qwen38/api-key")
curl -s -m 8 http://127.0.0.1:30000/v1/models -H "Authorization: Bearer $KEY" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("  model id:", [m["id"] for m in d["data"]])'
