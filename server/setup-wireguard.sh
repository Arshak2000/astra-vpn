#!/usr/bin/env bash
set -euo pipefail

# ASTRA VPN - initial WireGuard server setup for a fresh Ubuntu VPS.
# Run only on a new server you administer. This does not create user accounts
# or client profiles; those are added in a later, authenticated control-plane step.

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo bash setup-wireguard.sh"
  exit 1
fi

if [[ -e /etc/wireguard/wg0.conf ]]; then
  echo "A wg0.conf already exists. Refusing to overwrite it."
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This setup script supports Ubuntu/Debian servers using apt."
  exit 1
fi

WAN_IFACE="$(ip -o route show default | awk '{print $5; exit}')"
if [[ -z "${WAN_IFACE}" ]]; then
  echo "Could not detect the server's internet interface."
  exit 1
fi

echo "Installing WireGuard on interface: ${WAN_IFACE}"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard iptables

install -d -m 700 /etc/wireguard
umask 077
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
SERVER_PRIVATE_KEY="$(cat /etc/wireguard/server_private.key)"

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.66.0.1/24
ListenPort = 51820
PrivateKey = ${SERVER_PRIVATE_KEY}
SaveConfig = false
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WAN_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WAN_IFACE} -j MASQUERADE
EOF
chmod 600 /etc/wireguard/wg0.conf /etc/wireguard/server_private.key /etc/wireguard/server_public.key

cat > /etc/sysctl.d/99-astra-wireguard.conf <<'EOF'
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null

systemctl enable --now wg-quick@wg0

echo
echo "WireGuard service started."
echo "Server public key (safe to share with your client app):"
cat /etc/wireguard/server_public.key
echo
echo "IMPORTANT:"
echo "- In your VPS provider firewall, allow inbound UDP port 51820."
echo "- Configure the server firewall carefully before exposing the service."
echo "- NEVER share /etc/wireguard/server_private.key or wg0.conf."
echo "- No client has been added yet; this server is not ready for user connections."
