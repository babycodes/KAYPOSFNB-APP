import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';
import '../../core/local_db.dart';
import '../../services/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import '../../services/device_info_service.dart';
import '../../services/sync_service.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic> settings = {};
  
  PlatformFile? restoreFile;
  bool saving = false;
  String restoreMsg = '';
  bool _isBackingUp = false;
  bool _isRestoring = false;

  String _currentVersion = '';
  final UpdateService _updateService = UpdateService();
  bool _isCheckingUpdate = false;
  String _deviceUuid = '';

  final _storeNameCtrl = TextEditingController();
  final _storeSubNameCtrl = TextEditingController();
  final _storeAddressCtrl = TextEditingController();
  final _storePhoneCtrl = TextEditingController();
  final _storePromoCtrl = TextEditingController();

  // Logo & Print toggles
  String? _logoPath;
  bool _printLogo = true;
  bool _printStoreName = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadVersion();
    _loadDeviceUuid();
  }

  Future<void> _loadDeviceUuid() async {
    final uuid = await DeviceInfoService.getDeviceUuid();
    if (mounted) {
      setState(() => _deviceUuid = uuid);
    }
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
      _currentVersion = packageInfo.version;
    });
    }
  }

  Future<void> _loadSettings() async {
    try {
      final res = await Api.get('/settings');
      if (mounted) {
        setState(() {
        settings = res;
        _storeNameCtrl.text = settings['store_name'] ?? '';
        _storeSubNameCtrl.text = settings['store_sub_name'] ?? '';
        _storeAddressCtrl.text = settings['store_address'] ?? '';
        _storePhoneCtrl.text = settings['store_phone'] ?? '';
        _storePromoCtrl.text = settings['store_promo'] ?? '';
        _printLogo = (settings['print_logo'] ?? '1') == '1';
        _printStoreName = (settings['print_store_name'] ?? '1') == '1';
        final savedLogo = settings['store_logo_path']?.toString() ?? '';
        if (savedLogo.isNotEmpty && File(savedLogo).existsSync()) {
          _logoPath = savedLogo;
        }
      });
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    setState(() => saving = true);
    try {
      await Api.put('/settings', body: {
        'store_name': _storeNameCtrl.text,
        'store_sub_name': _storeSubNameCtrl.text,
        'store_address': _storeAddressCtrl.text,
        'store_phone': _storePhoneCtrl.text,
        'store_promo': _storePromoCtrl.text,
        'store_logo_path': _logoPath ?? '',
        'print_logo': _printLogo ? '1' : '0',
        'print_store_name': _printStoreName ? '1' : '0',
      });
      if (mounted) showToast(context, 'Pengaturan tersimpan');
    } catch (e) {
      if (mounted) showToast(context, 'Gagal menyimpan: $e');
    }
    setState(() => saving = false);
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result != null && result.files.isNotEmpty) {
      final picked = result.files.first;
      if (picked.path == null) return;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final logoDir = Directory(p.join(appDir.path, 'kaypos_assets'));
        if (!logoDir.existsSync()) logoDir.createSync(recursive: true);
        final ext = p.extension(picked.path!);
        final destPath = p.join(logoDir.path, 'store_logo$ext');
        File(picked.path!).copySync(destPath);
        setState(() => _logoPath = destPath);
      } catch (e) {
        if (mounted) showToast(context, 'Gagal menyimpan logo: $e');
      }
    }
  }

  void _removeLogo() {
    if (_logoPath != null) {
      try { File(_logoPath!).deleteSync(); } catch (_) {}
    }
    setState(() => _logoPath = null);
  }

  /// BACKUP: Copy database file to user-selected location
  Future<void> _downloadBackup() async {
    if (kIsWeb) {
      if (mounted) showToast(context, 'Backup tidak tersedia di versi Web.');
      return;
    }
    
    setState(() => _isBackingUp = true);
    try {
      final dbPath = await getDatabasesPath();
      final sourcePath = p.join(dbPath, 'kayposfnb.db');
      final sourceFile = File(sourcePath);
      
      if (!await sourceFile.exists()) {
        if (mounted) showToast(context, 'Database tidak ditemukan.');
        setState(() => _isBackingUp = false);
        return;
      }

      // Let user pick save location
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      String? result;
      try {
        result = await FilePicker.saveFile(
          dialogTitle: 'Simpan Backup Database',
          fileName: 'kaypos_backup_$timestamp.db',
          type: FileType.custom,
          allowedExtensions: ['db'],
        );
      } catch (_) {
        // saveFile not supported on some platforms, use getDirectoryPath
        final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Pilih folder backup');
        if (dir != null) {
          result = p.join(dir, 'kaypos_backup_$timestamp.db');
        }
      }
      
      if (result != null) {
        await sourceFile.copy(result);
        if (mounted) showToast(context, '✅ Backup berhasil disimpan!');
      }
    } catch (e) {
      if (mounted) showToast(context, 'Gagal backup: $e');
    }
    setState(() => _isBackingUp = false);
  }
  
  /// Pick a .db file for restore — reads file immediately to avoid content URI expiry
  Future<void> _pickRestoreFile() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      withData: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final picked = result.files.first;
      if (picked.path == null) {
        if (mounted) showToast(context, 'File path tidak tersedia');
        return;
      }
      
      // Immediately copy to a safe temp location (Android content URIs can expire)
      try {
        final dbDir = LocalDb.cachedDbDir;
        if (dbDir == null) {
          if (mounted) showToast(context, 'Database belum diinisialisasi');
          return;
        }
        final safeCopyPath = '$dbDir/kaypos_restore_staged.db';
        File(picked.path!).copySync(safeCopyPath);
        
        setState(() {
          restoreFile = picked;
          _stagedRestorePath = safeCopyPath;
          restoreMsg = '';
        });
      } catch (e) {
        if (mounted) showToast(context, 'Gagal membaca file: $e');
      }
    }
  }
  
  String? _stagedRestorePath;

  /// RESTORE: Stage backup → swap DB → soft restart app
  Future<void> _restoreDB() async {
    if (_stagedRestorePath == null) return;
    if (kIsWeb) {
      if (mounted) showToast(context, 'Restore tidak tersedia di versi Web.');
      return;
    }

    final dbDir = LocalDb.cachedDbDir;
    if (dbDir == null) {
      showToast(context, 'Database belum diinisialisasi');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        bool isWorking = false;
        String statusText = 'Menyalin database...';
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(isWorking ? '⏳ Memproses...' : '⚠️ Konfirmasi Restore'),
            content: isWorking
              ? Row(children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 20),
                  Expanded(child: Text('$statusText\nAplikasi akan restart otomatis.', style: const TextStyle(fontSize: 14))),
                ])
              : const Text(
                  'PERHATIAN: Semua data saat ini akan DIGANTI dengan data dari file backup.\n\n'
                  'Aplikasi akan RESTART secara otomatis.\n'
                  'Saat dibuka kembali, database sudah terganti.\n\n'
                  'Lanjutkan?'
                ),
            actions: isWorking ? [] : [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  setDialogState(() => isWorking = true);
                  
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    try {
                      // 1. Close current DB connection
                      setDialogState(() => statusText = 'Menutup database...');
                      await LocalDb.closeAndReset();
                      await Future.delayed(const Duration(milliseconds: 300));
                      
                      // 2. Rename staged file to the pending restore name
                      setDialogState(() => statusText = 'Menyiapkan restore...');
                      final pendingPath = '$dbDir/kaypos_restore_pending.db';
                      final stagedFile = File(_stagedRestorePath!);
                      if (await stagedFile.exists()) {
                        stagedFile.copySync(pendingPath);
                        stagedFile.deleteSync();
                      }
                      
                      // 3. Reinitialize DB (triggers _applyPendingRestore)
                      setDialogState(() => statusText = 'Memulai ulang database...');
                      await LocalDb.instance;
                      
                      // 4. Close dialog FIRST, then navigate to splash
                      if (ctx.mounted) {
                        Navigator.of(dialogCtx).pop();
                      }
                      await Future.delayed(const Duration(milliseconds: 100));
                      
                      // 5. Navigate to splash → splash re-checks auth → routes to login
                      if (context.mounted) {
                        showToast(context, '✅ Restore berhasil! Memuat ulang...');
                        context.go('/');
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        Navigator.pop(dialogCtx);
                        showToast(context, '❌ Gagal restore: $e');
                      }
                    }
                  });
                },
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Ya, Restore & Restart App'),
              ),
            ],
          );
        });
      },
    );
  }

  void _checkForUpdates() async {
    setState(() => _isCheckingUpdate = true);
    
    try {
      final updateInfo = await _updateService.checkUpdate();
      if (updateInfo != null) {
        _showUpdateDialog(updateInfo);
      } else {
        if (mounted) showToast(context, 'Aplikasi sudah versi terbaru! ✅');
      }
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  void _showUpdateDialog(UpdateInfo updateInfo) {
    double downloadProgress = 0;
    bool isDownloading = false;
    bool isDone = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Update v${updateInfo.version}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(updateInfo.releaseNotes.isNotEmpty ? updateInfo.releaseNotes : 'Pembaruan tersedia.'),
                const SizedBox(height: 12),
                Text('File: ${updateInfo.fileName}', style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontFamily: 'monospace')),
                const SizedBox(height: 16),
                if (isDownloading && !isDone) ...[
                  LinearProgressIndicator(value: downloadProgress > 0 ? downloadProgress / 100 : null),
                  const SizedBox(height: 8),
                  Text(downloadProgress > 0 ? '${downloadProgress.toStringAsFixed(1)}% diunduh...' : 'Menghubungkan...', style: const TextStyle(fontSize: 12)),
                ] else if (isDone) ...[
                  const Row(children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text('Unduhan selesai! Membuka installer...', style: TextStyle(color: Colors.green, fontSize: 13)),
                  ]),
                ] else ...[
                  const Text('Data toko dan transaksi AMAN dan tidak akan hilang.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
            actions: [
              if (!isDownloading && !isDone)
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Nanti Saja'),
                ),
              if (isDownloading && !isDone)
                TextButton(
                  onPressed: () {
                    _updateService.cancelDownload();
                    Navigator.pop(dialogCtx);
                  },
                  child: const Text('Batalkan'),
                ),
              if (!isDownloading && !isDone)
                FilledButton.icon(
                  onPressed: () async {
                    setDialogState(() { isDownloading = true; downloadProgress = 0; });
                    try {
                      final path = await _updateService.downloadUpdate(
                        downloadUrl: updateInfo.downloadUrl,
                        version: updateInfo.version,
                        fileName: updateInfo.fileName,
                        onProgress: (received, total) {
                          if (total > 0) {
                            setDialogState(() => downloadProgress = (received / total * 100));
                          }
                        },
                      );
                      if (path != null && ctx.mounted) {
                        setDialogState(() => isDone = true);
                        await Future.delayed(const Duration(milliseconds: 500));
                        if (ctx.mounted) Navigator.pop(dialogCtx);
                        await _updateService.installUpdate(path);
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        Navigator.pop(dialogCtx);
                        showToast(context, 'Gagal: ${e.toString().replaceAll("Exception: ", "")}');
                      }
                    }
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Download & Install'),
                ),
              if (isDone)
                FilledButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Tutup'),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Store Info
          _SectionBox(cs, title: 'Info Toko', icon: Icons.storefront, children: [
            _Field('NAMA TOKO (UNTUK STRUK)', _storeNameCtrl),
            const SizedBox(height: 12),
            _Field('SUB NAMA TOKO', _storeSubNameCtrl, hint: 'Contoh: Plastik & Bahan Kue'),
            const SizedBox(height: 12),
            _Field('ALAMAT', _storeAddressCtrl),
            const SizedBox(height: 12),
            _Field('NO. TELP', _storePhoneCtrl),
            const SizedBox(height: 12),
            _FieldArea('PROMO / PESAN DI STRUK', _storePromoCtrl, hint: 'Contoh: Diskon 10% setiap hari Jumat!\nFollow IG @toko_anda'),
          ]),
          const SizedBox(height: 24),

          // Logo & Print Preferences
          _SectionBox(cs, title: 'Logo & Struk', icon: Icons.image, children: [
            Text('LOGO TOKO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Logo preview
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: _logoPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(File(_logoPath!), fit: BoxFit.contain, errorBuilder: (ctx, err, stack) => Icon(Icons.broken_image, size: 32, color: cs.onSurfaceVariant)),
                    )
                  : Icon(Icons.add_photo_alternate_outlined, size: 32, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Logo akan dicetak di bagian atas struk. Gunakan gambar persegi atau horizontal, latar putih.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                Row(children: [
                  FilledButton.tonalIcon(
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Text('Pilih Gambar', style: TextStyle(fontSize: 12)),
                  ),
                  if (_logoPath != null) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _removeLogo,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Hapus Logo',
                      style: IconButton.styleFrom(backgroundColor: cs.errorContainer, foregroundColor: cs.error),
                    ),
                  ],
                ]),
              ])),
            ]),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Cetak Logo di Struk', style: TextStyle(fontSize: 14)),
              subtitle: Text(_logoPath == null ? 'Logo belum dipilih' : 'Logo akan tampil di atas struk', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              value: _printLogo,
              onChanged: (v) => setState(() => _printLogo = v),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Cetak Nama Toko di Struk', style: TextStyle(fontSize: 14)),
              subtitle: Text('Nonaktifkan jika logo sudah mencantumkan nama toko', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              value: _printStoreName,
              onChanged: (v) => setState(() => _printStoreName = v),
              contentPadding: EdgeInsets.zero,
            ),
          ]),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: saving ? null : _saveSettings,
            icon: const Icon(Icons.save),
            label: Text(saving ? 'Menyimpan...' : 'Simpan Pengaturan', style: const TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
          ),
          const SizedBox(height: 24),

          // Backup
          _SectionBox(cs, title: 'Backup & Restore', icon: Icons.backup, children: [
            FilledButton.icon(
              onPressed: _isBackingUp ? null : _downloadBackup,
              icon: _isBackingUp
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
              label: Text(_isBackingUp ? 'Menyalin...' : 'Download Backup ke Perangkat Ini', style: const TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(backgroundColor: cs.secondaryContainer, foregroundColor: cs.onSecondaryContainer, minimumSize: const Size(double.infinity, 48)),
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),
            Text('Upload file .db untuk restore:', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12)), child: Text(restoreFile?.name ?? 'Belum ada file dipilih', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))),
              const SizedBox(width: 8),
              FilledButton(onPressed: _pickRestoreFile, child: const Text('Pilih File')),
            ]),
            if (restoreFile != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isRestoring ? null : _restoreDB,
                icon: _isRestoring 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.warning_amber),
                label: Text(_isRestoring ? 'Restoring...' : 'Restore Database', style: const TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError, minimumSize: const Size(double.infinity, 48)),
              ),
            ],
            if (restoreMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Center(child: Text(restoreMsg, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: restoreMsg.contains('✅') ? Colors.green : cs.error)))),
          ]),
          const SizedBox(height: 24),

          // Update System
          _SectionBox(cs, title: 'Pembaruan Sistem', icon: Icons.system_update, action: _currentVersion.isEmpty ? null : Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)), child: Text('v$_currentVersion', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary))), children: [
            Text('Periksa versi terbaru aplikasi KAYPOS FNB. Data produk, pengaturan, dan riwayat transaksi tidak akan hilang setelah pembaruan.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isCheckingUpdate ? null : _checkForUpdates,
              icon: _isCheckingUpdate 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                : const Icon(Icons.cloud_download),
              label: Text(_isCheckingUpdate ? 'Mengecek...' : 'Cek Pembaruan', style: const TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, minimumSize: const Size(double.infinity, 48)),
            ),
          ]),
          const SizedBox(height: 24),

          // Security / Device Info
          _SectionBox(cs, title: 'Keamanan & Perangkat', icon: Icons.security, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Device UUID', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: Text(_deviceUuid.isEmpty ? 'Memuat...' : _deviceUuid, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () {
                  if (_deviceUuid.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: _deviceUuid));
                    if (mounted) showToast(context, 'UUID disalin ke clipboard');
                  }
                },
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sinkronisasi Data', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: Text('Kirim data transaksi belum tersinkron ke server', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              trailing: FilledButton.tonalIcon(
                onPressed: () async {
                  setState(() => saving = true); // reuse saving state for loading UI
                  final result = await SyncService.pushTransactions();
                  setState(() => saving = false);

                  if (result == 'SYNC_REVOKED') {
                    if (mounted) {
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Koneksi Terputus ⚠️'),
                          content: const Text('Koneksi Server terputus (PIN telah dirubah/dicabut oleh Admin). Silakan ke Halaman Login dan klik logo Jaringan (DNS) untuk memasukkan ulang URL dan PIN baru yang valid.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup'))
                          ],
                        )
                      );
                    }
                  } else {
                    if (mounted) showToast(context, result);
                  }
                },
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Sync Sekarang'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _SectionBox(ColorScheme cs, {required String title, required IconData icon, Widget? action, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          if (action != null) action,
        ]),
        const SizedBox(height: 20),
        ...children,
      ]),
    );
  }

  Widget _Field(String label, TextEditingController ctrl, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
      const SizedBox(height: 6),
      TextField(controller: ctrl, decoration: InputDecoration(hintText: hint)),
    ]);
  }

  Widget _FieldArea(String label, TextEditingController ctrl, {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
      const SizedBox(height: 6),
      TextField(controller: ctrl, maxLines: 4, minLines: 2, decoration: InputDecoration(hintText: hint, alignLabelWithHint: true)),
    ]);
  }
}
