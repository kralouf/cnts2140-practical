#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/inventory"

SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=5
)

# Use sshpass so students do not need to set up SSH keys for the exam
sshsudo() {
  local user host cmd
  user="$1"; host="$2"; shift 2
  cmd="$*"
  sshpass -p "$LAB_PASSWORD" ssh "${SSH_OPTS[@]}" "${user}@${host}" "sudo bash -lc '$cmd'"
}

sshsudo_file() {
  local user host src dst
  user="$1"; host="$2"; src="$3"; dst="$4"
  # copy to a temp path then sudo-move into place with correct perms if needed
  sshpass -p "$LAB_PASSWORD" scp "${SSH_OPTS[@]}" "$src" "${user}@${host}:/tmp/.upl.$$"
  sshpass -p "$LAB_PASSWORD" ssh "${SSH_OPTS[@]}" "${user}@${host}" "sudo install -m 700 -o root -g root /tmp/.upl.$$ '$dst'; rm -f /tmp/.upl.$$"
}