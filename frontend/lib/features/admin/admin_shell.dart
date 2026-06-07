// ignore: unused_import
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';
import '../../core/api.dart';
import '../../core/theme.dart';
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
    {'href': '/admin', 'label': 'Dashboard', 'icon': Icons.dashboard_rounded},
    {'href': '/admin/produk', 'label': 'Produk', 'icon': Icons.restaurant_menu_rounded},
    {'href': '/admin/kategori', 'label': 'Kategori Produk', 'icon': Icons.label_rounded},
    {'href': '/admin/bahan-baku', 'label': 'Inventory', 'icon': Icons.inventory_2_rounded},
    {'href': '/admin/kategori-bahan', 'label': 'Kategori Inventory', 'icon': Icons.category_rounded},
    {'href': '/admin/paket', 'label': 'Menu Paket', 'icon': Icons.fastfood_rounded},
    {'href': '/admin/diskon', 'label': 'Diskon', 'icon': Icons.discount_rounded},
    {'href': '/admin/kartu-stok', 'label': 'Stok Opname', 'icon': Icons.fact_check_rounded},
    {'href': '/admin/laporan', 'label': 'Laporan', 'icon': Icons.bar_chart_rounded},
    {'href': '/admin/karyawan', 'label': 'Karyawan', 'icon': Icons.people_rounded},
    {'href': '/admin/settings', 'label': 'Pengaturan', 'icon': Icons.settings_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _loadBahanAlerts();
    // Check for new reports once on launch (non-blocking, granular update via ValueNotifier)
    SyncService.checkNewReports();
    SyncService.getPendingPushCount();
    // Refresh push count immediately when any sync action modifies data
    SyncService.syncNotifier.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    SyncService.getPendingPushCount();
    _loadBahanAlerts();
  }

  @override
  void dispose() {
    SyncService.syncNotifier.removeListener(_onSyncChanged);
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
        if (!isMobile) AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: showLabels ? 240 : 68,
          child: _buildSidebar(cs, auth, currentPath, false, showLabels),
        ),
        Expanded(child: Column(children: [
          // Header bar
          Container(
            padding: EdgeInsets.only(left: 20, right: 20, top: MediaQuery.of(context).padding.top + 14, bottom: 14),
            decoration: BoxDecoration(
              color: cs.surfaceBright,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(children: [
              if (isMobile) IconButton(onPressed: () => _scaffoldKey.currentState?.openDrawer(), icon: Icon(Icons.menu_rounded, color: cs.onSurface)),
              if (!isMobile) IconButton(
                onPressed: () => setState(() => sidebarOpen = !sidebarOpen),
                icon: AnimatedRotation(
                  turns: sidebarOpen ? 0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.menu_open_rounded, color: cs.onSurfaceVariant, size: 22),
                ),
                tooltip: sidebarOpen ? 'Tutup Sidebar' : 'Buka Sidebar',
              ),
              const SizedBox(width: 8),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Dark sidebar in light mode, surface-matched in dark mode
    final sidebarBg = isDark ? cs.surfaceBright : AppTheme.sidebarDark;
    final textColor = isDark ? cs.onSurface : AppTheme.sidebarText;
    final textMuted = isDark ? cs.onSurfaceVariant : AppTheme.sidebarTextMuted;
    final activeColor = isDark ? cs.primaryContainer : AppTheme.sidebarItemActive;
    final activeTextColor = isDark ? cs.onPrimaryContainer : AppTheme.brandAmber;
    final dividerColor = isDark ? cs.outlineVariant : const Color(0xFF3D302A);

    return Container(
      decoration: BoxDecoration(
        color: sidebarBg,
        border: isMobile ? null : Border(right: BorderSide(color: dividerColor, width: 0.5)),
      ),
      child: Column(children: [
        // Logo header
        Container(
          padding: EdgeInsets.only(left: 12, right: 12, top: MediaQuery.of(context).padding.top + 12, bottom: 12),
          decoration: BoxDecoration(
            gradient: isDark ? null : LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppTheme.sidebarDark, AppTheme.sidebarDarkAlt],
            ),
          ),
          child: Row(children: [
            InkWell(
              onTap: isMobile ? null : () => setState(() => sidebarOpen = !sidebarOpen),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset('assets/icon-512.png', width: 42, height: 42, fit: BoxFit.cover),
                ),
              ),
            ),
            if (showLabels) ...[
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('KAYPOS', style: TextStyle(fontWeight: FontWeight.w800, color: textColor, fontSize: 16, letterSpacing: 0.5)),
                Text('Admin Panel', style: TextStyle(fontSize: 10, color: textMuted)),
              ]),
            ],
          ]),
        ),
        Divider(height: 1, color: dividerColor),
        // Nav items
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), children: navItems.map((item) {
          final active = currentPath == item['href'];
          return Tooltip(
            message: showLabels ? '' : item['label'] as String,
            child: Padding(padding: const EdgeInsets.only(bottom: 2), child: Material(
              color: Colors.transparent,
              child: InkWell(
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
                borderRadius: BorderRadius.circular(10),
                hoverColor: isDark ? cs.surfaceContainerHigh : AppTheme.sidebarItemHover,
                splashColor: activeTextColor.withValues(alpha: 0.1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 42, padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: active ? activeColor : null,
                    borderRadius: BorderRadius.circular(10),
                    border: active ? Border.all(color: activeTextColor.withValues(alpha: 0.2), width: 0.5) : null,
                  ),
                  child: Row(children: [
                    Icon(item['icon'] as IconData, size: 20, color: active ? activeTextColor : textMuted),
                    if (showLabels) ...[const SizedBox(width: 12), Expanded(child: Text(item['label'] as String, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? activeTextColor : textColor)))],
                    // Badge for Bahan Baku
                    if (item['href'] == '/admin/bahan-baku' && (_bahanHabisCount > 0 || _bahanRendahCount > 0))
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        constraints: const BoxConstraints(minWidth: 20), height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: _bahanHabisCount > 0 ? Colors.red.shade600 : Colors.amber.shade700,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Center(child: Text(
                          '${_bahanHabisCount + _bahanRendahCount}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                        )),
                      ),
                  ])),
              ),
            )),
          );
        }).toList())),
        Divider(height: 1, color: dividerColor),
        // Bottom actions
        Padding(padding: const EdgeInsets.all(8), child: Column(children: [
          // Pull Reports Button with badge
          ValueListenableBuilder<int>(
            valueListenable: SyncService.newReportNotifier,
            builder: (context, newCount, _) {
              return _sidebarAction(
                icon: Icons.download_rounded,
                label: 'Terima Laporan',
                showLabels: showLabels,
                color: newCount > 0 ? cs.primary : textMuted,
                badge: newCount > 0 ? newCount : null,
                badgeColor: cs.primary,
                isDark: isDark,
                textColor: textColor,
                textMuted: textMuted,
                onTap: () async {
                  final msg = await SyncService.pullReports();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
                  );
                  _loadBahanAlerts();
                },
              );
            },
          ),
          // Push Master Data Button with badge
          ValueListenableBuilder<int>(
            valueListenable: SyncService.pendingPushCountNotifier,
            builder: (context, pushCount, _) {
              return _sidebarAction(
                icon: Icons.cloud_upload_rounded,
                label: 'Kirim Update',
                showLabels: showLabels,
                color: pushCount > 0 ? Colors.green.shade400 : textMuted,
                badge: pushCount > 0 ? pushCount : null,
                badgeColor: Colors.green,
                isDark: isDark,
                textColor: textColor,
                textMuted: textMuted,
                onTap: () async {
                  // First check if server is reachable and has data
                  final serverStatus = await SyncService.checkServerDataStatus();
                  if (!context.mounted) return;
                  
                  if (serverStatus == 'NO_CONNECTION') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Server tidak tersambung. Periksa koneksi.'), behavior: SnackBarBehavior.floating),
                    );
                    return;
                  }
                  
                  if (serverStatus == 'DEVICE_NOT_REGISTERED') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Perangkat belum terdaftar di server. Sambungkan ulang ke server terlebih dahulu.'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 4)),
                    );
                    return;
                  }
                  
                  // If server is empty, auto-suggest force push
                  if (serverStatus == 'SERVER_EMPTY') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        icon: Icon(Icons.cloud_off, color: Colors.orange.shade700, size: 40),
                        title: const Text('Server Data Kosong'),
                        content: const Text('Server tidak memiliki data master. Kirim ulang semua data dari perangkat ini ke server?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kirim Ulang Semua')),
                        ],
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await SyncService.resetPushCursor();
                      final msg = await SyncService.pushMasterData();
                      if (!context.mounted) return;
                      SyncService.getPendingPushCount();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
                      );
                    }
                    return;
                  }
                  
                  // Normal flow: push only changes
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Kirim Update Master?'),
                      content: Text(pushCount > 0
                        ? 'Ada $pushCount perubahan data master yang belum dikirim. Kirim sekarang agar Kasir dapat mengunduhnya?'
                        : 'Kirim perubahan data master (Produk, Kategori, Diskon, dll) terbaru ke server agar Kasir dapat mengunduhnya?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kirim')),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    final msg = await SyncService.pushMasterData();
                    if (!context.mounted) return;
                    SyncService.getPendingPushCount();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
                    );
                  }
                },
              );
            },
          ),
          _sidebarAction(
            icon: Icons.storefront_rounded,
            label: 'Ke Kasir',
            showLabels: showLabels,
            color: AppTheme.brandAmber,
            isDark: isDark,
            textColor: textColor,
            textMuted: textMuted,
            onTap: () {
              Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
              context.go('/kasir');
            },
          ),
          _sidebarAction(
            icon: Icons.logout_rounded,
            label: 'Logout',
            showLabels: showLabels,
            color: Colors.red.shade400,
            isDark: isDark,
            textColor: textColor,
            textMuted: textMuted,
            onTap: () async {
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
            },
          ),
        ])),
      ]),
    );
  }

  Widget _sidebarAction({
    required IconData icon,
    required String label,
    required bool showLabels,
    required Color color,
    required bool isDark,
    required Color textColor,
    required Color textMuted,
    int? badge,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: showLabels ? '' : label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: color.withValues(alpha: 0.08),
          child: Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Stack(children: [
                Icon(icon, size: 20, color: color),
                if (badge != null) Positioned(right: -2, top: -2,
                  child: Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(color: badgeColor ?? color, shape: BoxShape.circle),
                  ),
                ),
              ]),
              if (showLabels) ...[const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: badge != null ? color : textColor))),
                if (badge != null) Container(
                  constraints: const BoxConstraints(minWidth: 20), height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(color: badgeColor ?? color, borderRadius: BorderRadius.circular(9)),
                  child: Center(child: Text('$badge', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white))),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
