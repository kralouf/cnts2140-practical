#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1) Integrity check (repo files)
( cd "$BASE_DIR" && sha256sum -c sha256sums.txt )

# 2) Load helpers (brings in inventory + ssh helpers)
# shellcheck disable=SC1091
source "$BASE_DIR/util/common.sh"

echo "[*] Installing grader on workstation..."

# Copy grader to /tmp on workstation
sshcopy "$WORKSTATION_HOST" "$WORKSTATION_USER" \
    "$BASE_DIR/grader/grader.sh" "/tmp/grader.sh"

# Move into place, lock it down, but DO NOT run it
# NOTE: sshsudo already runs sudo on the remote side — no inner 'sudo' here.
sshsudo "$WORKSTATION_HOST" "$WORKSTATION_USER" "
  # Clear immutable bit if previously set
  chattr -i /usr/local/bin/grader.sh 2>/dev/null || true

  # Move new grader into place and secure it
  mv /tmp/grader.sh /usr/local/bin/grader.sh
  chown root:root /usr/local/bin/grader.sh
  chmod 0555 /usr/local/bin/grader.sh

  # Re-apply immutable bit so students can't edit it
  chattr +i /usr/local/bin/grader.sh 2>/dev/null || true
"

echo "[*] Done."
echo "Now students run:  grader.sh"
echo "Pre-Requisites are complete, good luck!"