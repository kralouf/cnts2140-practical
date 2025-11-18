#!/usr/bin/env bash
set -euo pipefail

# Figure out where we are and load inventory
UTIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./inventory
. "$UTIL_DIR/inventory"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Basic ssh runner
sshrun() {
    local host=$1 user=$2
    shift 2
    ssh $SSH_OPTS "${user}@${host}" "$@"
}

# Run a command remotely using sudo (non-interactive)
# Uses LAB_PASSWORD from inventory to feed sudo on the remote host.
sshsudo() {
    local host=$1 user=$2
    shift 2
    local cmd="$*"

    ssh $SSH_OPTS "${user}@${host}" \
      "echo \"$LAB_PASSWORD\" | sudo -S bash -lc '$cmd'"
}

# Copy a file to a remote host
sshcopy() {
    local host=$1 user=$2 src=$3 dest=$4
    scp $SSH_OPTS "$src" "${user}@${host}:$dest"
}

# Copy a script to a remote host and make it executable (but DO NOT run it)
sshsudo_file() {
    local host=$1 user=$2 src=$3 dest=$4

    echo \"[*] Copying $src to $host:$dest\"
    sshcopy \"$host\" \"$user\" \"$src\" \"$dest\"

    echo \"[*] Setting mode on $host:$dest\"
    sshsudo \"$host\" \"$user\" \"chmod +x '$dest'\"
}
