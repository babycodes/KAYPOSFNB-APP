import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:bot_toast/bot_toast.dart';
import '../features/splash/splash_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/kasir/kasir_screen.dart';
import '../features/admin/admin_shell.dart';
import '../features/admin/admin_dashboard.dart';
import '../features/admin/kategori_page.dart';
import '../features/admin/kategori_bahan_page.dart';
import '../features/admin/produk_page.dart';
import '../features/admin/bahan_baku_page.dart';
import '../features/admin/laporan_page.dart';
import '../features/admin/karyawan_page.dart';
import '../features/admin/diskon_page.dart';
import '../features/admin/settings_page.dart';
import '../features/admin/paket_page.dart';

CustomTransitionPage _fadeTransition(Widget child) {
  return CustomTransitionPage(
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 200),
  );
}

final appRouter = GoRouter(
  initialLocation: '/',
  observers: [BotToastNavigatorObserver()],
  routes: [
    GoRoute(path: '/', pageBuilder: (context, state) => _fadeTransition(const SplashScreen())),
    GoRoute(path: '/login', pageBuilder: (context, state) => _fadeTransition(const LoginScreen())),
    GoRoute(path: '/kasir', pageBuilder: (context, state) => _fadeTransition(const KasirScreen())),
    ShellRoute(
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        GoRoute(path: '/admin', pageBuilder: (context, state) => _fadeTransition(const AdminDashboard())),
        GoRoute(path: '/admin/produk', pageBuilder: (context, state) => _fadeTransition(const ProdukPage())),
        GoRoute(path: '/admin/paket', pageBuilder: (context, state) => _fadeTransition(const PaketPage())),
        GoRoute(path: '/admin/kategori', pageBuilder: (context, state) => _fadeTransition(const KategoriPage())),
        GoRoute(path: '/admin/kategori-bahan', pageBuilder: (context, state) => _fadeTransition(const KategoriBahanPage())),
        GoRoute(path: '/admin/bahan-baku', pageBuilder: (context, state) => _fadeTransition(const BahanBakuPage())),
        GoRoute(path: '/admin/laporan', pageBuilder: (context, state) => _fadeTransition(const LaporanPage())),
        GoRoute(path: '/admin/karyawan', pageBuilder: (context, state) => _fadeTransition(const KaryawanPage())),
        GoRoute(path: '/admin/diskon', pageBuilder: (context, state) => _fadeTransition(const DiskonPage())),
        GoRoute(path: '/admin/settings', pageBuilder: (context, state) => _fadeTransition(const SettingsPage())),
      ],
    ),
  ],
);
