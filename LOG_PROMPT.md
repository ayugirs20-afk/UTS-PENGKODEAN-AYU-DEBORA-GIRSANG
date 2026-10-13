# Log Prompt — UTS Pengkodean Akuntansi

Dokumen ini merangkum permintaan dan proses penggunaan AI untuk membantu penyusunan jawaban UTS dan pengembangan purwarupa voucher kas keluar. Ringkasan ini bukan transkrip verbatim seluruh percakapan.

## Ringkasan prompt dan pekerjaan

1. Menjawab soal pada naskah UTS dalam dokumen Word baru dengan mengikuti contoh jawaban yang diberikan.
2. Memperbaiki dan melengkapi jawaban Word untuk bagian-bagian soal, termasuk bagian 3.1 dan 3.2, tanpa mengubah identitas mahasiswa.
3. Menyusun prompt untuk pembuatan purwarupa, lalu memasukkannya ke jawaban bagian 3.1.
4. Menambahkan gambar dan tabel pendukung ke dokumen Word dengan tata letak yang rapi dan tidak bertumpang tindih.
5. Membangun sistem voucher kas keluar yang terhubung dengan Supabase dan GitHub Pages serta mengikuti kebutuhan soal.
6. Memperbaiki validasi voucher, autentikasi, pencatatan audit, checksum, immutability jurnal yang sudah diposting, dan reversal.
7. Menjalankan pengujian aplikasi dan basis data dengan menghindari pembuatan transaksi bisnis nyata.
8. Menerbitkan sistem melalui GitHub Pages dan memeriksa hasil deployment.

## Hasil pengerjaan

- Jawaban UTS disusun dalam dokumen Word terpisah.
- Aplikasi voucher kas keluar menggunakan Supabase Auth dan PostgreSQL.
- Voucher divalidasi sebagai jurnal berpasangan sebelum diposting.
- Pengujian audit basis data menggunakan transaksi yang diakhiri `ROLLBACK`.
- Aplikasi diterbitkan melalui GitHub Pages.

## Tautan proyek

- Repository: https://github.com/ayugirs20-afk/UTS-PENGKODEAN-AYU-DEBORA-GIRSANG
- Aplikasi: https://ayugirs20-afk.github.io/UTS-PENGKODEAN-AYU-DEBORA-GIRSANG/

## Catatan

Jangan menyimpan kata sandi, token, kunci `service_role`, kode verifikasi, atau data pribadi sensitif pada dokumen ini maupun repository. Identitas mahasiswa pada dokumen jawaban dibiarkan kosong sesuai permintaan.
