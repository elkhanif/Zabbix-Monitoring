# Hyper-V + Zabbix di Windows Server kantor

Dokumentasi langkah instalasi (riwayat kronologis). Diupdate setiap satu langkah selesai.
**Untuk gambaran sistem, runbook, dan status terbaru, baca `DOKUMENTASI-TEKNIS-ZABBIX.md`.** Bagian "Langkah berikutnya" di bawah sudah usang.

## Tujuan
Pindahkan Zabbix server dari laptop (setup percobaan) ke Windows Server 2022 kantor (SERVER-MAZUTA-S, AD). Zabbix server hanya ada untuk Linux, jadi dijalankan di VM Ubuntu di atas Hyper-V, dengan Docker di dalam VM. AD tidak diubah.

Server gudang (Win Server 2022, AD, IP DHCP, beda jaringan) tersambung ke server kantor lewat ZeroTier. Di server gudang cukup dipasang Zabbix Agent 2 yang mengarah ke IP ZeroTier Zabbix server.

## Fakta server kantor
| Item | Nilai |
|---|---|
| Hostname | SERVER-MAZUTA-S |
| CPU / RAM | Intel i3-5005U (2 core) / 16 GB, mesin fisik |
| Cek Hyper-V | VT-x aktif di firmware, SLAT Yes, DEP Yes |
| NIC fisik | `Ethernet 3` (Intel I218-V, 1 Gbps) |
| IP LAN server | 192.168.0.111 (sekarang di `vEthernet (LAN)`) |
| IP ZeroTier server | 192.168.194.211 |
| Disk | Hanya drive C:, kosong 387 GB |

## Log
- 2026-10-02: Hyper-V role terpasang (`Install-WindowsFeature Hyper-V -IncludeManagementTools -Restart`), server sudah restart.
- 2026-10-02: Virtual switch `LAN` (External) dibuat di `Ethernet 3` dengan `-AllowManagementOS $true`. Server tetap dapat IP 192.168.0.111.

- 2026-10-02: ISO `ubuntu-24.04.5-live-server-amd64.iso` (3,8 GB) sudah ada di `C:\ISO\`. Folder `C:\VM\` dibuat.

- 2026-10-02: VM `zabbix` dibuat (Gen2, 2 vCPU, 4 GB, 60 GB, switch `LAN`). DVD drive sempat dobel, sisa satu di location 1. Boot installer gagal: `kernel panic - not syncing: No working init found`.
- 2026-10-02: Penyebab: ISO korup. SHA256 file lokal `67ee109c...` tidak sama dengan resmi `97f3d7ff...fafe0fd8`. Perlu download ulang dan verifikasi hash. Catatan: `Invoke-WebRequest` di PS 5.1 membaca SHA256SUMS sebagai biner, pakai `curl.exe -s`.

- 2026-10-02: Dipakai ISO **Ubuntu 22.04.5 live-server** (bukan 24.04.5 yang korup), instalasi selesai. VM `zabbix` IP **192.168.0.182/22** (mask /22 = 192.168.0.0 sampai 192.168.3.255, mencakup 4 subnet kantor).

- 2026-10-02: SSH ke VM berhasil (`ubuntu-server@192.168.0.182`; hostname VM `ubuntu-server`). Sempat gagal karena izin `~/.ssh/config` di laptop, diperbaiki dengan `icacls` (`/inheritance:r`, `/remove "*S-1-3-4"`, `/grant:r`). Docker 29.8.2 dan Compose v5.5.1 terpasang.

- 2026-10-02: Stack Zabbix (4 container: db, server, web, agent) jalan di VM lewat `docker compose up -d` di `~/zabbix`. Mulai dari database kosong (tidak migrasi). Baris mount `fping-wrapper` dihapus di salinan VM. Insiden: `scp` terpotong saat paste sehingga `fping-wrapper.sh` di laptop tertimpa isi `docker-compose.yml` (file itu tidak terpakai, abaikan). Web: http://192.168.0.182:8080.

- 2026-10-02: Script `setup-autoregistration.ps1` dan `setup-snmp-discovery.ps1` dijalankan ke 192.168.0.182 (4 rule discovery, action per merek, group Laptop-PC). Discovery menemukan 12 host SNMP, macro `{$SNMP_COMMUNITY}` disetel lewat `-SyncMacros`. Tips: token API diisi lewat `$t = Read-Host "Token"` (paste dengan klik kanan, bukan Ctrl+V di prompt secure). Hapus token setelah dipakai. Peringatan: template `Synology DSM by SNMP` belum ada.

- 2026-10-02: `Install-Standalone.ps1` dan `Install-ZabbixAgent2.ps1` (folder `zabbix/deploy`) diubah dari 192.168.0.131 ke 192.168.0.182. Tidak ada lagi referensi ke .131 di folder itu.

- 2026-10-02: Discovery SNMP dipercepat sementara ke interval 1m (HARUS dikembalikan ke 1h/30m). Host hijau 13 (12 SNMP + Zabbix server), laptop sebelumnya 18. Network discovery rule tidak punya tombol Execute now.
- 2026-10-02: Tes agent di PC `IT-SUPPORT2` lewat `deploy\Install.bat`: sukses ("Berhasil"). MSI Agent 2 (`zabbix_agent2-7.4.15-windows-amd64-openssl.msi`, 18,4 MB) disimpan di `zabbix\deploy`. Hati-hati: jangan pakai MSI `zabbix_agent-...` (Agent klasik, salah). Tinggal verifikasi host muncul di Zabbix.

- 2026-10-02: Host `IT-SUPPORT2` muncul di Zabbix. Dibuat `zabbix/deploy/setup-asset-template.ps1` (template "Asset Windows - Hardware", item WMI, action autoregistration kedua, link ke host Laptop-PC) dan `export-assets.ps1` (CSV untuk Excel). Sintaks sudah dicek, BELUM dijalankan ke server. Daftar software ditunda ke tahap kedua. Ada perangkat Linux juga (belum dibahas). Catatan: ID inventory_link (8, 12, 31) belum diverifikasi, cek tab Inventory.

- 2026-10-02: Folder terpisah `zabbix/deploy-linux/` untuk Ubuntu desktop: `install-agent-ubuntu.sh` (Zabbix Agent 2 7.4 dari repo.zabbix.com, HostMetadata=linux) dan `setup-autoregistration-linux.ps1` (group Linux-PC, action "Autoregister Linux", template `Linux by Zabbix agent active`). Belum dijalankan. Aset hardware Linux (serial/model) ditunda.

- 2026-10-02: Template "Asset Windows - Hardware" terpasang, 18 item `Asset:` berisi data di IT-SUPPORT2. Penyebab data awal kosong: interval 12h/1h menunda pengambilan pertama, sekarang interval 1h (Current user 15m); default di script sudah 1h. Item OS tidak di-link ke inventory karena bentrok dengan template Windows bawaan (otomatis dihindari). Monitor hanya "Generic PnP Monitor" (keterbatasan Win32_DesktopMonitor).
- 2026-10-02: Export satu-klik: `deploy/Export-Aset.bat` (+ `run-export-aset.ps1`, memanggil `export-assets.ps1`), hasil CSV di `deploy/hasil/`. Token dari clipboard atau diketik, tidak disimpan. Hanya jalan kalau terhubung ke jaringan kantor/VPN.
- Catatan: agent hanya mengirim data kalau bisa menjangkau 192.168.0.182:10051. Di luar jaringan kantor tidak ada data baru (nilai terakhir tetap tersimpan). Solusi nanti: ZeroTier di VM dan PC, lalu agent menunjuk ke IP ZeroTier VM.

## Langkah berikutnya
1. Buat VM Gen2 `zabbix`: 2 vCPU, 4 GB RAM statis, disk 60 GB di `C:\VM\`, Secure Boot template `MicrosoftUEFICertificateAuthority`, auto start saat server nyala.
3. Install Ubuntu dengan IP statis di LAN kantor (di luar range DHCP) dan OpenSSH server.
4. Install Docker di VM, salin folder `zabbix/` dari laptop, migrasi konfigurasi dan host.
5. Pasang Zabbix Agent 2 di server gudang (active mode, server = IP ZeroTier Zabbix, `HOSTMETADATA=windows`).
6. Revoke API token Zabbix yang sempat ter-paste di chat.
