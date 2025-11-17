#!/usr/bin/env bash
set -euo pipefail

SERVERA="servera"
SERVERB="serverb"
SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -q"

PASS=0; FAIL=0; TOTAL=0
REPORT="/home/student/grade_report.txt"; : > "$REPORT"
say(){ echo -e "$1" | tee -a "$REPORT"; }
ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); }
add(){ TOTAL=$((TOTAL+1)); }
mark(){ add; if "$@"; then ok; say "PASS: $*"; else bad; say "FAIL: $*"; fi; }

rcmd(){ ssh $SSHOPTS "student@$1" "${2:-true}"; }
rsudo(){ ssh $SSHOPTS "student@$1" "sudo bash -lc '$2'"; }
gre(){ grep -Eq "$2" <<<"$1"; }

say "=== RHEL Practical Auto-Grader ==="
date | tee -a "$REPORT"

# helper: check reboot after exam marker
check_reboot(){
  local host="$1"
  local boot exam
  boot=$(rcmd "$host" "stat -c %Y /proc/1" 2>/dev/null || echo 0)
  exam=$(rsudo "$host" "cat /root/.exam_start 2>/dev/null || echo 0")
  [[ ${boot:-0} -gt ${exam:-0} ]]
}

say "\n[SELinux enforcing]"
mark rcmd "$SERVERA" "getenforce | grep -xq Enforcing"
mark rcmd "$SERVERB" "getenforce | grep -xq Enforcing"

say "\n[Phase 1: Users/Groups/Access on servera]"
mark rcmd "$SERVERA" "getent group webops >/dev/null"
mark rcmd "$SERVERA" "getent group secops >/dev/null"
mark rcmd "$SERVERA" "id -nG alice | grep -qw webops"
mark rcmd "$SERVERA" "id -nG bob   | grep -qw secops"
mark rcmd "$SERVERA" "id carol >/dev/null"

# service accounts (servera/b)
say "\n[Service accounts]"
mark rsudo "$SERVERA" "getent passwd websvc | grep -q '/sbin/nologin'"
mark rsudo "$SERVERA" "passwd -S websvc 2>/dev/null | grep -qi 'locked'"
mark rsudo "$SERVERB" "getent passwd secmon | grep -q '/sbin/nologin'" || mark rsudo "$SERVERB" "false"  # allow fail if not created
mark rsudo "$SERVERB" "passwd -S secmon 2>/dev/null | grep -qi 'locked'" || mark rsudo "$SERVERB" "false"

# directories & modes
say "\n[Directories & modes (servera)]"
mark rcmd "$SERVERA" "stat -c '%a %G %n' /srv/shared | grep -q '^775 webops /srv/shared$'"
mark rcmd "$SERVERA" "stat -c '%f' /srv/shared | awk '{exit !((strtonum(\"0x\"$1) & 0x200) != 0)}'"
mark rcmd "$SERVERA" "stat -c '%a %G %n' /srv/drop   | grep -q '^777 secops /srv/drop$'"
mark rcmd "$SERVERA" "stat -c '%f' /srv/drop   | awk '{exit !((strtonum(\"0x\"$1) & 0x200) != 0)}'"  # sticky bit 01000
mark rcmd "$SERVERA" "stat -c '%a %G %n' /srv/secure | grep -q '^750 secops /srv/secure$'"

# ACL for alice on /srv/secure
say "\n[ACLs (servera)]"
mark rsudo "$SERVERA" "getfacl -p /srv/secure | grep -Eq '^default:other::|^default:user:alice:r--|^default:user:alice:-*r-*'"
# accept any default ACL that ensures alice has r-- by default for new files; minimal regex leniency:
mark rsudo "$SERVERA" "getfacl -p /srv/secure | grep -Eq '^default:user:alice:.*r'"

# umask 0022 (check /etc/profile or profile.d, and effective for new login)
say "\n[umask (servera)]"
mark rcmd "$SERVERA" "bash -lc 'umask' | grep -xq 0022"

say "\n[Phase 2: SSH hardening on serverb]"
SSHD_T="$(rsudo "$SERVERB" "sshd -T 2>/dev/null" || true)"
PORT="$(awk '/^port /{print $2}' <<<\"$SSHD_T\" | head -n1)"
add; if [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1024 && "$PORT" -ne 22 ]]; then ok; say "PASS: sshd high port $PORT"; else bad; say "FAIL: sshd high port invalid ($PORT)"; fi
add; if gre "$SSHD_T" "^passwordauthentication no"; then ok; say "PASS: PasswordAuthentication no"; else bad; say "FAIL: PasswordAuthentication not no"; fi
add; if gre "$SSHD_T" "^allowgroups webops"; then ok; say "PASS: AllowGroups webops"; else bad; say "FAIL: AllowGroups not webops"; fi
mark rsudo "$SERVERB" "ss -lntp | grep -q \":$PORT .*sshd\""
mark rsudo "$SERVERB" "semanage port -l | grep -E '^ssh_port_t' | grep -Eq '(^|[^0-9])'"$PORT"'([^0-9]|$)'"
mark rsudo "$SERVERB" "firewall-cmd --zone=public --list-ports | grep -qw ${PORT}/tcp"

# password must fail, key must succeed for alice; bob must fail
say "\n[SSH auth behavior (serverb)]"
# password attempt (should fail)
add; if ! ssh $SSHOPTS -p "$PORT" -o PreferredAuthentications=password -o PubkeyAuthentication=no "student@$SERVERB" true; then ok; say "PASS: password login blocked"; else bad; say "FAIL: password login succeeded"; fi
# alice key (assume student created in default ~/.ssh)
add; if ssh $SSHOPTS -p "$PORT" "alice@$SERVERB" 'true'; then ok; say "PASS: alice key login ok"; else bad; say "FAIL: alice key login failed"; fi
# bob key should fail (no group)
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
# not active/enabled, ideally not installed
add; if ! rcmd "$SERVERB" "systemctl is-active httpd 2>/dev/null | grep -qx active"; then ok; say "PASS: httpd not active"; else bad; say "FAIL: httpd active on serverb"; fi
add; if ! rcmd "$SERVERB" "systemctl is-enabled httpd 2>/dev/null | grep -qx enabled"; then ok; say "PASS: httpd not enabled"; else bad; say "FAIL: httpd enabled on serverb"; fi

say "\n[Phase 6: Logging/journald/cockpit]"
# journald persistent
mark rsudo "$SERVERB" "test -d /var/log/journal && journalctl --directory=/var/log/journal -n1 >/dev/null"
# at least 1 failed password and 1 success publickey today
mark rsudo "$SERVERB" "journalctl -S today -u sshd | grep -qi 'Failed password'"
mark rsudo "$SERVERB" "journalctl -S today -u sshd | grep -qi 'publickey'"

# SELinux AVC denial happened today
mark rsudo "$SERVERB" "ausearch -m AVC -ts today | grep -q 'avc:'"
# cockpit firewall service open on both
mark rsudo "$SERVERA" "firewall-cmd --zone=public --list-services | grep -qw cockpit"
mark rsudo "$SERVERB" "firewall-cmd --zone=public --list-services | grep -qw cockpit"

say "\n[Phase 7: Reboot & persistence]"
mark check_reboot "$SERVERA"
mark check_reboot "$SERVERB"

# post-reboot rechecks
say "\n[Post-reboot rechecks]"
add; if ssh $SSHOPTS -p "$PORT" "alice@$SERVERB" 'true'; then ok; say "PASS: alice key login persists"; else bad; say "FAIL: alice key login not persistent"; fi
add; if ! ssh $SSHOPTS -p "$PORT" "bob@$SERVERB" 'true'; then ok; say "PASS: bob remains blocked"; else bad; say "FAIL: bob allowed post-reboot"; fi
add; if curl -sk "https://$SERVERA" | grep -qx "I am servera."; then ok; say "PASS: https persists"; else bad; say "FAIL: https not persistent"; fi
add; if curl -s "http://$SERVERA:82" | grep -q "."; then ok; say "PASS: :82 persists"; else bad; say "FAIL: :82 not persistent"; fi
add; if curl -s "http://$SERVERA:82/x/index.html" | grep -qx "I am servera."; then ok; say "PASS: alias persists"; else bad; say "FAIL: alias not persistent"; fi

# summary + scoring
say "\n=== SUMMARY ==="
say "PASS: $PASS"
say "FAIL: $FAIL"
say "TOTAL CHECKS: $TOTAL"
# numeric score
pct=0
if [ "$TOTAL" -gt 0 ]; then
  pct=$(( 100 * PASS / TOTAL ))
fi
say "SCORE: $PASS/$TOTAL = ${pct}%"

# exit nonzero if any fail (useful in CI), but instructors will use the SCORE line.
[ "$FAIL" -eq 0 ] || exit 1