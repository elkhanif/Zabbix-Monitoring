#!/usr/bin/env bash
# Install Zabbix Agent 2 di Ubuntu (desktop/server), mode active + autoregistration (HostMetadata=linux).
#   sudo bash install-agent-ubuntu.sh
# Aman dijalankan ulang: paket dipasang ulang/diupdate, konfigurasi ditulis ulang dengan nilai yang sama.
set -euo pipefail

ZABBIX_SERVER="192.168.0.182"   # IP VM Zabbix
SERIES="7.4"                     # samakan dengan versi server (major.minor)
HOSTNAME_ZBX="$(hostname -s)"    # nama host di Zabbix = nama komputer; harus unik
CONF="/etc/zabbix/zabbix_agent2.conf"

[ "$(id -u)" -eq 0 ] || { echo "Jalankan dengan sudo: sudo bash $0" >&2; exit 1; }

. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
    echo "PERINGATAN: OS ini '${ID:-?}', script ditulis untuk Ubuntu. Lanjut dengan Ctrl+C untuk batal, Enter untuk teruskan."
    read -r _
fi

echo "Memeriksa koneksi ke ${ZABBIX_SERVER}:10051 ..."
if ! timeout 3 bash -c "</dev/tcp/${ZABBIX_SERVER}/10051" 2>/dev/null; then
    echo "PERINGATAN: port 10051 tidak terjangkau. Agent tetap dipasang, tapi belum bisa register."
fi

DEB="zabbix-release_latest_${SERIES}+ubuntu${VERSION_ID}_all.deb"
URL="https://repo.zabbix.com/zabbix/${SERIES}/release/ubuntu/pool/main/z/zabbix-release/${DEB}"
echo "Mengunduh repo Zabbix: ${URL}"
if ! curl -fsSL -o "/tmp/${DEB}" "${URL}"; then
    echo "Gagal mengunduh ${DEB}. Cek versi Ubuntu (${VERSION_ID}) didukung di:" >&2
    echo "  https://repo.zabbix.com/zabbix/${SERIES}/release/ubuntu/pool/main/z/zabbix-release/" >&2
    exit 1
fi
dpkg -i "/tmp/${DEB}"
apt-get update -qq
apt-get install -y zabbix-agent2

cp -n "${CONF}" "${CONF}.orig"
sed -i -E "s|^Server=.*|Server=${ZABBIX_SERVER}|; s|^ServerActive=.*|ServerActive=${ZABBIX_SERVER}|; s|^Hostname=.*|Hostname=${HOSTNAME_ZBX}|" "${CONF}"
if grep -q '^HostMetadata=' "${CONF}"; then
    sed -i -E "s|^HostMetadata=.*|HostMetadata=linux|" "${CONF}"
else
    echo "HostMetadata=linux" >> "${CONF}"
fi

systemctl enable zabbix-agent2 >/dev/null
systemctl restart zabbix-agent2
sleep 2
systemctl --no-pager --lines=0 status zabbix-agent2 || true

echo
echo "Selesai. Host '${HOSTNAME_ZBX}' akan muncul di Zabbix dalam ~1-2 menit (group Linux-PC)."
echo "Log: sudo tail -n 20 /var/log/zabbix/zabbix_agent2.log"
