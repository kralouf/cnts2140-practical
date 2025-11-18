#!/usr/bin/env bash
set -euo pipefail
date -u +"%s" >/root/.exam_start

dnf -y install policycoreutils policycoreutils-python-utils setroubleshoot-server
systemctl enable --now firewalld
setenforce 1

# Ensure no web stack
systemctl disable --now httpd 2>/dev/null || true
dnf -y remove httpd mod_ssl >/dev/null 2>&1 || true

# SSH on high port but *without* SELinux/firewalld initially
NEWPORT=52222
sed -i 's/^#\?Port .*/Port '"$NEWPORT"'/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i '/^AllowGroups/d' /etc/ssh/sshd_config
systemctl enable --now sshd || true
systemctl restart sshd || true  # expect AVC before students label the port

# Firewall baseline
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=cockpit
firewall-cmd --permanent --remove-port="$NEWPORT"/tcp || true
firewall-cmd --reload

# Journald defaults (students will make persistent)
mkdir -p /etc/systemd/journald.conf.d
