// KAYPOS — Auth Provider (matches Svelte auth.svelte.ts)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

class AuthProvider extends ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _user;
  bool _locked = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token != null && _user != null;
  bool get isAuthenticated => _token != null && _user != null && !_locked;
  bool get isAdmin => _user?['role'] == 'admin';
  bool get isLocked => _locked;
  String get userName => _user?['name'] ?? '';

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await Api.post('/auth/login', body: {
      'username': username.trim().toLowerCase(),
      'password': password,
    });
    _token = res['token'];
    _user = res['user'];
    _locked = false;
    Api.setToken(res['token']);
    await persist();
    notifyListeners();
    return res['user'];
  }

  void lock() {
    _locked = true;
    _persistLock();
    notifyListeners();
  }

  Future<bool> unlock(String pin) async {
    try {
      await Api.post('/auth/verify-pin', body: {'pin': pin});
      _locked = false;
      _persistLock();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void logout() {
    _token = null;
    _user = null;
    _locked = false;
    Api.setToken('');
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('kaypos_auth');
      prefs.remove('kaypos_locked');
    });
    notifyListeners();
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null && _user != null) {
      prefs.setString('kaypos_auth', jsonEncode({'token': _token, 'user': _user}));
      _persistLock();
    }
  }

  Future<bool> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('kaypos_auth');
    if (saved == null) return false;
    try {
      final data = jsonDecode(saved);
      _token = data['token'];
      _user = data['user'];
      Api.setToken(data['token']);
      final wasLocked = prefs.getString('kaypos_locked');
      _locked = wasLocked == '1';
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void updateUserName(String name) {
    if (_user != null) {
      _user!['name'] = name;
      persist();
      notifyListeners();
    }
  }

  Future<void> _persistLock() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('kaypos_locked', _locked ? '1' : '0');
  }
}
