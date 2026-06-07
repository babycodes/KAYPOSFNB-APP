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

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;
  String _error = '';
  String _serverUrl = '';

  late AnimationController _animCtrl;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _loadServerStatus();

    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  bool _isServerOnline = false;

  Future<void> _loadServerStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('server_url') ?? '';
    if (mounted) {
      setState(() {
        _serverUrl = url;
      });
    }

    if (url.isNotEmpty) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
        if (mounted) {
          setState(() {
            _isServerOnline = true;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isServerOnline = false;
          });
        }
      }
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
                        'device_name': DeviceInfoService.getDefaultDeviceName(),
                        'device_platform': DeviceInfoService.getDevicePlatform(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // Subtle gradient background
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [cs.surface, cs.surfaceContainerLow]
                        : [cs.surface, cs.surfaceContainerLow, const Color(0xFFE0F0E0)],
                    stops: isDark ? [0.0, 1.0] : [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: FadeTransition(
                opacity: _fadeIn,
                child: SlideTransition(
                  position: _slideUp,
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo with glow
                  Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: cs.primary.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8)),
                        BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset('assets/icon-512.png', width: 88, height: 88, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('KAYPOS', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text('Food & Beverage POS', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, letterSpacing: 0.5)),
                  const SizedBox(height: 36),

                  // Login card
                  Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: cs.surfaceBright,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: cs.outlineVariant, width: 0.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06), blurRadius: 20, offset: const Offset(0, 8)),
                      ],
                    ),
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
                            child: Row(children: [
                              Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error, style: TextStyle(color: cs.onErrorContainer, fontSize: 13, fontWeight: FontWeight.w500))),
                            ]),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Username
                        Text('USERNAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _usernameCtrl,
                          autofocus: true,
                          onSubmitted: (_) => _handleLogin(),
                          decoration: _inputDecoration(context, 'Masukkan username'),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 20),

                        // Password
                        Text('PASSWORD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: !_showPassword,
                          onSubmitted: (_) => _handleLogin(),
                          decoration: _inputDecoration(context, 'Masukkan password').copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_showPassword ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: cs.onSurfaceVariant, size: 20),
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                            ),
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 28),

                        // Login Button
                        SizedBox(
                          width: double.infinity, height: 52,
                          child: FilledButton(
                            onPressed: _loading ? null : _handleLogin,
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 2,
                            ),
                            child: _loading
                              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: cs.onPrimary, strokeWidth: 2.5))
                              : const Text('Masuk', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.5)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(child: Text('Hubungi admin jika lupa password', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5)))),
                      ],
                    ),
                  ),
                ],
              ),
                ),
              ),
          ),
        ),
      // Top-left: server status
      Positioned(
        top: 16,
        left: 16,
        child: Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showConnectServerDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceBright.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Icon(
                    Icons.dns_rounded,
                    size: 20,
                    color: _serverUrl.isNotEmpty ? Colors.green : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (_serverUrl.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (_isServerOnline ? Colors.green : Colors.red).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: (_isServerOnline ? Colors.green : Colors.red).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: _isServerOnline ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isServerOnline ? 'Online' : 'Offline',
                      style: TextStyle(fontSize: 11, color: _isServerOnline ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      // Top-right: theme toggle
      Positioned(
            top: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.read<ThemeProvider>().toggle(),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceBright.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ),
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
