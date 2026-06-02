// ignore: unused_import
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';
import '../../core/api.dart';
import '../../services/sync_service.dart';

class AdminShell extends StatefulWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  bool sidebarOpen = true;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _bahanHabisCount = 0;
  int _bahanRendahCount = 0;

  final navItems = [
    {'href': '/admin', 'label': 'Dashboard', 'icon': Icons.dashboard},
    {'href': '/admin/produk', 'label': 'Produk', 'icon': Icons.inventory_2},
    {'href': '/admin/kategori', 'label': 'Kategori Produk', 'icon': Icons.label},
    {'href': '/admin/bahan-baku', 'label': 'Inventory', 'icon': Icons.inventory_2},
    {'href': '/admin/kategori-bahan', 'label': 'Kategori Inventory', 'icon': Icons.category},
    {'href': '/admin/paket', 'label': 'Menu Paket', 'icon': Icons.fastfood},
    {'href': '/admin/diskon', 'label': 'Diskon', 'icon': Icons.discount},
    {'href': '/admin/kartu-stok', 'label': 'Stok Opname', 'icon': Icons.fact_check},
    {'href': '/admin/laporan', 'label': 'Laporan', 'icon': Icons.bar_chart},
    {'href': '/admin/karyawan', 'label': 'Karyawan', 'icon': Icons.people},
    {'href': '/admin/settings', 'label': 'Pengaturan', 'icon': Icons.settings},
  ];

  @override
  void initState() {
    super.initState();
    _loadBahanAlerts();
    // Check for new reports once on launch (non-blocking, granular update via ValueNotifier)
    SyncService.checkNewReports();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadBahanAlerts() async {
    try {
      final alerts = await Api.get('/bahan-baku/alerts') as List;
      if (!mounted) return;
      int habis = 0, rendah = 0;
      for (final b in alerts) {
        final stock = (b['stock'] is num) ? (b['stock'] as num).toDouble() : 0.0;
        if (stock <= 0) { habis++; } else { rendah++; }
      }
      setState(() { _bahanHabisCount = habis; _bahanRendahCount = rendah; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final isCompact = MediaQuery.sizeOf(context).width < 1100;
    final currentPath = GoRouterState.of(context).uri.path;
    // Auto-collapse sidebar on compact screens
    final showLabels = sidebarOpen && !isCompact;

    if (!auth.isLoggedIn || !auth.isAdmin) {
      return Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('404', style: TextStyle(fontSize: 80, fontWeight: FontWeight.w900, color: cs.onSurface.withValues(alpha: 0.05))),
        const SizedBox(height: 16),
        Text('Halaman Tidak Ditemukan', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface)),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => context.go(auth.isLoggedIn ? '/kasir' : '/login'), child: Text(auth.isLoggedIn ? 'Kembali ke Kasir' : 'Login')),
      ])));
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: cs.surface,
      drawer: isMobile ? Drawer(child: _buildSidebar(cs, auth, currentPath, true, true)) : null,
      body: Row(children: [
        if (!isMobile) SizedBox(
          width: showLabels ? 240 : 64,
          child: _buildSidebar(cs, auth, currentPath, false, showLabels),
        ),
        Expanded(child: Column(children: [
          // Header
          Container(
            padding: EdgeInsets.only(left: 16, right: 16, top: MediaQuery.of(context).padding.top + 12, bottom: 12),
            decoration: BoxDecoration(color: cs.surfaceBright, border: Border(bottom: BorderSide(color: cs.outlineVariant))),
            child: Row(children: [
              if (isMobile) IconButton(onPressed: () => _scaffoldKey.currentState?.openDrawer(), icon: const Icon(Icons.menu)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(navItems.firstWhere((n) => n['href'] == currentPath, orElse: () => {'label': 'Admin'})['label'] as String,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
                Text('Halo, ${auth.userName}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ])),
            ]),
          ),
          Expanded(child: Padding(padding: const EdgeInsets.all(16), child: widget.child)),
        ])),
      ]),
    );
  }

  Widget _buildSidebar(ColorScheme cs, AuthProvider auth, String currentPath, bool isMobile, bool showLabels) {
    return Container(
      decoration: BoxDecoration(color: cs.surfaceBright, border: Border(right: BorderSide(color: cs.outlineVariant))),
      child: Column(children: [
        // Logo
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          InkWell(
            onTap: () => setState(() => sidebarOpen = !sidebarOpen),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/icon-512.png', width: 40, height: 40, fit: BoxFit.cover),
            ),
          ),
          if (showLabels) ...[
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('KAYPOS', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
              Text('Admin Panel', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ]),
          ],
        ])),
        const Divider(height: 1),
        // Nav
        Expanded(child: ListView(padding: const EdgeInsets.all(8), children: navItems.map((item) {
          final active = currentPath == item['href'];
          return Tooltip(
            message: showLabels ? '' : item['label'] as String,
            child: Padding(padding: const EdgeInsets.only(bottom: 4), child: InkWell(
              onTap: () {
                // Dismiss any open dialogs/modals/bottom sheets before navigating
                // popUntil with (route) => route.isFirst pops all overlay routes
                // while keeping the base GoRouter shell route intact
                Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
                // Then navigate
                context.go(item['href'] as String);
                if (isMobile && _scaffoldKey.currentState?.isDrawerOpen == true) {
                  _scaffoldKey.currentState?.closeDrawer();
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: active ? cs.primaryContainer : null, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(item['icon'] as IconData, size: 20, color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                  if (showLabels) ...[const SizedBox(width: 12), Expanded(child: Text(item['label'] as String, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant)))],
                  // Badge for Bahan Baku
                  if (item['href'] == '/admin/bahan-baku' && (_bahanHabisCount > 0 || _bahanRendahCount > 0))
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      constraints: const BoxConstraints(minWidth: 20), height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: _bahanHabisCount > 0 ? Colors.red : Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(child: Text(
                        '${_bahanHabisCount + _bahanRendahCount}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                      )),
                    ),
                ])),
            )),
          );
        }).toList())),
        const Divider(height: 1),
        // Bottom actions
        Padding(padding: const EdgeInsets.all(8), child: Column(children: [
          // Pull Reports Button with badge
          ValueListenableBuilder<int>(
            valueListenable: SyncService.newReportNotifier,
            builder: (context, newCount, _) {
              return Tooltip(
                message: showLabels ? '' : 'Terima Laporan',
                child: InkWell(
                  onTap: () async {
                    final msg = await SyncService.pullReports();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
                    );
                    _loadBahanAlerts();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Stack(children: [
                        Icon(Icons.download_rounded, size: 20, color: newCount > 0 ? cs.primary : cs.onSurfaceVariant),
                        if (newCount > 0) Positioned(right: 0, top: 0,
                          child: Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
                          ),
                        ),
                      ]),
                      if (showLabels) ...[const SizedBox(width: 12),
                        Expanded(child: Text('Terima Laporan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: newCount > 0 ? cs.primary : cs.onSurfaceVariant))),
                        if (newCount > 0) Container(
                          constraints: const BoxConstraints(minWidth: 20), height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text('$newCount', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white))),
                        ),
                      ],
                    ]),
                  ),
                ),
              );
            },
          ),
          // Push Master Data Button
          Tooltip(
            message: showLabels ? '' : 'Kirim Update Master',
            child: InkWell(
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Kirim Update Master?'),
                    content: const Text('Kirim perubahan data master (Produk, Kategori, Diskon, dll) terbaru ke server agar Kasir dapat mengunduhnya?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kirim')),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  final msg = await SyncService.pushMasterData();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
                  );
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Icon(Icons.cloud_upload_rounded, size: 20, color: cs.secondary),
                  if (showLabels) ...[const SizedBox(width: 12), Text('Kirim Update', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.secondary))],
                ]),
              ),
            ),
          ),
          Tooltip(
            message: showLabels ? '' : 'Ke Kasir',
            child: InkWell(onTap: () {
              Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
              context.go('/kasir');
            }, borderRadius: BorderRadius.circular(12),
              child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Icon(Icons.shopping_cart, size: 20, color: cs.primary),
                  if (showLabels) ...[const SizedBox(width: 12), Text('Ke Kasir', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.primary))],
                ]))),
          ),
          Tooltip(
            message: showLabels ? '' : 'Logout',
            child: InkWell(onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Konfirmasi'),
                  content: const Text('Apakah Anda yakin ingin keluar?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Keluar')),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
                auth.logout(); 
                context.go('/login'); 
              }
            }, borderRadius: BorderRadius.circular(12),
              child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Icon(Icons.logout, size: 20, color: cs.error),
                  if (showLabels) ...[const SizedBox(width: 12), Text('Logout', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.error))],
                ]))),
          ),
        ])),
      ]),
    );
  }
}
