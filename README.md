# Sistem Voucher Kas Keluar

Purwarupa aplikasi web untuk soal UTS: voucher kas keluar terhubung ke Supabase/PostgreSQL, memakai Supabase Auth, validasi double-entry di database, jurnal `POSTED` yang tidak dapat diubah/dihapus, checksum SHA-256, audit log, dan reversing entry.

## Struktur

- `src/main.js` — antarmuka, autentikasi, validasi live, RPC, riwayat, dan audit.
- `src/styles.css` — gaya antarmuka responsif.
- `supabase/migrations/202610120001_accounting_vouchers.sql` — tabel, RLS, trigger, fungsi RPC, seed bagan akun, checksum, dan audit.
- `.env.example` — template konfigurasi aplikasi lokal.

## Prasyarat

- Node.js 20.19+ atau 22.12+.
- Proyek Supabase.
- Akun GitHub untuk menyimpan dan menerbitkan aplikasi.

## Menyiapkan Supabase

1. Buat proyek di Supabase.
2. Buka **SQL Editor**, jalankan isi file `supabase/migrations/202610120001_accounting_vouchers.sql`.
3. Pastikan tabel bagan akun awal (`Kas`, `Bank`, `Utang Usaha`, dan contoh beban) muncul pada `chart_of_accounts`.
4. Aktifkan **Authentication → Providers → Email**. Untuk demo, atur konfirmasi email sesuai kebijakan proyek; produksi sebaiknya tetap memakai konfirmasi.
5. Dari **Project Settings → API**, salin **Project URL** dan **anon/publishable key**. Jangan pernah menyalin `service_role` key ke frontend.
6. Supabase Auth → URL Configuration: masukkan URL lokal `http://localhost:5173` ke Site URL/Redirect URLs. Setelah deploy GitHub Pages, tambahkan URL GitHub Pages sebagai redirect yang diizinkan.

## Menjalankan secara lokal

```powershell
cd "C:\Users\ASUS\Downloads\UTS PENGKODEAN 1\account-voucher-system"
npm install
Copy-Item .env.example .env
```

Isi `.env`:

```env
VITE_SUPABASE_URL=https://PROJECT_REF.supabase.co
VITE_SUPABASE_ANON_KEY=SUPABASE_ANON_OR_PUBLISHABLE_KEY
```

Lalu jalankan:

```powershell
npm run dev
```

Buka alamat yang ditampilkan Vite, biasanya `http://localhost:5173`. Buat akun dengan email/password, konfirmasi jika diwajibkan proyek, lalu masuk.

## Aturan bisnis dan kontrol

- Browser menghitung total secara live dalam satuan sen, menampilkan selisih, dan menonaktifkan tombol submit sebelum input valid.
- Validasi browser bukan kontrol keamanan. RPC `create_cash_voucher` mengulang validasi akun, jumlah baris, debit-kredit seimbang, dan aturan kas keluar di dalam PostgreSQL.
- Hanya akun kas/bank yang dikreditkan untuk voucher kas keluar. Transfer internal sebaiknya memakai jenis voucher terpisah.
- Pembuatan header, baris, checksum, dan perubahan status `DRAFT` → `POSTED` berjalan atomik di database.
- RLS membatasi riwayat ke pemilik jurnal. Klien tidak diberi hak langsung untuk menulis/menghapus tabel jurnal.
- Trigger menolak modifikasi header/baris jurnal yang sudah `POSTED`; koreksi menggunakan RPC `reverse_cash_voucher`.
- `audit_log` merekam operasi pada header/baris. Aplikasi hanya dapat melihat audit voucher miliknya melalui RPC `get_voucher_audit`.
- Hash dapat diverifikasi melalui `verify_voucher_checksum`. Hash mendeteksi perubahan data, tetapi bukan perlindungan dari administrator database berhak istimewa.

## Menghubungkan ke GitHub dan deploy

Di folder aplikasi, buat repository kosong di GitHub, lalu:

```powershell
git init
git add .
git commit -m "Build Supabase cash voucher prototype"
git branch -M main
git remote add origin https://github.com/USERNAME/REPOSITORY.git
git push -u origin main
```

Tambahkan repository variables di **Settings → Secrets and variables → Actions → Variables**:

- `VITE_SUPABASE_URL` — URL proyek Supabase.
- `VITE_SUPABASE_ANON_KEY` — anon/publishable key. Key ini memang dipakai di browser; keamanan tabel tetap bergantung pada RLS dan fungsi RPC.

Aktifkan **Settings → Pages → Build and deployment → Source: GitHub Actions**. Workflow `.github/workflows/deploy-pages.yml` sudah disertakan. Setelah repository memiliki branch `main`, konfigurasi kedua variables di atas, dan sumber GitHub Pages diatur ke GitHub Actions, setiap push ke `main` akan membangun dan menerbitkan aplikasi.

## Catatan

Ini purwarupa akademik, bukan sistem produksi. Sebelum pemakaian nyata, tambahkan review hak akses, kebijakan nomor bukti, periode akuntansi, pembatasan besaran input, klasifikasi arus kas, multi-currency, kebijakan pengelolaan kas/setara kas sesuai PSAK, dan pengujian pada proyek Supabase tersendiri. Migration ini belum dieksekusi terhadap proyek Supabase karena kredensial/proyek pengguna tidak tersedia di workspace.
