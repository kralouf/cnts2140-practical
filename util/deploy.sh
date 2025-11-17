#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1) Integrity check (repo files)
( cd "$BASE_DIR" && sha256sum -c sha256sums.txt )

# 2) Load helpers
# shellcheck disable=SC1091
source "$BASE_DIR/util/common.sh"

echo "[*] Deploying baseline to servera/serverb..."
sshsudo_file "student" "servera.lab.example.com" "$BASE_DIR/proctor/baseline.sh" "/root/baseline.sh"
sshsudo "student" "servera.lab.example.com" "/root/baseline.sh"

sshsudo_file "student" "serverb.lab.example.com" "$BASE_DIR/proctor/baseline.sh" "/root/baseline.sh"
sshsudo "student" "serverb.lab.example.com" "/root/baseline.sh"

echo "[*] Injecting servera..."
sshsudo_file "student" "servera.lab.example.com" "$BASE_DIR/inject/servera_inject.sh" "/root/servera_inject.sh"
sshsudo "student" "servera.lab.example.com" "/root/servera_inject.sh"

echo "[*] Injecting serverb..."
sshsudo_file "student" "serverb.lab.example.com" "$BASE_DIR/inject/serverb_inject.sh" "/root/serverb_inject.sh"
sshsudo "student" "serverb.lab.example.com" "/root/serverb_inject.sh"

echo "[*] Installing grader on workstation..."
# Copy grader
sshsudo_file "student" "workstation.lab.example.com" "$BASE_DIR/grader/grade_practical.sh" "/usr/local/bin/grade_practical.sh"
# Lock grader (read+exec only; immutable)
sshsudo "student" "workstation.lab.example.com" "chown root:root /usr/local/bin/grade_practical.sh && chmod 0555 /usr/local/bin/grade_practical.sh && chattr +i /usr/local/bin/grade_practical.sh || true"

echo "[*] Done."
echo "Now students run:  /usr/local/bin/grader.sh"