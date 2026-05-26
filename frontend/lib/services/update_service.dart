import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';

class UpdateInfo {
  final String version;
  final String releaseNotes;
  final String downloadUrl;
  final String fileName;

  UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileName,
  });
}

class UpdateService {
  static const String _repoOwner = 'babycodes';
  static const String _repoName = 'KAYPOSFNB-APP';
  
  http.Client? _httpClient;
  bool _cancelled = false;

  /// Detect the Linux distro family by reading /etc/os-release
  static Future<String> _detectLinuxDistro() async {
    try {
      final file = File('/etc/os-release');
      if (await file.exists()) {
        final content = (await file.readAsString()).toLowerCase();
        // RPM-based distros
        if (content.contains('fedora') ||
            content.contains('rhel') ||
            content.contains('centos') ||
            content.contains('rocky') ||
            content.contains('alma') ||
            content.contains('suse') ||
            content.contains('opensuse')) {
          return 'rpm';
        }
      }
    } catch (_) {}
    return 'deb'; // Default: Debian/Ubuntu family
  }

  /// Determine which file extension to look for in release assets
  static Future<String> _getTargetExtension() async {
    if (kIsWeb) return '';
    if (Platform.isAndroid) return '.apk';
    if (Platform.isWindows) return '.exe';
    if (Platform.isMacOS) return '.dmg';
    if (Platform.isLinux) {
      final distro = await _detectLinuxDistro();
      return distro == 'rpm' ? '.rpm' : '.deb';
    }
    return '';
  }

  /// Check for updates from GitHub Releases
  Future<UpdateInfo?> checkUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Gagal mengecek pembaruan (HTTP ${response.statusCode})');
      }

      final data = jsonDecode(response.body);
      final latestTag = (data['tag_name'] ?? '').toString().replaceFirst('v', '');
      final releaseNotes = (data['body'] ?? '').toString();

      if (latestTag.isEmpty) return null;

      if (_isNewer(latestTag, currentVersion)) {
        final targetExt = await _getTargetExtension();
        final assets = data['assets'] as List? ?? [];
        
        String downloadUrl = data['html_url'] ?? '';
        String fileName = 'kayposfnb_update$targetExt';

        // Find the matching asset for this OS
        for (var asset in assets) {
          final name = (asset['name'] ?? '').toString().toLowerCase();
          if (targetExt.isNotEmpty && name.endsWith(targetExt)) {
            downloadUrl = asset['browser_download_url'] ?? '';
            fileName = asset['name'] ?? fileName;
            break;
          }
        }

        // Fallback: if no matching asset found but release exists, use html_url
        return UpdateInfo(
          version: latestTag,
          releaseNotes: releaseNotes,
          downloadUrl: downloadUrl,
          fileName: fileName,
        );
      }

      return null;
    } catch (e) {
      if (e.toString().contains('Exception:')) rethrow;
      throw Exception('Gagal mengecek pembaruan: $e');
    }
  }

  /// Compare two semantic versions. Returns true if remote > current.
  bool _isNewer(String remote, String current) {
    try {
      final rParts = remote.split('.').map(int.parse).toList();
      final cParts = current.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final r = i < rParts.length ? rParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (r > c) return true;
        if (r < c) return false;
      }
      return false;
    } catch (_) {
      return remote != current;
    }
  }

  /// Download the update binary to a temp directory, reporting progress
  Future<String?> downloadUpdate({
    required String downloadUrl,
    required String version,
    required String fileName,
    required Function(int received, int total) onProgress,
  }) async {
    _cancelled = false;
    _httpClient = http.Client();

    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await _httpClient!.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Download gagal (HTTP ${streamedResponse.statusCode})');
      }

      final total = streamedResponse.contentLength ?? -1;
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      // Delete old downloaded file to prevent conflict
      if (await file.exists()) await file.delete();
      final sink = file.openWrite();

      int received = 0;
      await for (var chunk in streamedResponse.stream) {
        if (_cancelled) {
          await sink.close();
          if (await file.exists()) await file.delete();
          return null;
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }

      await sink.close();
      return filePath;
    } catch (e) {
      if (_cancelled) return null;
      rethrow;
    } finally {
      _httpClient?.close();
      _httpClient = null;
    }
  }

  /// Cancel an in-progress download
  void cancelDownload() {
    _cancelled = true;
    _httpClient?.close();
    _httpClient = null;
  }

  /// Install the downloaded update file
  Future<void> installUpdate(String filePath) async {
    if (kIsWeb) return;

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File installer tidak ditemukan: $filePath');
    }

    if (Platform.isLinux) {
      // Try xdg-open first (works for most desktop environments)
      try {
        await Process.run('xdg-open', [filePath]);
        return;
      } catch (_) {}

      // Fallback: try direct package manager
      final ext = filePath.toLowerCase();
      if (ext.endsWith('.deb')) {
        // Try graphical installer first, then terminal
        try {
          await Process.run('pkexec', ['dpkg', '-i', filePath]);
          return;
        } catch (_) {}
      } else if (ext.endsWith('.rpm')) {
        try {
          await Process.run('pkexec', ['rpm', '-Uvh', filePath]);
          return;
        } catch (_) {}
      }
    }

    // Android — use open_filex with explicit MIME type for APK
    if (Platform.isAndroid) {
      final result = await OpenFilex.open(filePath, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        throw Exception('Gagal membuka installer APK. Silakan install manual: $filePath');
      }
      return;
    }

    // Windows, macOS — use open_filex
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      final uri = Uri.file(filePath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Gagal membuka file installer. Silakan buka manual: $filePath');
      }
    }
  }

  /// Convenience: open the release page in browser
  Future<void> openDownloadPage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
