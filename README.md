# FinTrack — Personal Finance Manager

Aplikasi Android pengelolaan keuangan pribadi yang berjalan **sepenuhnya offline**.
Dibangun bertahap mengikuti spesifikasi pada `PROMPT.MD`.

## Status pengembangan

| Tahap | Cakupan | Status |
| --- | --- | --- |
| 1 | Environment, dependency, struktur folder, tema, navigasi | Selesai |
| 2 | SQLite + Drift, seluruh tabel, migration, uji database | Selesai |
| 3 | Akun, kategori, transaksi, kalkulasi saldo | Selesai |
| 4 | Dashboard, anggaran, target tabungan | Selesai |
| 5 | Laporan dan grafik | Selesai |
| 6 | Backup/restore, ekspor CSV, keamanan aplikasi | Selesai |
| 7 | Pengujian menyeluruh, build APK release | Selesai dengan batasan terdokumentasi |

## Teknologi dan dependensi

- Flutter 3.47.5 / Dart 3.13.4
- SQLite melalui [Drift](https://drift.simonbinder.eu/) dan `sqlite3`; database lokal tidak dienkripsi
- Riverpod — state management
- go_router — navigasi (StatefulShellRoute, 5 tab)
- fl_chart — grafik dashboard/laporan
- intl — format Rupiah dan tanggal Indonesia
- flutter_secure_storage, local_auth — penyimpanan hash PIN dan autentikasi biometrik lokal
- file_picker — pemilihan file restore dan dialog simpan backup/CSV
- cryptography — AES-256-GCM dan PBKDF2-HMAC-SHA256 untuk backup berpassword
- path_provider — lokasi database privat aplikasi
- Dependensi dan versi terpilih tercatat di `pubspec.yaml` dan `pubspec.lock`

## Instalasi dan konfigurasi

1. Pasang Flutter stable sesuai versi di atas dan siapkan Android SDK/emulator atau perangkat Android.
2. Ambil dependensi: `flutter pub get`.
3. Jalankan aplikasi: `flutter run`.
4. Database SQLite dibuat di direktori aplikasi menggunakan `path_provider`; v1 tidak butuh akun, server, internet, atau konfigurasi environment.
5. Untuk detail konfigurasi Android/toolchain, lihat `android/` dan `pubspec.yaml`.

## Menjalankan dan memverifikasi

```bash
flutter run
flutter analyze
flutter test
```

## Implementasi Stage 4

- Dashboard menghitung saldo kumulatif dari ledger; filter periode hanya memengaruhi pemasukan, pengeluaran, selisih, dan rincian kategori.
- Anggaran menghitung pengeluaran per kategori dan bulan. Progress dibatasi 0–100% secara visual; status peringatan aktif mulai 80% dan saat batas terlampaui.
- Target tabungan mendukung buat, ubah, arsip/pulihkan, hapus target tanpa riwayat, setoran, dan penarikan. Setoran/penarikan dicatat sebagai kontribusi berpasangan dengan akun agar saldo tidak dihitung ganda; penarikan melampaui saldo target ditolak dalam transaksi DB.
- Tombol sembunyikan saldo menyimpan preferensi lokal dan hanya memasker nominal pada dashboard.
- Tidak ada cloud atau data contoh yang dipakai sebagai pengganti database. Kategori awal disediakan melalui seeding lokal.

## Implementasi Stage 5

- Laporan menyediakan filter hari, minggu, bulan, tahun, dan rentang khusus.
- Grafik tren pemasukan/pengeluaran memakai bucket harian untuk rentang sampai 62 hari dan bulanan untuk rentang lebih panjang; bucket kosong diisi nol.
- Perbandingan menunjukkan perubahan nominal/persentase terhadap periode sebelumnya; periode sebelumnya nol ditampilkan tanpa persentase.
- Rincian pengeluaran per kategori, riwayat bulanan, dan saldo semua akun (termasuk akun arsip) dihitung dari ledger lokal.
- Transfer tidak masuk hitungan pemasukan/pengeluaran. Saldo akun memasukkan transaksi, transfer, dan kontribusi tabungan tepat satu kali.

## Struktur folder

```
lib/
  core/       # database, router, tema, utils, widgets
  features/   # dashboard, transaksi, akun, kategori, anggaran, tabungan, laporan, backup, settings
  shared/     # Riverpod providers
  app.dart    # MaterialApp.router
  main.dart   # ProviderScope entry point
test/         # unit, repository, widget tests
```

## Implementasi Stage 6

- Backup JSON memiliki `schemaVersion`, waktu pembuatan UTC, dan tujuh tabel data aplikasi. Preferensi PIN, biometrik, dan auto-lock sengaja tidak diekspor; restore mempertahankan nilai lokal perangkat.
- Restore memvalidasi format, versi, ukuran, dan kolom sebelum dialog konfirmasi. Penggantian tabel berlangsung dalam satu transaksi Drift; kegagalan constraint me-rollback seluruh restore.
- Backup dapat dienkripsi dengan AES-256-GCM; kunci diturunkan melalui PBKDF2-HMAC-SHA256. Password tidak disimpan. Simpan password secara terpisah: kehilangan password membuat backup terenkripsi tidak dapat dipulihkan.
- CSV transaksi memakai UTF-8 BOM, CRLF, semua field di-quote, dan prefiks aman terhadap spreadsheet formula injection.
- PIN opsional 4–8 digit disimpan sebagai salted PBKDF2 hash di `flutter_secure_storage`. Biometrik opsional memakai `local_auth`; auto-lock tersedia saat kembali dari latar belakang. Jika status keamanan lokal gagal dibaca, aplikasi tetap terkunci dan menyediakan retry.
- Verifikasi: `flutter test --reporter expanded` lulus (171 tes); `flutter analyze --no-pub` tanpa warning/error (4 info lint `prefer_initializing_formals`); `flutter build apk --release` berhasil menghasilkan APK 62.3 MB. Android memakai `FLAG_SECURE` untuk mencegah screenshot dan pratinjau task switcher.
- Pembatasan percobaan PIN belum diterapkan; PIN minimum 4 digit, jadi jangan anggap app lock sebagai perlindungan terhadap penyerang dengan akses perangkat fisik.
- Attachment transaksi menyimpan path lokal, bukan isi file. File attachment tidak termasuk backup dan dapat hilang saat pindah perangkat atau instal ulang.

## Keamanan dan privasi

Database SQLite lokal **tidak dienkripsi** (SQLCipher belum diaktifkan). Data keuangan berada di penyimpanan privat aplikasi; uninstall dapat menghapus data lokal. Backup tanpa password adalah JSON plaintext. Gunakan password backup kuat bila file disimpan di lokasi bersama. Tidak ada data dikirim ke server eksternal atau analytics pihak ketiga.
