#!/bin/sh
podman exec caddy caddy adapt --config /etc/caddy/Caddyfile --pretty 2>/dev/null | python3 -c '
import sys, json
data=json.load(sys.stdin)
hosts=set()

def walk(x):
    if isinstance(x, dict):
        if "host" in x and isinstance(x["host"], list):
            hosts.update(x["host"])
        for v in x.values():
            walk(v)
    elif isinstance(x, list):
        for v in x:
            walk(v)

walk(data)

for h in sorted(hosts):
    if h != "*.ebra.dev":
        print(f"169.254.1.2 {h}")
' > hosts
