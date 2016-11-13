#!/bin/sh

cat >> /etc/rc.conf << EOF
hostname="freebsd"
powerd_enable="YES"
sshd_enable="YES"
sendmail_enable="NO"
ifconfig_ue0="DHCP"
ntpd_enable="YES"
ntpd_sync_on_start="YES"
lighttpd_enable="YES"
lighttpd_logdir_enable="YES"
EOF

echo '172.0.0.1 freebsd freebsd.my.domain' >> /etc/hosts

mkdir -p /usr/local/www/data
chmod a+x /usr/local/etc/rc.d/lighttpd_logdir

pw useradd -m -n freebsd
pw group mod wheel -m freebsd
pw group mod operator -m freebsd
echo "freebsd" | pw mod user freebsd -h 0
