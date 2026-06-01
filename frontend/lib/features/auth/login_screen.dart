// Login Screen — pixel-perfect match of Svelte login/+page.svelte
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/auth_provider.dart';
import '../../core/theme_provider.dart';
import '../../core/helpers.dart';
import '../../services/device_info_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String _serverUrl = '';

  @override
  void initState() {
    super.initState();
    _loadServerStatus();
  }

  Future<void> _loadServerStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _serverUrl = prefs.getString('server_url') ?? '';
      });
    }
  }

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
  Future<void> _showConnectServerDialog() async {
    final urlCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    
    // Auto fill if saved previously
    final prefs = await SharedPreferences.getInstance();
    urlCtrl.text = prefs.getString('server_url') ?? '';

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        bool isConnecting = false;
        String dialogError = '';
        return StatefulBuilder(builder: (stCtx, setStState) {
          return AlertDialog(
            title: const Text('Sambungkan ke Server'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dialogError.isNotEmpty) ...[
                  Text(dialogError, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(labelText: 'URL Server (misal: http://192.168.1.10:8080)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: '6-Digit PIN'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              FilledButton(
                onPressed: isConnecting ? null : () async {
                  if (urlCtrl.text.isEmpty || pinCtrl.text.isEmpty) {
                    setStState(() => dialogError = 'URL dan PIN wajib diisi');
                    return;
                  }
                  
                  setStState(() { isConnecting = true; dialogError = ''; });
                  
                  try {
                    final uuid = await DeviceInfoService.getDeviceUuid();
                    
                    // Cleanup URL trailing slash
                    var baseUrl = urlCtrl.text.trim();
                    if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);
                    if (!baseUrl.startsWith('http')) baseUrl = 'http://$baseUrl';

                    final res = await http.post(
                      Uri.parse('$baseUrl/api/client/pair'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'pin': pinCtrl.text.trim(),
                        'uuid': uuid,
                        'device_name': 'KayPOS Client'
                      }),
                    ).timeout(const Duration(seconds: 10));

                    if (res.statusCode == 200) {
                      await prefs.setString('server_url', baseUrl);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        setState(() => _serverUrl = baseUrl); // Update UI
                        showToast(context, 'Berhasil tersambung ke Server!');
                      }
                    } else {
                      final body = jsonDecode(res.body);
                      setStState(() => dialogError = body['error'] ?? 'Gagal menyambung');
                    }
                  } catch (e) {
                    setStState(() => dialogError = 'Koneksi gagal: Periksa URL dan jaringan');
                  } finally {
                    setStState(() => isConnecting = false);
                  }
                },
                child: isConnecting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sambungkan'),
              )
            ],
          );
        });
      },
    );
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
        left: 24,
        child: Row(
          children: [
            IconButton(
              onPressed: _showConnectServerDialog,
              icon: Icon(
                Icons.dns,
                color: _serverUrl.isNotEmpty ? Colors.green : cs.onSurfaceVariant,
              ),
              tooltip: 'Sambungkan ke Server',
            ),
            if (_serverUrl.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 12, color: Colors.green),
                    const SizedBox(width: 4),
                    Text('Connected', style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
          ],
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
