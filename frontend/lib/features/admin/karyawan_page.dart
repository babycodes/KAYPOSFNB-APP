import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';
import 'widgets/kay_confirm_dialog.dart';

class KaryawanPage extends StatefulWidget {
  const KaryawanPage({super.key});
  @override
  State<KaryawanPage> createState() => _KaryawanPageState();
}

class _KaryawanPageState extends State<KaryawanPage> {
  List<dynamic> users = [];
  
  bool showForm = false;
  String formError = '';
  final _usernameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final res = await Api.get('/users');
      if (mounted) setState(() => users = res as List);
    } catch (_) {}
  }

  void _openCreate() {
    setState(() {
      _usernameCtrl.clear();
      _nameCtrl.clear();
      formError = '';
      showForm = true;
    });
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (username.isEmpty || name.isEmpty) {
      setState(() => formError = 'Username dan nama wajib diisi');
      return;
    }
    try {
      await Api.post('/users', body: {'username': username, 'name': name, 'role': 'kasir'});
      setState(() => showForm = false);
      await _loadData();
      if (mounted) showToast(context, 'Karyawan berhasil ditambahkan');
    } catch (e) {
      setState(() => formError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _toggleActive(dynamic u) async {
    try {
      await Api.put('/users/${u['id']}', body: {'is_active': u['is_active'] == 1 ? 0 : 1});
      await _loadData();
    } catch (_) {}
  }

  Future<void> _confirmReset(dynamic u) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => KayConfirmDialog(
      title: 'Reset Password & PIN',
      message: "Yakin ingin mereset password dan PIN untuk '${u['name']}'? Password akan kembali ke 'pwkasir' dan PIN ke '000000'.",
      confirmText: 'Ya, Reset',
    ));
    if (confirm == true) {
      try {
        await Api.post('/users/${u['id']}/reset');
        if (mounted) showToast(context, 'Password dan PIN berhasil direset');
      } catch (e) {
        if (mounted) showToast(context, 'Gagal reset: $e');
      }
    }
  }

  Future<void> _confirmDelete(dynamic u) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => KayConfirmDialog(
      title: 'Hapus Karyawan',
      message: "Karyawan '${u['name']}' akan dihapus permanen. Aksi ini tidak bisa dibatalkan.",
      confirmText: 'Hapus Permanen',
    ));
    if (confirm == true) {
      try {
        await Api.delete('/users/${u['id']}');
        await _loadData();
        if (mounted) showToast(context, 'Karyawan berhasil dihapus');
      } catch (e) {
        if (mounted) showToast(context, 'Gagal menghapus: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${users.length} karyawan', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          FilledButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tambah Karyawan', style: TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
          ),
        ]),
        const SizedBox(height: 16),
        
        Expanded(child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 400, mainAxisExtent: 140,
            crossAxisSpacing: 12, mainAxisSpacing: 12,
          ),
          itemCount: users.length,
          itemBuilder: (context, i) {
            final u = users[i];
            final isAdmin = u['role'] == 'admin';
            final isActive = u['is_active'] == 1;

            return Opacity(opacity: isActive ? 1.0 : 0.4, child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
              child: Column(children: [
                Row(children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(color: isAdmin ? cs.tertiaryContainer : cs.primaryContainer, shape: BoxShape.circle),
                    child: Center(child: Text((u['name'] as String).substring(0, 1).toUpperCase(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isAdmin ? cs.onTertiaryContainer : cs.onPrimaryContainer)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('@${u['username']} · ${(u['role'] as String).toUpperCase()}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: isAdmin ? FontWeight.bold : FontWeight.normal)),
                  ])),
                ]),
                const Spacer(),
                Row(children: [
                  Expanded(child: TextButton.icon(
                    onPressed: () => _confirmReset(u),
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Reset PW & PIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(backgroundColor: cs.surfaceContainer, foregroundColor: cs.onSurface),
                  )),
                  if (!isAdmin) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _toggleActive(u),
                      style: TextButton.styleFrom(backgroundColor: isActive ? cs.errorContainer.withValues(alpha: 0.5) : cs.secondaryContainer.withValues(alpha: 0.5), foregroundColor: isActive ? cs.error : cs.secondary),
                      child: Text(isActive ? 'Nonaktifkan' : 'Aktifkan', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _confirmDelete(u),
                      icon: const Icon(Icons.delete, size: 14),
                      style: IconButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                  ]
                ]),
              ]),
            ));
          },
        )),
      ]),
      
      if (showForm) Positioned.fill(child: GestureDetector(onTap: () => setState(() => showForm = false), child: Container(color: Colors.black54, alignment: Alignment.center,
        child: GestureDetector(onTap: () {}, child: Material(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), elevation: 8, child: Container(width: isMobile ? MediaQuery.sizeOf(context).width - 32 : 400, padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Tambah Karyawan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Password default: pwkasir · PIN: 000000', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
            const SizedBox(height: 16),
            if (formError.isNotEmpty) ...[Container(padding: const EdgeInsets.all(8), width: double.infinity, decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(8)), child: Text(formError, style: TextStyle(color: cs.onErrorContainer, fontSize: 12, fontWeight: FontWeight.bold))), const SizedBox(height: 16)],
            
            Text('USERNAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            TextField(controller: _usernameCtrl, decoration: const InputDecoration(hintText: 'contoh: kasir3')),
            const SizedBox(height: 12),
            
            Text('NAMA LENGKAP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(hintText: 'Nama karyawan')),
            const SizedBox(height: 24),
            
            Row(children: [
              Expanded(child: TextButton(onPressed: () => setState(() => showForm = false), style: TextButton.styleFrom(backgroundColor: cs.surfaceContainer, foregroundColor: cs.onSurface, padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.bold)))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: FilledButton(onPressed: _save, style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)))),
            ])
          ]),
        ))),
      ))),
    ]);
  }
}
