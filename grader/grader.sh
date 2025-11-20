#!/usr/bin/env bash
set -euo pipefail

SERVERA="servera"
SERVERB="serverb"

# SSH options with connection multiplexing to avoid repeated password prompts
CONTROL_PATH="/tmp/ssh-%r@%h:%p"
SSHOPTS="-o StrictHostKeyChecking=no \
         -o UserKnownHostsFile=/dev/null \
         -o ConnectTimeout=5 \
         -o ControlMaster=auto \
         -o ControlPath=${CONTROL_PATH} \
         -o ControlPersist=300 -q"

PASS=0          # tasks passed
FAIL=0          # tasks failed
TOTAL=0         # total tasks
POINTS_PASS=0   # points (2 per task)
POINTS_TOTAL=0  # total possible points
REPORT="/home/student/grade_report.txt"; : > "$REPORT"

# Colors + symbols (disable colors if not a TTY)
if [ -t 1 ]; then
  GREEN="\e[32m"
  RED="\e[31m"
  YELLOW="\e[33m"
  RESET="\e[0m"
else
  GREEN=""; RED=""; YELLOW=""; RESET=""
fi
CHECK="✔"
CROSS="✘"

# Summary writer (used only at the end)
summary() {
    echo -e "$1"
    echo -e "$1" >> "$REPORT"
}

ok(){ PASS=$((PASS+1)); POINTS_PASS=$((POINTS_PASS+2)); }
bad(){ FAIL=$((FAIL+1)); }
add(){ TOTAL=$((TOTAL+1)); POINTS_TOTAL=$((POINTS_TOTAL+2)); }

# SSH helpers
rcmd(){ ssh $SSHOPTS "student@$1" "${2:-true}"; }

# NOTE: everything passed to rsudo must be a *single-quoted* string (no unescaped double quotes)
rsudo(){
  local host="$1"
  shift
  local cmd="$*"
  ssh $SSHOPTS "student@$host" \
    "echo student | sudo -S -p '' bash -lc \"$cmd\""
}

gre(){ grep -Eq "$2" <<<"$1"; }

# Task runner: one label, one check, pretty output
task() {
  local label="$1"; shift
  add
  if "$@"; then
    ok
    printf "%b[%s] %s%b\n" "$GREEN" "$CHECK" "$label" "$RESET"
    echo "[PASS] $label" >> "$REPORT"
  else
    bad
    printf "%b[%s] %s%b\n" "$RED" "$CROSS" "$label" "$RESET"
    echo "[FAIL] $label" >> "$REPORT"
  fi
  sleep 1
}

echo "=== RHEL Practical Auto-Grader ==="
echo "Running checks... (this may take a minute)"
echo "Detailed report: $REPORT"
echo "----------------------------------------"

echo "=== RHEL Practical Auto-Grader ===" >> "$REPORT"
date >> "$REPORT"

# Prime SSH master connections (one password prompt per host, ideally)
ssh $SSHOPTS -MNf "student@$SERVERA" || true
ssh $SSHOPTS -MNf "student@$SERVERB" || true

# Helper: check reboot after exam marker
check_reboot(){
  local host="$1"
  local boot exam
  boot=$(rcmd "$host" "stat -c %Y /proc/1" 2>/dev/null || echo 0)
  exam=$(rsudo "$host" 'cat /root/.exam_start 2>/dev/null || echo 0')
  [[ ${boot:-0} -gt ${exam:-0} ]]
}

# ---- SHORT-CIRCUIT: pristine environment -> 0/49 ----
# If there is no webops group and no alice user on servera,
# assume the student hasn't started the exam yet.
if ! rcmd "$SERVERA" "getent group webops >/dev/null" && \
   ! rcmd "$SERVERA" "getent passwd alice >/dev/null"; then
    TOTAL=49
    PASS=0
    FAIL=49
    POINTS_TOTAL=$((TOTAL*2))
    POINTS_PASS=0
    summary "Environment appears unconfigured (no exam users/groups found)."
    summary "RESULT: FAIL"
    summary "SCORE: $POINTS_PASS/$POINTS_TOTAL = 0%"
    summary "Report saved to: $REPORT"
    exit 1
fi
# ------------------------------------------------------

echo
echo -e "${YELLOW}GLOBAL: SELinux state${RESET}"
task "SELinux Enforcing on servera" rcmd "$SERVERA" "getenforce | grep -xq Enforcing"
task "SELinux Enforcing on serverb" rcmd "$SERVERB" "getenforce | grep -xq Enforcing"

########################################
# PHASE 1: Users, Groups, and Access (servera)
########################################
echo
echo -e "${YELLOW}PHASE 1: Users, Groups, and Access (servera)${RESET}"

# Groups
task "Create group 'webops' (servera)" rcmd "$SERVERA" "getent group webops >/dev/null"
task "Create group 'secops' (servera)" rcmd "$SERVERA" "getent group secops >/dev/null"

# Users
task "User 'alice' in primary group 'webops' (servera)" \
     rcmd "$SERVERA" "id -nG alice | grep -qw webops"
task "User 'bob' in primary group 'secops' (servera)" \
     rcmd "$SERVERA" "id -nG bob   | grep -qw secops"
task "User 'carol' exists (servera)" \
     rcmd "$SERVERA" "id carol >/dev/null"

# Service accounts (no shell + locked)
task "Service account 'websvc' has no shell (/sbin/nologin) on servera" \
     rsudo "$SERVERA" "getent passwd websvc | grep -Eq '/sbin/nologin|/usr/sbin/nologin'"
task "Service account 'websvc' password locked on servera" \
     rsudo "$SERVERA" "passwd -S websvc 2>/dev/null | grep -qi 'locked'"
task "Service account 'secmon' has no shell (/sbin/nologin) on serverb" \
     rsudo "$SERVERB" "getent passwd secmon | grep -Eq '/sbin/nologin|/usr/sbin/nologin'"
task "Service account 'secmon' password locked on serverb" \
     rsudo "$SERVERB" "passwd -S secmon 2>/dev/null | grep -qi 'locked'"

# Directories & modes
task "/srv/shared: root:webops, SGID, mode 2775 (servera)" \
     rcmd "$SERVERA" "stat -c '%a %G %n' /srv/shared | grep -q '^2775 webops /srv/shared$'"
task "/srv/drop: root:secops, sticky, mode 1777 (servera)" \
     rcmd "$SERVERA" "stat -c '%a %G %n' /srv/drop   | grep -q '^1777 secops /srv/drop$'"
task "/srv/secure: root:secops, mode 750 (servera)" \
     rcmd "$SERVERA" "stat -c '%a %G %n' /srv/secure | grep -q '^750 secops /srv/secure$'"

# ACL
task "POSIX default ACL: 'alice' has read-only on new files in /srv/secure (servera)" \
     rsudo "$SERVERA" "getfacl -p /srv/secure | grep -Eq '^default:user:alice:.*r'"

# umask
task "System-wide default umask is 0022 (servera)" \
     rcmd "$SERVERA" "bash -lc 'umask' | grep -xq 0022"

########################################
# PHASE 2: SSH Hardening (serverb)
########################################
echo
echo -e "${YELLOW}PHASE 2: SSH Hardening (serverb)${RESET}"

SSHD_CONF="/etc/ssh/sshd_config"

# Get the effective port from sshd_config (last Port line wins)
PORT="$(rsudo "$SERVERB" "grep -i '^Port ' $SSHD_CONF | tail -n1 | awk '{print \$2}'" || true)"

check_sshd_port() {
  [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1024 && "$PORT" -ne 22 ]]
}
check_passwordauth_no() {
  rsudo "$SERVERB" "grep -qi '^PasswordAuthentication no' $SSHD_CONF"
}
check_allowgroups_webops() {
  rsudo "$SERVERB" "grep -qi '^AllowGroups webops' $SSHD_CONF"
}

task "sshd listening on non-default high port (>=1024, !=22) on serverb" \
     check_sshd_port
task "PasswordAuthentication disabled in sshd_config (serverb)" \
     check_passwordauth_no
task "AllowGroups restricted to 'webops' in sshd_config (serverb)" \
     check_allowgroups_webops

task "sshd actually bound to configured port on serverb" \
     rsudo "$SERVERB" "ss -lntp | grep -q \":$PORT .*sshd\""
task "SELinux ssh_port_t includes sshd port on serverb" \
     rsudo "$SERVERB" "semanage port -l | grep -E '^ssh_port_t' | grep -w $PORT >/dev/null"
task "Firewall allows sshd port on serverb" \
     rsudo "$SERVERB" "firewall-cmd --zone=public --list-ports | grep -qw ${PORT}/tcp"

echo
echo -e "${YELLOW}PHASE 2: SSH Authentication Behavior (serverb)${RESET}"

if [[ -n "$PORT" ]]; then
  task "Password login to serverb (on new port) is blocked" \
       bash -lc "! ssh $SSHOPTS -p \"$PORT\" -o PreferredAuthentications=password -o PubkeyAuthentication=no \"student@$SERVERB\" true"
  task "Key-based SSH login as 'alice' to serverb succeeds" \
       bash -lc "ssh $SSHOPTS -p \"$PORT\" \"alice@$SERVERB\" true"
  task "'bob' cannot SSH to serverb (blocked by AllowGroups)" \
       bash -lc "! ssh $SSHOPTS -p \"$PORT\" \"bob@$SERVERB\" true"
else
  # If we couldn't detect a port, record 3 fails but don't blow up with 'Bad port'
  task "Password login blocked (no ssh port detected)" false
  task "alice key login (no ssh port detected)" false
  task "bob blocked by AllowGroups (no ssh port detected)" false
fi

########################################
# PHASE 3: Web and Firewall (servera)
########################################
echo
echo -e "${YELLOW}PHASE 3: Web and Firewall (servera)${RESET}"

task "Apache httpd service enabled (servera)" \
     rcmd "$SERVERA" "systemctl is-enabled httpd | grep -xq enabled"
task "Apache httpd service active (running) on servera" \
     rcmd "$SERVERA" "systemctl is-active httpd | grep -xq active"
task "Firewall: https service allowed (servera)" \
     rsudo "$SERVERA" "firewall-cmd --zone=public --list-services | grep -qw https"
task "From workstation: https://servera returns 'I am servera.'" \
     bash -lc "curl -sk \"https://$SERVERA\" | grep -qx 'I am servera.'"

########################################
# PHASE 4: Port 82 + SELinux (servera)
########################################
echo
echo -e "${YELLOW}PHASE 4: Web on port 82 + SELinux (servera)${RESET}"

task "SELinux http_port_t includes port 82 (servera)" \
     rsudo "$SERVERA" "semanage port -l | grep '^http_port_t' | grep -w 82"
task "Firewall allows port 82/tcp (servera)" \
     rsudo "$SERVERA" "firewall-cmd --zone=public --list-ports | grep -qw 82/tcp"
task "From workstation: http://servera:82 responds" \
     bash -lc "curl -s \"http://$SERVERA:82\" | grep -q '.'"

########################################
# PHASE 4 (continued): SELinux fcontext + Alias (servera)
########################################
echo
echo -e "${YELLOW}PHASE 4: SELinux fcontext + /x/ alias (servera)${RESET}"

task "SELinux fcontext: /srv/www-extra(/...) labeled httpd_sys_content_t" \
     rsudo "$SERVERA" "semanage fcontext -l | grep -E '^/srv/www-extra(/.*)?' | grep -q httpd_sys_content_t"
task "From workstation: http://servera:82/x/index.html shows 'I am servera.'" \
     bash -lc "curl -s \"http://$SERVERA:82/x/index.html\" | grep -qx 'I am servera.'"

########################################
# EXTRA: No web on serverb
########################################
echo
echo -e "${YELLOW}CHECK: No unintended web server on serverb${RESET}"

task "httpd not active (running) on serverb" \
     rcmd "$SERVERB" "systemctl is-active httpd 2>/dev/null | grep -qxv active"
task "httpd not enabled on boot on serverb" \
     rcmd "$SERVERB" "systemctl is-enabled httpd 2>/dev/null | grep -qxv enabled"

########################################
# PHASE 5: Logging and Analysis (serverb)
########################################
echo
echo -e "${YELLOW}PHASE 5: Logging and Analysis (serverb)${RESET}"

task "journald logs persistent on serverb (/var/log/journal exists, readable)" \
     rsudo "$SERVERB" "test -d /var/log/journal && ls /var/log/journal/* >/dev/null 2>&1"
task "journald shows at least one failed SSH password attempt today (serverb)" \
     rsudo "$SERVERB" "journalctl -S today -u sshd | grep -qi 'Failed password'"
task "journald shows at least one successful public-key login today (serverb)" \
     rsudo "$SERVERB" "journalctl -S today -u sshd | grep -qi 'publickey'"
task "SELinux logs an AVC denial today (e.g., sshd bind attempt) on serverb" \
     rsudo "$SERVERB" "ausearch -m AVC -ts today | grep -q 'avc:'"
task "Firewall: cockpit service reachable on servera" \
     rsudo "$SERVERA" "firewall-cmd --zone=public --list-services | grep -qw cockpit"
task "Firewall: cockpit service reachable on serverb" \
     rsudo "$SERVERB" "firewall-cmd --zone=public --list-services | grep -qw cockpit"

########################################
# PHASE 7: Reboot & Persistence
########################################
echo
echo -e "${YELLOW}PHASE 7: Reboot & Persistence${RESET}"

task "servera has been rebooted after exam start marker" check_reboot "$SERVERA"
task "serverb has been rebooted after exam start marker" check_reboot "$SERVERB"

if [[ -n "$PORT" ]]; then
  task "Post-reboot: alice key login to serverb still works" \
       bash -lc "ssh $SSHOPTS -p \"$PORT\" \"alice@$SERVERB\" true"
  task "Post-reboot: bob remains blocked from SSH to serverb" \
       bash -lc "! ssh $SSHOPTS -p \"$PORT\" \"bob@$SERVERB\" true"
else
  task "Post-reboot: alice key login to serverb still works (no ssh port detected)" false
  task "Post-reboot: bob remains blocked from SSH to serverb (no ssh port detected)" false
fi

task "Post-reboot: https://servera still returns 'I am servera.'" \
     bash -lc "curl -sk \"https://$SERVERA\" | grep -qx 'I am servera.'"
task "Post-reboot: http://servera:82 still responds" \
     bash -lc "curl -s \"http://$SERVERA:82\" | grep -q '.'"
task "Post-reboot: http://servera:82/x/index.html still returns 'I am servera.'" \
     bash -lc "curl -s \"http://$SERVERA:82/x/index.html\" | grep -qx 'I am servera.'"

########################################
# SUMMARY
########################################

pct=0
if [ "$POINTS_TOTAL" -gt 0 ]; then
  pct=$(( 100 * POINTS_PASS / POINTS_TOTAL ))
fi

echo
echo "----------------------------------------"
summary "RESULT: $([ "$FAIL" -eq 0 ] && echo PASS || echo FAIL)"
summary "SCORE: $POINTS_PASS/$POINTS_TOTAL = ${pct}%"
summary "Report saved to: $REPORT"
echo "----------------------------------------"

[ "$FAIL" -eq 0 ] || exit 1