set -u
echo "=== os ==="; cat /etc/os-release | head -3
echo "=== docker ==="; docker --version 2>&1; docker info --format '{{.ServerVersion}} storage={{.Driver}} runtimes={{.Runtimes}}' 2>&1 | head -3
echo "=== nvidia toolkit ==="; nvidia-ctk --version 2>&1 | head -2
echo "=== containers ==="; docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>&1 | head -20
echo "=== images ==="; docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' 2>&1 | head -20
echo "=== home ==="; ls -la ~ | head -30
echo "=== models present? ==="; ls -d ~/.cache/huggingface 2>/dev/null && du -sh ~/.cache/huggingface 2>/dev/null
ls -d ~/models ~/dgx-spark-qwen38 ~/flashnext-ple /var/tmp/models 2>/dev/null
echo "=== systemd units of interest ==="; systemctl list-units --all --no-legend 'qwen*' 'opencode*' 2>/dev/null | head
echo "=== net ==="; curl -sS -m 15 -o /dev/null -w 'huggingface=%{http_code} ' https://huggingface.co/ 2>&1; curl -sS -m 15 -o /dev/null -w 'modelscope=%{http_code}\n' https://www.modelscope.cn/ 2>&1
echo "=== python ==="; python3 --version; which python3 pip3 uv 2>/dev/null
echo "=== disk ==="; df -h | grep -Ev 'tmpfs|udev|loop'
echo "=== mem ==="; free -g
echo "=== swap/dev ==="; swapon --show 2>/dev/null | head
echo "=== earlyoom? ==="; systemctl is-active earlyoom 2>&1
echo "=== gui ==="; systemctl get-default
