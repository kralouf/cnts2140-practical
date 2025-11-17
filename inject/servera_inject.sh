#!/usr/bin/env bash
set -euo pipefail
date -u +"%s" >/root/.exam_start

dnf -y install httpd mod_ssl policycoreutils policycoreutils-python-utils setroubleshoot-server
systemctl enable --now firewalld
setenforce 1

echo 'I am servera.' >/var/www/html/index.html
chown root:root /var/www/html/index.html
chmod 0644 /var/www/html/index.html

# Ensure aliasable extra dir exists (students will label it for httpd)
mkdir -p /srv/www-extra
cp -f /var/www/html/index.html /srv/www-extra/

# Nonstandard 82 listener pre-created but SELinux/firewalld NOT opened yet
cat >/etc/httpd/conf.d/listen-82.conf <<'EOF'
Listen 82
<VirtualHost *:82>
    DocumentRoot "/var/www/html"
    <Directory "/var/www/html">
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Create permission targets (students must fix modes & ACLs)
mkdir -p /srv/shared /srv/drop /srv/secure
chmod 0755 /srv/shared /srv/drop /srv/secure

# Firewall: force students to open right services/ports
firewall-cmd --permanent --remove-service=http || true
firewall-cmd --permanent --remove-service=https || true
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=cockpit
firewall-cmd --reload

systemctl enable httpd || true
systemctl restart httpd || true