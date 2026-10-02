# Dokumentasi Teknis: Monitoring & Inventaris Aset dengan Zabbix

Terakhir diperbarui: 2026-10-02. Dokumen ini ditulis supaya orang yang baru membacanya paham sistemnya, dan orang yang meneruskan pekerjaan tahu harus mulai dari mana.
Riwayat langkah demi langkah (kronologis, termasuk kesalahan yang terjadi) ada di `docs/hyperv-zabbix-setup.md`.

> Tidak ada password, token, atau community SNMP di dokumen ini. Lokasi penyimpanannya dijelaskan di bagian 4.

---

## 1. Tujuan dan ruang lingkup

Kantor memakai Active Directory (AD) tapi tidak efektif, karena banyak PC memakai IP DHCP yang berubah-ubah. Zabbix dipakai untuk:

1. **Monitoring** PC/laptop, server, dan perangkat jaringan (AP, router, printer, NVR).
2. **Inventaris aset hardware** PC (merek, model, serial, CPU, RAM, disk, OS, dst.) yang bisa di-export ke Excel.

AD **tidak diubah dan tetap berjalan**. Zabbix berjalan berdampingan, tidak menggantikan fungsi login/GPO AD.

**Dalam ruang lingkup sekarang:** jaringan kantor, PC Windows, server Windows, perangkat SNMP.
**Belum:** server gudang, PC Linux (script siap, belum dipakai), daftar software, akses dari luar kantor. Lihat bagian 9.

---

## 2. Arsitektur

```
 Jaringan kantor 192.168.0.0/22  (mencakup 192.168.0.x s/d 192.168.3.x)

 +-----------------------------------------------+
 | Windows Server 2022  "SERVER-MAZUTA-S"        |   AD kantor
 | IP LAN 192.168.0.111 | ZeroTier 192.168.194.211|   (tidak diubah)
 |                                               |
 |   Hyper-V  (virtual switch "LAN" -> NIC fisik)|
 |     +-----------------------------------+     |
 |     | VM Ubuntu 22.04  192.168.0.182/22 |     |
 |     |   Docker Compose                  |     |
 |     |   - zabbix-db     (PostgreSQL 16) |     |
 |     |   - zabbix-server (port 10051)    |     |
 |     |   - zabbix-web    (port 8080)     |     |
 |     |   - zabbix-agent  (memantau VM)   |     |
 |     +-----------------------------------+     |
 +-----------------------------------------------+
        ^                    ^                    ^
        | agent (active)     | SNMP polling       | web 8080 (admin)
        | -> 10051           | dari server        |
   PC / laptop         AP, router, printer,     laptop admin
   Windows & Linux     NVR                      (browser + script)
```

Dua cara data masuk ke Zabbix:

| Cara | Untuk | Arah koneksi |
|---|---|---|
| **Agent Zabbix 2, mode active** | PC, laptop, server | Agent **keluar** ke `192.168.0.182:10051`. Tidak perlu port masuk di PC. Perangkat dikenali dari **hostname**, jadi IP DHCP berubah tidak masalah. |
| **SNMP discovery** | AP, router, printer, NVR | Server memindai range IP, lalu polling perangkat. Perangkat dikenali dari **IP**, jadi sebaiknya IP-nya tetap (DHCP reservation). |

Server gudang (Win Server 2022, AD sendiri, beda jaringan) tersambung ke server kantor lewat **ZeroTier**. Rencana integrasinya ada di bagian 9.

---

## 3. Inventaris komponen

| Komponen | Detail |
|---|---|
| Server host | Windows Server 2022, hostname `SERVER-MAZUTA-S`, Intel i3-5005U (2 core), 16 GB RAM, mesin fisik. Disk hanya drive C:. |
| IP host | LAN `192.168.0.111` (adapter `vEthernet (LAN)`), ZeroTier `192.168.194.211`. Tailscale juga terpasang. |
| Hyper-V | Role terpasang. Virtual switch `LAN` (External) di NIC fisik `Ethernet 3` (Intel I218-V). |
| VM Zabbix | Nama VM `zabbix`, Generation 2, 2 vCPU, 4 GB RAM statis, disk 60 GB di `C:\VM\zabbix.vhdx`, Secure Boot template `MicrosoftUEFICertificateAuthority`. Auto start saat host nyala (diset, belum diuji dengan restart server). |
| OS VM | Ubuntu Server **22.04.5** LTS. Hostname `ubuntu-server`, IP statis `192.168.0.182/22`, OpenSSH aktif. Catatan: ISO 24.04.5 sempat dipakai tapi file-nya korup, jadi diganti 22.04.5. |
| Docker di VM | Docker Engine 29.8.2, Compose v5.5.1. Folder kerja `~/zabbix` di VM. |
| Zabbix | Versi 7.4.x (image `latest`, saat setup resolve ke 7.4.15). Agent PC dipasang 7.4.15. |
| Web Zabbix | `http://192.168.0.182:8080` |
| Port | 8080 (web), 10051 (Zabbix server, menerima data agent), 22 (SSH VM). |
| Folder ISO | `C:\ISO\` di host (berisi ISO Ubuntu). |

---

## 4. Akses dan penyimpanan rahasia

| Hal | Di mana | Catatan |
|---|---|---|
| Login web Zabbix | Akun `Admin` | Password harus sudah diganti dari bawaan. Simpan di password manager tim. **Verifikasi** (bagian 9). |
| SSH ke VM | `ssh ubuntu-server@192.168.0.182` | Password di password manager. |
| Password database | Di `docker-compose.yml` (VM dan laptop), nilai bawaan lemah | **Perlu diganti**. Lihat bagian 9. |
| Community SNMP | Macro Zabbix `{$SNMP_COMMUNITY}` | Global: **Administration → Macros**. Per host: tab Macros host. Nilai tidak ditulis di sini. |
| API token | Dibuat sementara di web | **Selalu hapus setelah dipakai** (Users → API tokens). Jangan paste ke chat/dokumen. |

Catatan teknis SSH dari Windows: kalau muncul `Bad owner or permissions on ...\.ssh\config`, perbaiki izin file dengan `icacls`:
`icacls $f /inheritance:r; icacls $f /remove "*S-1-3-4"; icacls $f /grant:r "${env:USERNAME}:F"`.

---

## 5. Peta file di folder `zabbix/`

| Path | Fungsi | Dijalankan di |
|---|---|---|
| `docker-compose.yml` | Definisi 4 container Zabbix | VM (`docker compose up -d`) |
| `zabbix_server_locations.conf` | Lokasi `fping` dll. untuk server | Di-mount ke container server |
| `fping-wrapper.sh` | **Tidak terpakai** (sudah tidak dipanggil). Isinya sempat tertimpa tak sengaja. Aman diabaikan atau dihapus. | - |
| `deploy-windows/` | **Paket siap bagi** untuk PC Windows: `Install.bat`, `Install-Standalone.ps1`, MSI Agent 2 (MSI tidak ada di repo, unduh sendiri). Server target sudah 192.168.0.182. Juga `Update-ZabbixServer.bat/.ps1` (**darurat**: mengganti alamat server di agent yang sudah terpasang, lihat 7.7). | PC target |
| `deploy-windows.rar` | Arsip paket di atas | - |
| `deploy/` | Folder kerja admin. Berisi script setup server dan export aset (tabel di bawah). Juga salinan paket PC. | Laptop admin |
| `deploy-linux/` | `install-agent-ubuntu.sh` dan `setup-autoregistration-linux.ps1` untuk PC Ubuntu. **Belum pernah dijalankan.** | PC Ubuntu / laptop admin |

Isi `deploy/`:

| File | Fungsi | Kapan dipakai |
|---|---|---|
| `setup-autoregistration.ps1` | Membuat grup `Laptop-PC` + action "Autoregister Windows" (tambah host, grup, template Windows, inventory otomatis) | Sekali per server Zabbix baru |
| `setup-snmp-discovery.ps1` | Membuat 4 rule discovery SNMP (per /24) + action per merek. Opsi `-SyncMacros` mengisi macro community di host yang baru ditemukan. | Sekali, lalu `-SyncMacros` setelah ada host baru |
| `setup-asset-template.ps1` | Membuat template "Asset Windows - Hardware" (18 item WMI), action "Autoregister Windows - Asset", dan memasangnya ke host `Laptop-PC` yang ada. Aman diulang. | Sekali per server |
| `export-assets.ps1` | Menarik data aset semua host `Laptop-PC` via API menjadi CSV | Dipanggil script lain atau manual |
| `Export-Aset.bat` + `run-export-aset.ps1` | **Export satu klik**: token dari clipboard/diketik, CSV masuk ke `deploy/hasil/` | Setiap butuh laporan |
| `Install.bat` + `Install-Standalone.ps1` | Installer Agent 2 untuk PC non-domain | Per PC |
| `Install-ZabbixAgent2.ps1` | Versi untuk GPO (butuh share `\\FILESERVER\ZabbixAgent`) | **Tidak dipakai**, karena banyak PC tidak terhubung AD |
| `zabbix_agent2-7.4.15-windows-amd64-openssl.msi` | Installer Agent 2. **Bukan** `zabbix_agent-...` (agent klasik, salah). | - |

---

## 6. Konfigurasi di Zabbix

### 6.1 Host group
| Group | Isi |
|---|---|
| `Laptop-PC` | PC/laptop Windows (otomatis lewat autoregistration) |
| `Network` | AP, router, switch |
| `Printer` | Printer Epson/Kyocera |
| `Camera-NVR` | NVR Hikvision |
| `NAS` | Synology (belum ada perangkatnya terdeteksi) |
| `Linux-PC` | Dibuat oleh `setup-autoregistration-linux.ps1` (belum dijalankan) |

### 6.2 Autoregistration (agent)
Agent mengirim `HostMetadata=windows` (atau `linux`). Action mencocokkan metadata dan otomatis: menambah host, memasukkan ke grup, me-link template, mengatur **inventory mode = Automatic**.

| Action | Kondisi | Template yang di-link |
|---|---|---|
| Autoregister Windows | metadata mengandung `windows` | `Windows by Zabbix agent active` |
| Autoregister Windows - Asset | metadata mengandung `windows` | `Asset Windows - Hardware` |
| Autoregister Linux *(belum dibuat)* | metadata mengandung `linux` | `Linux by Zabbix agent active` |

### 6.3 SNMP discovery
- 4 rule: `SNMP Discovery 192.168.0.0/24` sampai `192.168.3.0/24` (satu rule per /24 karena satu rule besar kena batas waktu fping). Check: SNMP get `sysDescr` (1.3.6.1.2.1.1.1.0) dengan community `{$SNMP_COMMUNITY}`.
- Interval normal: **1 jam**. (Rule jaringan tidak punya tombol "Execute now". Untuk memicu cepat, turunkan interval sementara ke 1m lalu kembalikan.)
- Action per merek mencocokkan `sysDescr`: Ubiquiti, TP-Link Switch, TP-Link Omada Router, Ruijie Switch, Hikvision, Synology NAS, Epson, Kyocera. Masing-masing menambah host ke grup yang sesuai dan me-link template SNMP-nya.
- Hasil terakhir: **12 host SNMP** terdeteksi (laptop percobaan sebelumnya 18). Selisih belum diselidiki.

### 6.4 Template "Asset Windows - Hardware"
18 item, tipe Zabbix agent (active), tag `component: asset`. Semua memakai kunci `wmi.get` / `wmi.getall` (hanya Windows, Agent 2).

| Item | Sumber WMI | Interval |
|---|---|---|
| Manufacturer, Model | Win32_ComputerSystem | 1h |
| Serial number | Win32_BIOS | 1h |
| CPU | Win32_Processor | 1h |
| Motherboard | Win32_BaseBoard | 1h |
| TPM | Win32_Tpm (namespace `root\cimv2\Security\MicrosoftTpm`) | 1h |
| RAM total (bytes), RAM modules | Win32_ComputerSystem, Win32_PhysicalMemory | 1h |
| GPU | Win32_VideoController | 1h |
| Monitor | Win32_DesktopMonitor | 1h |
| Disks | Win32_DiskDrive | 1h |
| Printers | Win32_Printer | 1h |
| OS, OS details | Win32_OperatingSystem | 1h |
| Network adapters, MAC address | Win32_NetworkAdapterConfiguration (IPEnabled) | 1h |
| Current user | Win32_ComputerSystem.UserName | 15m |
| Domain or workgroup | Win32_ComputerSystem.Domain | 1h |

Item berisi daftar disimpan sebagai **JSON**; `export-assets.ps1` mengubahnya jadi teks ringkas dan ukuran byte jadi GB.

Link ke tab **Inventory** (`inventory_link`): ID 5=OS, 14=hardware, 29=model sudah dikonfirmasi dokumentasi Zabbix; **8 (serial), 12 (MAC), 31 (vendor) belum diverifikasi**. Field yang sudah dipakai template Windows bawaan (mis. OS lewat `system.sw.os`) otomatis dihindari script, karena Zabbix melarang dua item mengisi field inventory yang sama. Export CSV tidak bergantung pada tab Inventory (membaca nilai item langsung).

---

## 7. Prosedur operasional (runbook)

### 7.1 Menambah PC Windows baru
1. Salin folder `deploy-windows/` (isi: `Install.bat`, `Install-Standalone.ps1`, MSI Agent 2) ke PC itu.
2. Klik dua kali `Install.bat` → setujui prompt admin → tunggu "Berhasil".
3. Dalam 1-2 menit host muncul di grup `Laptop-PC`. Data aset penuh muncul dalam sekitar 1 jam (interval item).

Syarat: PC bisa menjangkau `192.168.0.182:10051`; **nama komputer unik**.

### 7.2 Menambah PC Ubuntu (belum diuji)
Jalankan `setup-autoregistration-linux.ps1` sekali dari laptop admin, lalu di tiap Ubuntu: `sudo bash install-agent-ubuntu.sh`. Data aset hardware Linux (serial/model) belum ada.

### 7.3 Export laporan aset
1. Web Zabbix: **Users → API tokens → Create API token**, copy.
2. Klik dua kali `deploy/Export-Aset.bat`. CSV di `deploy/hasil/aset-TANGGAL-JAM.csv`.
3. Hapus token di Zabbix.

Pemisah kolom CSV mengikuti pengaturan regional Windows (`-UseCulture`): titik koma di Indonesia. File tidak bisa ditimpa kalau masih terbuka di Excel.

### 7.4 Deploy ulang / pindah ke server lain
Prasyarat: mesin Linux (VM Hyper-V atau fisik) dengan Docker + Compose. Zabbix server tidak berjalan di Windows.

**Kunci kemudahan: beri server baru IP yang sama (`192.168.0.182`).** Matikan server lama dulu agar tidak bentrok. Dengan IP yang sama, semua agent di PC langsung tersambung lagi tanpa diubah. Kalau IP harus beda, lihat 7.7.

**Pilihan A: mulai bersih** (cukup untuk kondisi sekarang, data masih sedikit)
1. Siapkan VM Ubuntu + Docker (urutan di `docs/hyperv-zabbix-setup.md`: Hyper-V, virtual switch, VM Gen2, Ubuntu 22.04, IP statis, Docker).
2. Clone repo, salin `zabbix/docker-compose.yml` dan `zabbix/zabbix_server_locations.conf` ke `~/zabbix` di VM. Hapus baris mount `fping-wrapper` bila ada. Ganti password database lewat `.env`. Lalu `docker compose up -d`.
3. Buka web `:8080`, login `Admin` (password bawaan), **langsung ganti password**, buat API token.
4. Dari laptop admin jalankan berurutan, memakai `-Url` server baru:
   `setup-autoregistration.ps1` → `setup-snmp-discovery.ps1` (lalu `-SyncMacros` setelah host muncul) → `setup-asset-template.ps1`. Hapus token setelah selesai.
5. Agent PC: kalau IP sama, host muncul sendiri lewat autoregistration. Kalau IP beda, lihat 7.7.
Yang hilang: riwayat grafik/metrik lama dan host manual yang dibuat lewat web (host otomatis dibuat ulang).

**Pilihan B: pindahkan database** (mempertahankan riwayat dan semua pengaturan manual). *Belum diuji.*
1. Di server lama: `docker exec zabbix-db pg_dump -U zabbix -d zabbix -Fc > ~/zabbix.dump`, salin file ke server baru.
2. Di server baru: `docker compose up -d zabbix-db` **saja** (jangan jalankan server dulu supaya skema kosong tidak dibuat). Tunggu siap, lalu `docker exec -i zabbix-db pg_restore -U zabbix -d zabbix --clean --if-exists < ~/zabbix.dump`.
3. `docker compose up -d`. Versi Zabbix server baru harus **sama atau lebih baru** dari yang lama (server menaikkan skema sendiri; tidak bisa turun versi). Pin tag image di compose agar pasti.
4. Setelah naik, cek **Reports → System information** (tidak ada error) dan **Data collection → Hosts** (host dan data masih ada).
Catatan: password database di compose baru harus sama dengan yang ada di dump, atau jalankan `ALTER USER`.

### 7.5 Cara aman memakai API token di PowerShell
`$t = Read-Host "Token"` lalu paste dengan **klik kanan** (Ctrl+V tidak bekerja di prompt secure). Setelah selesai: hapus token di web, `Remove-Variable t`. Jangan paste output terminal yang memuat token ke chat/dokumen.

### 7.6 Perintah berguna di VM
```bash
cd ~/zabbix
docker compose ps                     # status container
docker compose logs -f zabbix-server  # log server
docker compose restart                # restart semua
docker compose pull && docker compose up -d   # upgrade image (baca catatan versi di bagian 8)
```

### 7.7 Kalau IP server Zabbix berubah (darurat)
**Dampak:** alamat server tertulis di tiap agent (`Server=` dan `ServerActive=` di `zabbix_agent2.conf`). Kalau IP VM berubah, semua PC berhenti mengirim data dan hostnya satu per satu jadi merah. Polling SNMP (AP, printer, dll.) tetap jalan karena server yang menghubungi perangkat.

**Pencegahan (lakukan lebih dulu, lihat bagian 9):** IP `192.168.0.182` statis di Ubuntu, harus di-**kecualikan/reservasi di DHCP router**, dan jangan diubah tanpa rencana. Opsi lain: pakai nama DNS di agent (hanya efektif kalau PC memakai DNS yang me-resolve nama itu).

**Perbaikan kalau terjadi:**
1. Pastikan server baru bisa dijangkau di IP baru (`Test-NetConnection <IP> -Port 10051`).
2. Di tiap PC Windows jalankan (sebagai Administrator) script dari `zabbix/deploy-windows/`:
   `Update-ZabbixServer.bat <IP-baru>`  (atau `Update-ZabbixServer.ps1 -NewServer <IP-baru>`)
   Script mengecek koneksi, membuat cadangan `zabbix_agent2.conf.bak-<tanggal>`, mengganti hanya `Server=` dan `ServerActive=`, lalu restart service "Zabbix Agent 2". Aman dijalankan ulang.
3. PC Ubuntu: ubah dua baris yang sama di `/etc/zabbix/zabbix_agent2.conf`, lalu `sudo systemctl restart zabbix-agent2`.
4. Ubah `$ZabbixServer` di `Install-Standalone.ps1` (kedua salinan: `deploy/` dan `deploy-windows/`) dan `Install-ZabbixAgent2.ps1` supaya PC baru memakai IP baru, serta `$ZabbixUrl` di `run-export-aset.ps1`.
5. Catat IP baru di dokumentasi ini (bagian 3) dan commit.

Script ini harus dijalankan di tiap PC (tidak ada kendali terpusat), jadi kerjanya sebanding jumlah PC. Itu alasan pencegahan di atas lebih penting.

---

## 8. Keputusan desain dan alasannya

| Keputusan | Alasan |
|---|---|
| Zabbix di VM Linux di atas Hyper-V | Zabbix server hanya ada untuk Linux. Hyper-V sudah termasuk di Windows Server (tanpa Docker Desktop yang berat). VM terpisah dari AD, resource-nya bisa dibatasi. |
| Agent **active**, bukan passive | PC berganti IP (DHCP). Active memakai hostname dan koneksi keluar saja, jadi tidak perlu IP tetap atau port masuk. |
| Autoregistration lewat `HostMetadata` | PC baru terdaftar sendiri, tanpa input manual. |
| Installer standalone, bukan GPO | Banyak PC tidak terhubung ke AD. |
| Mulai database kosong di server baru | Data laptop hanya 18 host hasil discovery, bisa dibuat ulang otomatis. Menghindari migrasi `pg_dump` dan membawa data uji/token lama. |
| Aset diambil via WMI, bukan software list | Cukup untuk laporan hardware. Daftar software ditunda (butuh UserParameter PowerShell di tiap PC). |
| Interval item aset 1h (bukan 12h) | Agent 2 menunda pengambilan pertama item berinterval panjang sampai hingga satu interval. Dengan 12h, PC baru kosong sampai setengah hari. |
| Export lewat script API | Zabbix tidak punya export CSV/Excel untuk data ini. |
| Image `latest` | Dipakai agar cepat. **Sebaiknya di-pin** ke 7.4 agar upgrade mayor tidak terjadi tak sengaja. |

---

## 9. Status dan pekerjaan yang tersisa

Urutan prioritas. Tanda **[cek]** = saya tidak punya bukti selesai, harus diverifikasi dulu.

### Keamanan dan keandalan (kerjakan lebih dulu)
- [ ] **[cek]** Password `Admin` Zabbix sudah diganti dari bawaan.
- [ ] Ganti password database di `docker-compose.yml` (sekarang bawaan, lemah), lalu `docker compose down && up -d` (volume database lama menyimpan password lama, jadi perlu `ALTER USER` di PostgreSQL atau hapus volume kalau data masih kosong).
- [ ] **[cek]** Interval keempat rule discovery SNMP sudah dikembalikan dari 1m ke 1h/30m.
- [ ] **IP `192.168.0.182` jangan diubah**, dan **kecualikan/reservasi di DHCP router** supaya tidak dibagikan ke perangkat lain. Kalau tetap berubah: prosedur dan script darurat ada di 7.7 (`Update-ZabbixServer`). Sudah di-reservasi di router? **[cek]**
- [ ] **[cek]** Semua API token (termasuk yang bocor di chat dan token asset) sudah dihapus.
- [ ] Uji restart Windows Server: VM `zabbix` harus nyala otomatis dan container ikut naik (`restart: unless-stopped` sudah diset).
- [ ] Backup: belum ada. Minimal `pg_dump` terjadwal dan snapshot/ekspor VM. Backup folder `zabbix/` di luar mesin ini.
- [ ] **[cek]** Stack Zabbix lama di laptop admin sudah dimatikan (`docker compose down`, tanpa `-v`).
- [ ] Pin versi image Zabbix ke 7.4 dan samakan dengan versi agent.

### Fungsional
- [ ] **12 vs 18 host SNMP**: cari perangkat yang belum terdeteksi (Monitoring → Discovery). Cek jangkauan jaringan dari VM, community, dan kecocokan `sysDescr` dengan action.
- [ ] DHCP reservation untuk AP, printer, NVR, switch (discovery mengenali via IP). Pastikan IP VM Zabbix (`192.168.0.182`) di luar range DHCP.
- [ ] Switch **TP-Link / Ruijie** belum terdeteksi (community Ruijie belum diketahui).
- [ ] **Synology**: template `Synology DSM by SNMP` tidak ditemukan; NAS belum ada.
- [ ] Item Ubiquiti: client-count dan CPU belum ada.
- [ ] **Redam alert berisik** template Windows (service Automatic yang berhenti sendiri: Brave/Google Updater/Intel/Sensor, dst.). Atur macro filter service di template (nama macro cek langsung di Data collection → Templates → macros) atau hapus trigger yang tidak relevan.
- [ ] Rollout agent ke semua PC (sekarang 2 PC di `Laptop-PC`).
- [ ] Verifikasi ID `inventory_link` 8, 12, 31 di tab Inventory.
- [ ] Monitor: `Win32_DesktopMonitor` hanya menghasilkan "Generic PnP Monitor". Perlu sumber lain (`WmiMonitorID`) kalau merek/serial monitor dibutuhkan.

### Fase berikutnya
- [ ] **Server gudang**: pasang Agent 2. Jalur: ZeroTier. Pasang ZeroTier di VM Zabbix, agent gudang menunjuk ke IP ZeroTier VM. Untuk perangkat lain di gudang: managed route ZeroTier lewat server gudang, atau Zabbix Proxy (butuh VM Linux di gudang).
- [ ] **Akses di luar kantor**: agent hanya mengirim data kalau menjangkau `192.168.0.182:10051`. Di luar kantor tidak ada data baru (nilai terakhir tetap tersimpan, host tampak merah). Solusi: ZeroTier di semua PC dan agent menunjuk ke IP ZeroTier VM.
- [ ] **PC Linux**: jalankan `setup-autoregistration-linux.ps1` lalu installer di Ubuntu; tambah item aset Linux.
- [ ] **Daftar software** per PC (registry Uninstall lewat UserParameter PowerShell, sheet kedua di CSV).
- [ ] Export terjadwal otomatis (token baca-saja, user Zabbix terpisah).

---

## 10. Pelajaran / jebakan yang sudah ditemui

| Gejala | Penyebab | Solusi |
|---|---|---|
| `kernel panic - No working init found` saat install Ubuntu | File ISO korup (ukuran sama, hash beda) | Selalu cocokkan SHA256 dengan `SHA256SUMS`. Pakai `curl.exe -L -C -`, bukan `Start-BitsTransfer`/`Invoke-WebRequest`. |
| `Invoke-WebRequest` pada `SHA256SUMS` tidak menampilkan apa-apa | PowerShell 5.1 membaca isinya sebagai byte | Pakai `curl.exe -s`. |
| `Set-VMFirmware -FirstBootDevice` error "System.Object[]" | VM punya dua DVD drive | Hapus salah satu dengan `Remove-VMDvdDrive`. |
| `scp` menimpa file lokal | Perintah panjang terpotong saat paste, jadi tujuan SSH hilang | Satu file per perintah `scp`. |
| `invalid Control characters` saat memakai token | Ctrl+V pada prompt secure memasukkan karakter kontrol; token jadi 1 karakter | Paste dengan klik kanan, cek `$t.Length` = 64. |
| Item `Asset:` "No data found" | Interval 12h menunda pengambilan pertama | Interval 1h. Percepat dengan Mass update interval ke 5m lalu kembalikan. |
| `host.massadd`: "inventory field OS already populated" | Template Windows bawaan sudah mengisi field itu | Script otomatis menghindari field yang bentrok. |
| Export CSV: "file is being used by another process" | CSV terbuka di Excel | Tutup Excel; nama file default sekarang memuat jam-menit. |
| CSV berisi `Count=1, Length=1...` | `ConvertFrom-Json` PS 5.1 mengembalikan array sebagai satu objek | Sudah diperbaiki di `export-assets.ps1` (memakai `foreach`). |
| Alert "service not running" banyak | Template Windows memantau semua service Automatic | Lihat bagian 9 (redam alert). |
| Rule discovery tidak punya "Execute now" | Memang fitur ini hanya untuk LLD item | Turunkan interval sementara. |

---

## 11. Referensi
- Zabbix 7.4 dokumentasi: https://www.zabbix.com/documentation/7.4/
- Unduhan agent: https://www.zabbix.com/download_agents (MSI Agent 2 langsung: `https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.15/`)
- Repo Ubuntu: https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/
- Kunci item WMI: `wmi.get[namespace,query]` (nilai pertama) dan `wmi.getall[namespace,query]` (JSON semua baris), Windows, Agent 2.
