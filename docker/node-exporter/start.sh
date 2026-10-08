#!/usr/bin/env bash
# Start the node-exporter stack, binding it to the host's Tailscale IPv4 address.
set -euo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

TAILSCALE_IP="$(tailscale ip -4 | head -n1)"
if [[ -z "${TAILSCALE_IP}" ]]; then
    echo "Unable to determine Tailscale IPv4 address" >&2
    exit 1
fi
export TAILSCALE_IP

echo "Starting node-exporter on ${TAILSCALE_IP}:9100"
docker compose pull
docker compose up -d --remove-orphans "$@"
