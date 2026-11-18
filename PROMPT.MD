# MASTER PROMPT — FINTRACK PERSONAL FINANCE MANAGER

Bertindaklah sebagai Senior Flutter Developer, Mobile Software Architect, UI/UX Designer, dan Database Engineer.

Saya ingin membangun aplikasi Android bernama **FinTrack – Personal Finance Manager**.

Aplikasi ini merupakan aplikasi pengelolaan keuangan pribadi yang akan digunakan secara rutin dalam jangka panjang. Oleh karena itu, prioritaskan stabilitas, keamanan data, kemudahan penggunaan, performa, dan kemudahan maintenance.

Jangan membuat aplikasi yang hanya berisi tampilan atau CRUD sederhana. Bangun aplikasi yang benar-benar berfungsi dan memiliki alur pengelolaan keuangan yang konsisten.

---

# 1. TUJUAN APLIKASI

FinTrack digunakan untuk membantu saya:

1. Mencatat pemasukan dan pengeluaran.
2. Memantau saldo keuangan.
3. Mengelola kategori transaksi.
4. Membuat anggaran bulanan.
5. Menentukan target tabungan.
6. Memantau kondisi keuangan melalui grafik.
7. Memisahkan keuangan pribadi dan keuangan usaha.
8. Melihat riwayat transaksi.
9. Melakukan backup dan restore data.

Aplikasi hanya digunakan oleh satu pemilik, sehingga tidak memerlukan registrasi, multi-user, atau sistem login berbasis server.

Aplikasi harus dapat digunakan tanpa koneksi internet.

# 2. TEKNOLOGI YANG WAJIB DIGUNAKAN

Gunakan teknologi berikut:

- Flutter sebagai framework utama.
- Dart sebagai bahasa pemrograman.
- SQLite sebagai database lokal.
- Drift sebagai database persistence layer.
- Riverpod sebagai state management.
- go_router untuk navigasi.
- fl_chart untuk grafik keuangan.
- flutter_secure_storage untuk menyimpan data kredensial sensitif.
- local_auth untuk autentikasi biometrik.
- intl untuk format mata uang dan tanggal.
- file_picker untuk pemilihan file backup.
- path_provider untuk pengelolaan lokasi file.

Gunakan versi package yang kompatibel dengan versi Flutter yang terpasang.

Jangan menambahkan dependency yang tidak diperlukan.

# 3. DESAIN UI/UX

Buat desain aplikasi yang modern, elegan, minimalis, dan profesional.

Referensi visual:
- Aplikasi fintech modern.
- Dashboard keuangan premium.
- Tampilan bersih dan tidak terlalu ramai.
- Navigasi sederhana.
- Typography yang mudah dibaca.

Tema warna:

- Primary: Navy gelap (#14213D).
- Secondary: Gold (#D4AF37).
- Background light: (#F7F8FA).
- Background dark: (#101827).
- Income: Hijau.
- Expense: Merah.
- Text: Menggunakan warna dengan kontras yang baik.

Sediakan:
- Light mode.
- Dark mode.
- System theme.
- Responsive layout.
- Empty state.
- Loading state.
- Error state.
- Dialog konfirmasi untuk tindakan penting.

Gunakan Material 3 dan hindari desain yang terlihat seperti template aplikasi generik.

# 4. FITUR UTAMA

## A. Dashboard

Dashboard merupakan halaman utama aplikasi.

Tampilkan:

1. Total saldo.
2. Total pemasukan bulan ini.
3. Total pengeluaran bulan ini.
4. Selisih pemasukan dan pengeluaran.
5. Grafik pemasukan dan pengeluaran.
6. Ringkasan anggaran.
7. Target tabungan.
8. Transaksi terbaru.

Tambahkan filter periode:
- Hari ini.
- Minggu ini.
- Bulan ini.
- Tahun ini.
- Rentang tanggal khusus.

Sediakan tombol untuk menyembunyikan nominal saldo ketika aplikasi sedang dibuka di tempat umum.

## B. Manajemen Transaksi

Buat fitur untuk menambahkan, melihat, mengedit, dan menghapus transaksi.

Jenis transaksi:

- Income.
- Expense.
- Transfer antar akun.

Field transaksi:

- Nominal.
- Jenis transaksi.
- Kategori.
- Akun sumber atau tujuan.
- Tanggal.
- Catatan.
- Lampiran opsional.

Ketentuan:

- Nominal harus lebih dari nol.
- Tanggal transaksi dapat dipilih.
- Kategori harus sesuai jenis transaksi.
- Semua perubahan saldo harus dihitung berdasarkan transaksi.
- Transfer tidak boleh dihitung sebagai pemasukan atau pengeluaran.
- Perubahan dan penghapusan transaksi harus memperbarui saldo secara konsisten.

Sediakan pencarian dan filter transaksi berdasarkan kategori, jenis, akun, dan periode.

## C. Manajemen Akun Keuangan

Buat fitur pengelolaan beberapa akun keuangan.

Contoh:

- Cash.
- Bank BCA.
- Bank BRI.
- E-Wallet.
- Dana tunai usaha.

Setiap akun memiliki:

- Nama akun.
- Jenis akun.
- Saldo awal.
- Saldo saat ini.
- Catatan.

Saldo akun harus dapat dihitung berdasarkan saldo awal dan seluruh transaksi yang terkait.

Jangan menganggap transfer antar akun sebagai pemasukan atau pengeluaran baru.

## D. Kategori Transaksi

Sediakan kategori default.

Kategori pemasukan:
- Gaji.
- Uang saku.
- Bisnis.
- Bonus.
- Investasi.
- Lainnya.

Kategori pengeluaran:
- Makanan.
- Transportasi.
- Pendidikan.
- Belanja.
- Tagihan.
- Hiburan.
- Kesehatan.
- Kebutuhan usaha.
- Lainnya.

Pengguna dapat menambah, mengedit, dan menghapus kategori buatan sendiri.

Kategori yang sudah digunakan dalam transaksi tidak boleh dihapus sembarangan. Sediakan mekanisme pengarsipan atau konfirmasi pemindahan kategori.

## E. Budget Management

Fitur untuk mengatur batas pengeluaran.

Pengguna dapat:
- Membuat anggaran bulanan.
- Menentukan kategori.
- Menentukan batas nominal.
- Melihat jumlah yang telah digunakan.
- Melihat sisa anggaran.
- Mendapatkan peringatan ketika penggunaan anggaran mencapai 80%.
- Mendapatkan peringatan ketika anggaran terlampaui.

Tampilkan progress bar untuk setiap anggaran.

## F. Savings Goals

Fitur untuk membuat target tabungan.

Informasi:
- Nama target.
- Target nominal.
- Jumlah terkumpul.
- Target tanggal.
- Catatan.

Contoh:
- Dana darurat.
- Laptop baru.
- Tabungan pribadi.
- Modal usaha.

Tampilkan progress pencapaian target dalam bentuk persentase dan grafik.

Penyetoran atau penarikan dari target tabungan harus dicatat secara konsisten agar tidak terjadi penghitungan ganda terhadap saldo.

## G. Financial Reports

Buat halaman laporan keuangan dengan grafik yang informatif.

Tampilkan:
- Grafik pemasukan.
- Grafik pengeluaran.
- Perbandingan pemasukan dan pengeluaran.
- Pengeluaran berdasarkan kategori.
- Riwayat keuangan bulanan.
- Ringkasan akun.
- Perbandingan antarperiode.

Sediakan pilihan periode laporan.

Gunakan fl_chart.

## H. Backup and Restore

Fitur ini merupakan salah satu prioritas tertinggi karena data keuangan akan digunakan dalam jangka panjang.

Buat fitur:

1. Backup seluruh data aplikasi ke file.
2. Restore data dari file backup.
3. Ekspor transaksi ke CSV.
4. Impor backup yang valid.
5. Validasi file sebelum restore.
6. Konfirmasi sebelum menimpa data.
7. Informasi tanggal dan versi backup.

Backup harus mencakup seluruh data penting:
- Transaksi.
- Akun.
- Kategori.
- Anggaran.
- Target tabungan.
- Pengaturan aplikasi.

Gunakan format backup JSON dengan struktur yang memiliki versi skema.

Tambahkan opsi enkripsi backup menggunakan AES-256-GCM dengan password backup yang dimasukkan pengguna.

Jangan menyimpan password backup dalam bentuk teks biasa.

Pastikan file backup dapat dipulihkan meskipun aplikasi telah diinstal ulang.

## I. Security and Privacy

Karena aplikasi menyimpan informasi keuangan pribadi, perhatikan keamanan.

Implementasikan:

- PIN aplikasi opsional.
- Biometric authentication opsional.
- Auto-lock ketika aplikasi tidak aktif.
- Penyimpanan kredensial menggunakan secure storage.
- Proteksi data backup.
- Validasi seluruh input.
- Konfirmasi penghapusan data.
- Tidak mengirim data ke server eksternal.
- Tidak menggunakan analytics pihak ketiga.

Jangan mengklaim database SQLite otomatis terenkripsi.

Jika ingin menggunakan enkripsi database, jelaskan pilihan implementasinya dan dependency yang dibutuhkan. Jangan mengorbankan kompatibilitas atau stabilitas database.

# 5. RANCANGAN DATABASE

Gunakan SQLite dengan Drift.

Buat tabel:

1. accounts
2. transactions
3. categories
4. budgets
5. savings_goals
6. savings_contributions
7. app_settings

Gunakan primary key dan foreign key yang tepat.

Gunakan integer untuk menyimpan nominal Rupiah agar tidak terjadi masalah presisi floating point.

Gunakan database versioning dan migration.

Pastikan:
- Relasi antar tabel konsisten.
- Penghapusan data tidak merusak transaksi terkait.
- Operasi transfer menggunakan database transaction.
- Perhitungan saldo konsisten.
- Indeks dibuat untuk kolom yang sering digunakan dalam pencarian.

Sediakan mekanisme kalkulasi saldo yang bisa diverifikasi melalui pengujian.

# 6. ARSITEKTUR APLIKASI

Gunakan pendekatan Clean Architecture atau feature-first architecture yang tetap sederhana dan mudah dipelihara.

Pisahkan:

- Presentation.
- Application / State Management.
- Domain.
- Data.
- Database.

Setiap fitur harus memiliki struktur yang jelas.

Hindari:
- Seluruh kode dimasukkan ke satu file.
- Query database langsung di widget.
- Business logic di dalam UI.
- Duplikasi kode.
- Hardcoded data untuk fitur yang seharusnya dinamis.

Gunakan repository pattern untuk akses data.

# 7. NAVIGASI

Gunakan bottom navigation bar dengan lima menu:

1. Home.
2. Transactions.
3. Budget.
4. Reports.
5. Settings.

Tambahkan tombol yang mudah diakses untuk menambahkan transaksi.

Halaman tambahan:
- Account Management.
- Category Management.
- Savings Goals.
- Transaction Detail.
- Backup and Restore.
- Security Settings.
- App Preferences.

# 8. KUALITAS DAN PENGUJIAN

Buat pengujian untuk:

- Perhitungan saldo.
- Penambahan transaksi.
- Pengeditan transaksi.
- Penghapusan transaksi.
- Transfer antar akun.
- Perhitungan anggaran.
- Perhitungan target tabungan.
- Migrasi database.
- Backup dan restore.
- Validasi nominal.
- Konsistensi data.

Pastikan tidak ada transaksi yang membuat saldo berubah dua kali.

Jangan hanya menguji tampilan. Prioritaskan pengujian business logic dan database.

# 9. STRUKTUR FOLDER

Buat struktur proyek yang modular dan konsisten.

Contoh:

lib/
  core/
    constants/
    theme/
    utils/
    database/
    security/
    widgets/

  features/
    dashboard/
    transactions/
    accounts/
    categories/
    budgets/
    savings/
    reports/
    backup/
    settings/

  shared/
    models/
    providers/
    services/

  app.dart
  main.dart

test/
  core/
  features/

# 10. TAHAPAN PENGEMBANGAN

Jangan langsung membuat seluruh aplikasi dalam satu proses tanpa pemeriksaan.

Kerjakan secara bertahap.

Tahap 1:
- Periksa environment Flutter.
- Buat proyek.
- Pasang dependency.
- Siapkan struktur folder.
- Buat tema dan navigasi.

Tahap 2:
- Implementasikan SQLite dan Drift.
- Buat seluruh tabel.
- Buat migration.
- Uji database.

Tahap 3:
- Implementasikan manajemen akun.
- Implementasikan kategori.
- Implementasikan transaksi.
- Pastikan kalkulasi saldo benar.

Tahap 4:
- Implementasikan dashboard.
- Implementasikan budget.
- Implementasikan savings goals.

Tahap 5:
- Implementasikan laporan dan grafik.

Tahap 6:
- Implementasikan backup dan restore.
- Implementasikan ekspor CSV.
- Implementasikan keamanan aplikasi.

Tahap 7:
- Lakukan pengujian menyeluruh.
- Perbaiki bug.
- Optimalkan UI.
- Build APK release.

Setelah setiap tahap selesai:
1. Jalankan flutter analyze.
2. Jalankan flutter test.
3. Perbaiki semua error.
4. Pastikan fitur sebelumnya tidak rusak.
5. Berikan ringkasan file dan fitur yang telah dibuat.

# 11. PANDUAN PENGEMBANGAN

Patuhi aturan berikut:

- Jangan membuat fitur palsu atau tombol yang tidak berfungsi.
- Jangan menggunakan data dummy sebagai pengganti database sebenarnya.
- Jangan menghapus kode yang sudah berfungsi tanpa alasan.
- Jangan melakukan perubahan besar tanpa memeriksa struktur proyek.
- Gunakan komponen UI yang dapat digunakan kembali.
- Pastikan seluruh halaman memiliki navigasi yang berfungsi.
- Perhatikan error handling.
- Pastikan aplikasi tetap berfungsi secara offline.
- Jangan menambahkan fitur cloud pada versi pertama.
- Dokumentasikan konfigurasi dan dependency.

Jika terdapat kebutuhan yang belum jelas, pilih implementasi yang paling sederhana, aman, dan mudah dirawat.

# 12. HASIL AKHIR

Saya menginginkan aplikasi FinTrack yang:

1. Berfungsi sepenuhnya di Android.
2. Dapat digunakan tanpa internet.
3. Menyimpan data secara permanen menggunakan SQLite.
4. Memiliki antarmuka modern dan profesional.
5. Memiliki pengelolaan transaksi yang akurat.
6. Memiliki fitur anggaran dan tabungan.
7. Memiliki laporan keuangan.
8. Memiliki backup dan restore.
9. Memiliki sistem keamanan lokal.
10. Dapat di-maintenance dan dikembangkan dalam jangka panjang.

Buat dokumentasi README.md yang berisi:
- Deskripsi aplikasi.
- Teknologi.
- Cara instalasi.
- Cara menjalankan.
- Struktur folder.
- Struktur database.
- Cara backup dan restore.
- Cara build APK.

**Prioritas utama: akurasi perhitungan keuangan, keamanan data, konsistensi database, dan kemudahan penggunaan.**

Mulai dengan memeriksa environment dan struktur proyek yang tersedia. Setelah itu, kerjakan Tahap 1 terlebih dahulu. Jangan langsung melompat ke seluruh tahap tanpa memastikan setiap bagian berjalan dengan baik.