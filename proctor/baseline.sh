#!/usr/bin/env bash
set -euo pipefail
date -u +"%s" >/root/.exam_start
dnf -y install policycoreutils policycoreutils-python-utils setroubleshoot-server
systemctl enable --now firewalld
setenforce 1