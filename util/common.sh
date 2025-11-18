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

# Run a command remotely using sudo with password from LAB_PASSWORD
sshsudo() {
    local host=$1 user=$2
    shift 2
    local cmd="$*"

    # Send LAB_PASSWORD to sudo via stdin (-S), suppress prompt (-p '')
    ssh -o StrictHostKeyChecking=no "${user}@${host}" \
        "echo \"$LAB_PASSWORD\" | sudo -S -p '' $cmd"
}


# Copy a file to a remote host
sshcopy() {
    local host=$1 user=$2 src=$3 dest=$4
    scp -o StrictHostKeyChecking=no "$src" "${user}@${host}:$dest"
}

# Copy a script to a remote host, chmod +x it, then run it with sudo
sshsudo_file() {
    local host=$1 user=$2 src=$3 dest=$4

    # Copy to a temp path that "user" can write to
    local tmp="/tmp/$(basename "$src")"

    echo "[*] Copying $src to $host:$tmp"
    sshcopy "$host" "$user" "$src" "$tmp"

    echo "[*] Moving $tmp to $dest and making it executable on $host"
    sshsudo "$host" "$user" mv "$tmp" "$dest"
    sshsudo "$host" "$user" chmod +x "$dest"

    echo "[*] Executing $dest on $host as root"
    sshsudo "$host" "$user" "$dest"
}
