# build with: podman build -t localhost/caddy-cloudflare:local .
# in current directory
FROM docker.io/caddy:builder-alpine AS builder

RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM docker.io/caddy:alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
