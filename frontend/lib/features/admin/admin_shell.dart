import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';

class AdminShell extends StatefulWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  bool sidebarOpen = true;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final navItems = [
    {'href': '/admin', 'label': 'Dashboard', 'icon': Icons.dashboard},
    {'href': '/admin/produk', 'label': 'Produk', 'icon': Icons.inventory_2},
    {'href': '/admin/kategori', 'label': 'Kategori Produk', 'icon': Icons.label},
    {'href': '/admin/kategori-bahan', 'label': 'Kategori Bahan', 'icon': Icons.category},
    {'href': '/admin/bahan-baku', 'label': 'Bahan Baku', 'icon': Icons.inventory_2},
    {'href': '/admin/laporan', 'label': 'Laporan', 'icon': Icons.bar_chart},
    {'href': '/admin/karyawan', 'label': 'Karyawan', 'icon': Icons.people},
    {'href': '/admin/diskon', 'label': 'Diskon', 'icon': Icons.discount},
    {'href': '/admin/settings', 'label': 'Pengaturan', 'icon': Icons.settings},
  ];

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
              onTap: () { context.go(item['href'] as String); if (isMobile) Navigator.pop(context); },
              borderRadius: BorderRadius.circular(12),
              child: Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: active ? cs.primaryContainer : null, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(item['icon'] as IconData, size: 20, color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                  if (showLabels) ...[const SizedBox(width: 12), Text(item['label'] as String, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant))],
                ])),
            )),
          );
        }).toList())),
        const Divider(height: 1),
        // Bottom actions
        Padding(padding: const EdgeInsets.all(8), child: Column(children: [
          Tooltip(
            message: showLabels ? '' : 'Ke Kasir',
            child: InkWell(onTap: () => context.go('/kasir'), borderRadius: BorderRadius.circular(12),
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
