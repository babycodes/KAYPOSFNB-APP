import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:provider/provider.dart';
import 'package:flutter_phoenix/flutter_phoenix.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/auth_provider.dart';
import 'core/theme_provider.dart';
import 'core/local_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeProvider = ThemeProvider();
  await themeProvider.init();
  // Inisialisasi Database Lokal Offline
  await LocalDb.instance;

  runApp(
    Phoenix(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider.value(value: themeProvider),
        ],
        child: const KayPosApp(),
      ),
    ),
  );
}

class KayPosApp extends StatelessWidget {
  const KayPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp.router(
      title: 'KAYPOSFNB',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      builder: BotToastInit(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
