#!/usr/bin/env bash
set -euo pipefail

# LuaMUD and websockify are local-only implementation ports. Permit loopback
# callers, then explicitly drop every non-loopback connection to these ports.
for port in 7777 6080; do
  iptables -C INPUT -i lo -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -i lo -p tcp --dport "$port" -j ACCEPT
  iptables -C INPUT ! -i lo -p tcp --dport "$port" -j DROP 2>/dev/null || \
    iptables -I INPUT 2 ! -i lo -p tcp --dport "$port" -j DROP
done
