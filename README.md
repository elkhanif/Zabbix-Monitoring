# Zabbix: monitoring dan inventaris aset kantor

Setup Zabbix 7.4 (VM Ubuntu di Hyper-V, Docker Compose) untuk memantau PC, server, dan perangkat jaringan, plus export inventaris aset hardware ke CSV/Excel.

**Mulai dari sini:** [`docs/DOKUMENTASI-TEKNIS-ZABBIX.md`](docs/DOKUMENTASI-TEKNIS-ZABBIX.md) (arsitektur, runbook, status, dan daftar pekerjaan tersisa).
Riwayat kronologis setup: [`docs/hyperv-zabbix-setup.md`](docs/hyperv-zabbix-setup.md).

## Isi
| Folder | Fungsi |
|---|---|
| `zabbix/docker-compose.yml` | Stack Zabbix (db, server, web, agent) |
| `zabbix/deploy/` | Script setup server (autoregistration, SNMP discovery, template aset) dan export aset |
| `zabbix/deploy-windows/` | Installer Agent 2 untuk PC Windows (taruh MSI di folder ini, lihat di bawah) |
| `zabbix/deploy-linux/` | Installer Agent 2 untuk Ubuntu |

## File yang tidak ada di repo
- **MSI Agent 2**: unduh `zabbix_agent2-7.4.15-windows-amd64-openssl.msi` dari <https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.15/> dan taruh di `zabbix/deploy-windows/` (dan `zabbix/deploy/` kalau dipakai dari sana). Jangan pakai `zabbix_agent-...` (tanpa angka 2).
- **Hasil export** (`aset-*.csv`, `hasil/`): berisi data PC kantor, sengaja tidak di-commit.
- **Password/token/community SNMP**: tidak ada di repo. Password database di `docker-compose.yml` masih nilai bawaan dan perlu diganti (lihat dokumentasi teknis bagian 9).
