#!/usr/bin/env bash
set -euo pipefail
date -u +"%s" >/root/.exam_start

dnf -y install policycoreutils policycoreutils-python-utils setroubleshoot-server
systemctl enable --now firewalld
setenforce 1

# Ensure no web stack
systemctl disable --now httpd 2>/dev/null || true
dnf -y remove httpd mod_ssl >/dev/null 2>&1 || true

# Firewall baseline
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=cockpit
firewall-cmd --reload

# Journald defaults (students will make persistent)
mkdir -p /etc/systemd/journald.conf.d
