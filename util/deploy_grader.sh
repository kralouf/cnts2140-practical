#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1) Integrity check (repo files)
# Make sure the filename here matches your repo (sha256sums.txt vs SHA256SUMS)
( cd "$BASE_DIR" && sha256sum -c sha256sums.txt )

# 2) Load helpers (brings in inventory + ssh helpers)
# shellcheck disable=SC1091
source "$BASE_DIR/util/common.sh"

echo "[*] Installing grader on workstation..."
# Copy grader to /tmp
sshcopy "$WORKSTATION_HOST" "$WORKSTATION_USER" "$BASE_DIR/grader/grader.sh" "/tmp/grader.sh"

# Move into place, lock it down, but DO NOT run it
sshsudo "$WORKSTATION_HOST" "$WORKSTATION_USER" \
  "mv /tmp/grader.sh /usr/local/bin/grader.sh && \
   sudo chown root:root /usr/local/bin/grader.sh && \
   sudo chmod 0555 /usr/local/bin/grader.sh && \
   sudo chattr +i /usr/local/bin/grader.sh || true"

echo "[*] Done."
echo "Now students run:  grader.sh"
echo "Pre-Requisites are complete, good luck!"