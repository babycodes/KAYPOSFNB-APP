// Login Screen — pixel-perfect match of Svelte login/+page.svelte
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';
import '../../core/theme_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;
  String _error = '';

  Future<void> _handleLogin() async {
    if (_usernameCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Username dan password wajib');
      return;
    }
    setState(() { _error = ''; _loading = true; });
    try {
      final auth = context.read<AuthProvider>();
      await auth.login(_usernameCtrl.text, _passwordCtrl.text);
      if (mounted) context.go('/kasir');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _loading = false);
  }



  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo image
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2)),
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 4)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset('assets/icon-512.png', width: 80, height: 80, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 16),
              Text('KAYPOS', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Text('Sistem Point of Sale', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
              const SizedBox(height: 32),

              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 384),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer, borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_error, style: TextStyle(color: cs.onErrorContainer, fontSize: 14, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Username
                    Text('USERNAME', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 1.0)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _usernameCtrl,
                      autofocus: true,
                      onSubmitted: (_) => _handleLogin(),
                      decoration: _inputDecoration(context, 'Masukkan username'),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 16),

                    // Password
                    Text('PASSWORD', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 1.0)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: !_showPassword,
                      onSubmitted: (_) => _handleLogin(),
                      decoration: _inputDecoration(context, 'Masukkan password').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off, color: cs.onSurfaceVariant),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 24),

                    // Login Button
                    SizedBox(
                      width: double.infinity, height: 56,
                      child: FilledButton(
                        onPressed: _loading ? null : _handleLogin,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 1,
                        ),
                        child: _loading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                          : const Text('Masuk', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(child: Text('Hubungi admin jika lupa password', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.5)))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      Positioned(
            top: 24,
            right: 24,
            child: IconButton(
              onPressed: () {
                context.read<ThemeProvider>().toggle();
              },
              icon: Icon(
                Theme.of(context).brightness == Brightness.light ? Icons.dark_mode : Icons.light_mode,
                color: cs.onSurfaceVariant,
              ),
              tooltip: 'Toggle Theme',
            ),
          ),

        ],
      ),
      ),
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String hint) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: cs.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
