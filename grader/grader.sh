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

PASS=0; FAIL=0; TOTAL=0
REPORT="/home/student/grade_report.txt"; : > "$REPORT"

# Write only to report
say() { echo -e "$1" >> "$REPORT"; }

# Write to report + stdout (for final summary only)
summary() {
    echo -e "$1"
    echo -e "$1" >> "$REPORT"
}

ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); }
add(){ TOTAL=$((TOTAL+1)); }
mark(){
    add
    if "$@"; then
        ok
        say "PASS: $*"
    else
        bad
        say "FAIL: $*"
    fi
}

# SSH helpers
rcmd(){ ssh $SSHOPTS "student@$1" "${2:-true}"; }
rsudo(){ ssh $SSHOPTS "student@$1" "echo student | sudo -S bash -lc '$2'"; }
gre(){ grep -Eq "$2" <<<"$1"; }

# Prime SSH master connections (one password prompt per host)
ssh $SSHOPTS -MNf "student@$SERVERA" || true
ssh $SSHOPTS -MNf "student@$SERVERB" || true

say "=== RHEL Practical Auto-Grader ==="
say "$(date)"

# Helper: check reboot after exam marker
check_reboot(){
  local host="$1"
  local boot exam
  boot=$(rcmd "$host" "stat -c %Y /proc/1" 2>/dev/null || echo 0)
  exam=$(rsudo "$host" "cat /root/.exam_start 2>/dev/null || echo 0")
  [[ ${boot:-0} -gt ${exam:-0} ]]
}

# ---- SHORT-CIRCUIT: pristine environment -> 0/49 ----
# If there is no webops group and no alice user on servera,
# we assume the student hasn't started the exam yet.
if ! rcmd "$SERVERA" "getent group webops >/dev/null" && \
   ! rcmd "$SERVERA" "getent passwd alice >/dev/null"; then
    TOTAL=49
    PASS=0
    FAIL=49
    summary "Environment appears unconfigured (no exam users/groups found)."
    summary "RESULT: FAIL"
    summary "SCORE: 0/$TOTAL = 0%"
    summary "Report saved to: $REPORT"
    exit 1
fi
# ------------------------------------------------------

say "\n[SELinux enforcing]"
mark rcmd "$SERVERA" "getenforce | grep -xq Enforcing"
mark rcmd "$SERVERB" "getenforce | grep -xq Enforcing"

say "\n[Phase 1: Users/Groups/Access on servera]"
mark rcmd "$SERVERA" "getent group webops >/dev/null"
mark rcmd "$SERVERA" "getent group secops >/dev/null"
mark rcmd "$SERVERA" "id -nG alice | grep -qw webops"
mark rcmd "$SERVERA" "id -nG bob   | grep -qw secops"
mark rcmd "$SERVERA" "id carol >/dev/null"

say "\n[Service accounts]"
mark rsudo "$SERVERA" "getent passwd websvc | grep -q '/sbin/nologin'"
mark rsudo "$SERVERA" "passwd -S websvc 2>/dev/null | grep -qi 'locked'"
mark rsudo "$SERVERB" "getent passwd secmon | grep -q '/sbin/nologin'"
mark rsudo "$SERVERB" "passwd -S secmon 2>/dev/null | grep -qi 'locked'"

say "\n[Directories & modes (servera)]"
mark rcmd "$SERVERA" "stat -c '%a %G %n' /srv/shared | grep -q '^2775 webops /srv/shared$'"
mark rcmd "$SERVERA" "stat -c '%a %G %n' /srv/drop   | grep -q '^1777 secops /srv/drop$'"
mark rcmd "$SERVERA" "stat -c '%a %G %n' /srv/secure | grep -q '^750 secops /srv/secure$'"

say "\n[ACLs (servera)]"
mark rsudo "$SERVERA" "getfacl -p /srv/secure | grep -Eq '^default:user:alice:.*r'"

say "\n[umask (servera)]"
mark rcmd "$SERVERA" "bash -lc 'umask' | grep -xq 0022"

say "\n[Phase 2: SSH hardening on serverb]"
SSHD_T="$(rsudo "$SERVERB" "sshd -T 2>/dev/null" || true)"
PORT="$(awk '/^port /{print $2}' <<<"$SSHD_T" | head -n1)"
add; if [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1024 && "$PORT" -ne 22 ]]; then ok; say "PASS: sshd high port $PORT"; else bad; say "FAIL: sshd high port invalid ($PORT)"; fi
add; if gre "$SSHD_T" "^passwordauthentication no"; then ok; say "PASS: PasswordAuthentication no"; else bad; say "FAIL: PasswordAuthentication not no"; fi
add; if gre "$SSHD_T" "^allowgroups webops"; then ok; say "PASS: AllowGroups webops"; else bad; say "FAIL: AllowGroups not webops"; fi
mark rsudo "$SERVERB" "ss -lntp | grep -q \":$PORT .*sshd\""
mark rsudo "$SERVERB" "semanage port -l | grep -E '^ssh_port_t' | grep -Eq '(^|[^0-9])'"$PORT"'([^0-9]|$)'"
mark rsudo "$SERVERB" "firewall-cmd --zone=public --list-ports | grep -qw ${PORT}/tcp"

say "\n[SSH auth behavior (serverb)]"
add; if ! ssh $SSHOPTS -p "$PORT" -o PreferredAuthentications=password -o PubkeyAuthentication=no "student@$SERVERB" true; then ok; say "PASS: password login blocked"; else bad; say "FAIL: password login succeeded"; fi
add; if ssh $SSHOPTS -p "$PORT" "alice@$SERVERB" 'true'; then ok; say "PASS: alice key login ok"; else bad; say "FAIL: alice key login failed"; fi
add; if ! ssh $SSHOPTS -p "$PORT" "bob@$SERVERB" 'true'; then ok; say "PASS: bob blocked by AllowGroups"; else bad; say "FAIL: bob unexpectedly allowed"; fi

say "\n[Phase 3: Web & firewall on servera]"
mark rcmd "$SERVERA" "systemctl is-enabled httpd | grep -xq enabled"
mark rcmd "$SERVERA" "systemctl is-active httpd | grep -xq active"
mark rsudo "$SERVERA" "firewall-cmd --zone=public --list-services | grep -qw https"
add; if curl -sk "https://$SERVERA" | grep -qx "I am servera."; then ok; say "PASS: curl https"; else bad; say "FAIL: curl https"; fi

say "\n[Phase 4: Port 82 + SELinux (servera)]"
mark rsudo "$SERVERA" "semanage port -l | grep '^http_port_t' | grep -Eq '(^|[^0-9])82([^0-9]|$)'"
mark rsudo "$SERVERA" "firewall-cmd --zone=public --list-ports | grep -qw 82/tcp"
add; if curl -s "http://$SERVERA:82" | grep -q "."; then ok; say "PASS: curl :82 works"; else bad; say "FAIL: curl :82 failed"; fi

say "\n[Phase 5: SELinux fcontext + alias (servera)]"
mark rsudo "$SERVERA" "semanage fcontext -l | grep -E '^/srv/www-extra(\(/\.\*\)\?)?\s+all\s+system_u:object_r:httpd_sys_content_t:s0'"
add; if curl -s "http://$SERVERA:82/x/index.html" | grep -qx "I am servera."; then ok; say "PASS: alias /x from /srv/www-extra"; else bad; say "FAIL: alias /x failed"; fi

say "\n[No web on serverb]"
add; if ! rcmd "$SERVERB" "systemctl is-active httpd 2>/dev/null | grep -qx active"; then ok; say "PASS: httpd not active"; else bad; say "FAIL: httpd active on serverb"; fi
add; if ! rcmd "$SERVERB" "systemctl is-enabled httpd 2>/dev/null | grep -qx enabled"; then ok; say "PASS: httpd not enabled"; else bad; say "FAIL: httpd enabled on serverb"; fi

say "\n[Phase 6: Logging/journald/cockpit]"
mark rsudo "$SERVERB" "test -d /var/log/journal && journalctl --directory=/var/log/journal -n1 >/dev/null"
mark rsudo "$SERVERB" "journalctl -S today -u sshd | grep -qi 'Failed password'"
mark rsudo "$SERVERB" "journalctl -S today -u sshd | grep -qi 'publickey'"
mark rsudo "$SERVERB" "ausearch -m AVC -ts today | grep -q 'avc:'"
mark rsudo "$SERVERA" "firewall-cmd --zone=public --list-services | grep -qw cockpit"
mark rsudo "$SERVERB" "firewall-cmd --zone=public --list-services | grep -qw cockpit"

say "\n[Phase 7: Reboot & persistence]"
mark check_reboot "$SERVERA"
mark check_reboot "$SERVERB"

say "\n[Post-reboot rechecks]"
add; if ssh $SSHOPTS -p "$PORT" "alice@$SERVERB" 'true'; then ok; say "PASS: alice key login persists"; else bad; say "FAIL: alice key login not persistent"; fi
add; if ! ssh $SSHOPTS -p "$PORT" "bob@$SERVERB" 'true'; then ok; say "PASS: bob remains blocked"; else bad; say "FAIL: bob allowed post-reboot"; fi
add; if curl -sk "https://$SERVERA" | grep -qx "I am servera."; then ok; say "PASS: https persists"; else bad; say "FAIL: https not persistent"; fi
add; if curl -s "http://$SERVERA:82" | grep -q "."; then ok; say "PASS: :82 persists"; else bad; say "FAIL: :82 not persistent"; fi
add; if curl -s "http://$SERVERA:82/x/index.html" | grep -qx "I am servera."; then ok; say "PASS: alias persists"; else bad; say "FAIL: alias not persistent"; fi

# summary + scoring
pct=0
if [ "$TOTAL" -gt 0 ]; then
  pct=$(( 100 * PASS / TOTAL ))
fi

summary "RESULT: $([ "$FAIL" -eq 0 ] && echo PASS || echo FAIL)"
summary "SCORE: $PASS/$TOTAL = ${pct}%"
summary "Report saved to: $REPORT"

[ "$FAIL" -eq 0 ] || exit 1