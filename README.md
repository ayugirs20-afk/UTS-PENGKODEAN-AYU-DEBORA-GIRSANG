# Sistem Voucher Kas Keluar

Purwarupa aplikasi web untuk soal UTS: voucher kas keluar terhubung ke Supabase/PostgreSQL, memakai Supabase Auth, validasi double-entry di database, jurnal `POSTED` yang tidak dapat diubah/dihapus, checksum SHA-256, audit log, dan reversing entry.

## Struktur

- `src/main.js` — antarmuka, autentikasi, validasi live, RPC, riwayat, dan audit.
- `src/voucher-validation.js` — validasi header dan baris jurnal yang dipakai antarmuka.
- `tests/voucher-validation.test.js` — uji otomatis validasi voucher di browser.
- `src/styles.css` — gaya antarmuka responsif.
- `supabase/migrations/202610120001_accounting_vouchers.sql` — skema voucher, RLS, trigger, RPC, seed akun, checksum, dan audit append-only.
- `supabase/tests/audit_trail.sql` — uji transaksi, immutability, checksum, audit log, dan reversal; seluruh data uji di-rollback.
- `.env.example` — template konfigurasi aplikasi lokal.

## Prasyarat

- Node.js 20.19+ atau 22.12+.
- Proyek Supabase.
- Akun GitHub untuk menyimpan dan menerbitkan aplikasi.

## Menyiapkan Supabase

1. Buat proyek di Supabase.
2. Buka **SQL Editor**, jalankan isi file `supabase/migrations/202610120001_accounting_vouchers.sql`.
   - Migration dapat melengkapi tabel `chart_of_accounts`, `journal_headers`, dan `journal_lines` yang sudah ada, tanpa menghapus tabel persediaan.
   - Jika ditemukan jurnal lama yang belum memiliki `created_by`, migration berhenti dan meminta pemetaan pemilik sebelum melanjutkan; migration tidak mengarang identitas pemilik.
3. Pastikan akun awal (`Kas`, `Bank`, `Utang Usaha`, dan contoh beban) muncul pada `chart_of_accounts`, dan fungsi RPC serta trigger audit berhasil dibuat.
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

Buka alamat yang ditampilkan Vite, biasanya `http://localhost:5173`. Buat akun dengan email/password, konfirmasi jika diwajibkan proyek, lalu masuk. Tautan konfirmasi diarahkan kembali ke alamat aplikasi yang sedang dibuka; pastikan URL lokal maupun URL GitHub Pages terdaftar dalam Auth **Redirect URLs**.

## Aturan bisnis dan kontrol

- Browser menghitung total secara live dalam satuan sen, memvalidasi header/akun/nominal dan aturan akun kas, menampilkan selisih, dan menonaktifkan tombol submit sampai voucher valid serta seimbang.
- Validasi browser bukan kontrol keamanan. RPC `create_cash_voucher` mengulang validasi akun, jumlah baris, debit-kredit seimbang, dan aturan kas keluar di dalam PostgreSQL.
- Hanya akun kas/bank yang dikreditkan untuk voucher kas keluar. Transfer internal sebaiknya memakai jenis voucher terpisah.
- Pembuatan header, baris, checksum, dan perubahan status `DRAFT` → `POSTED` berjalan atomik di database.
- RLS membatasi riwayat ke pemilik jurnal. Klien tidak diberi hak langsung untuk menulis/menghapus tabel jurnal.
- Trigger menolak modifikasi header/baris jurnal yang sudah `POSTED`; koreksi menggunakan RPC `reverse_cash_voucher`.
- `audit_log` merekam operasi pada header/baris dengan aktor dan waktu server; UPDATE/DELETE ditolak oleh trigger append-only. Aplikasi hanya dapat membaca audit voucher miliknya melalui RPC `get_voucher_audit`.
- `hash_checksum` menyimpan SHA-256 atas header dan baris, termasuk tautan reversal; `verify_voucher_checksum` menghitung ulang dan membandingkan hash tersebut.
- Hash dan trigger melindungi alur aplikasi, tetapi bukan jaminan anti-tamper terhadap pemilik database/superuser yang dapat mengubah skema atau menonaktifkan trigger.

## Uji validasi browser

Jalankan dari direktori proyek dengan `npm test`. Pengujian meliputi konversi nominal presisi dua desimal, voucher seimbang, selisih debit/kredit, header wajib, baris debit/kredit yang konflik, aturan akun kas keluar, dan akun yang tidak tersedia. Tes ini tidak membuat atau mengirim transaksi ke Supabase.

## Uji audit trail di Supabase

1. Buat minimal satu akun pada **Authentication → Users**.
2. Jalankan `supabase/tests/audit_trail.sql` dari SQL Editor dengan role administratif.
3. Tes membuat voucher seimbang sementara, memverifikasi actor/timestamp, audit log, dan checksum; memastikan UPDATE/DELETE terhadap jurnal `POSTED` dan audit log ditolak; membuat reversal; serta memeriksa bahwa jurnal tidak seimbang ditolak.
4. Seluruh uji berada di dalam transaksi yang diakhiri `ROLLBACK`, sehingga voucher/jurnal uji tidak tertinggal.

## Menghubungkan ke GitHub dan deploy

Repository menerbitkan aplikasi melalui GitHub Pages dan workflow **Deploy GitHub Pages**. Situs tersedia pada URL proyek GitHub Pages setelah deployment berhasil.

Pastikan **Settings → Pages → Build and deployment → Source** disetel ke **GitHub Actions**. Tambahkan repository variables melalui **Settings → Secrets and variables → Actions → Variables**:

- `VITE_SUPABASE_URL` — URL proyek Supabase.
- `VITE_SUPABASE_ANON_KEY` — anon/publishable key; key ini dipakai di browser dan bukan `service_role`.

Setelah konfigurasi tersedia, push ke `main` akan membangun dan menerbitkan aplikasi. Status dan alasan kegagalan deployment dapat dilihat pada tab **Actions**.

Simpan perubahan ke branch `main`:

```powershell
git status
git add -A
git commit -m "Describe the change"
git push origin main
```

Workflow `.github/workflows/deploy-pages.yml` memeriksa kedua konfigurasi sebelum build. Jika nilai belum diatur, proses berhenti dengan pesan tentang nama variable yang perlu ditambahkan.

## Catatan

Ini purwarupa akademik, bukan sistem produksi. Sebelum pemakaian nyata, tambahkan review hak akses, kebijakan nomor bukti, periode akuntansi, pembatasan besaran input, klasifikasi arus kas, multi-currency, dan kebijakan pengelolaan kas/setara kas sesuai PSAK.
