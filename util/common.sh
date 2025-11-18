#!/usr/bin/env bash
set -euo pipefail

# Figure out where we are and load inventory
UTIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./inventory
. "$UTIL_DIR/inventory"

# Basic ssh runner
sshrun() {
    local host=$1 user=$2
    shift 2
    ssh -o StrictHostKeyChecking=no "${user}@${host}" "$@"
}

# Run a command remotely using sudo (non-interactive)
sshsudo() {
    local host=$1 user=$2
    shift 2
    sshrun "$host" "$user" sudo -n "$@"
}

# Copy a file to a remote host
sshcopy() {
    local host=$1 user=$2 src=$3 dest=$4
    scp -o StrictHostKeyChecking=no "$src" "${user}@${host}:$dest"
}

# Copy a script to a remote host, chmod +x it, then run it with sudo
sshsudo_file() {
    local host=$1 user=$2 src=$3 dest=$4

    echo "[*] Copying $src to $host:$dest"
    sshcopy "$host" "$user" "$src" "$dest"

    echo "[*] Making $dest executable on $host"
    sshsudo "$host" "$user" chmod +x "$dest"

    echo "[*] Executing $dest on $host as root"
    sshsudo "$host" "$user" "$dest"
}