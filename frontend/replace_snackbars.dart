import 'dart:io';

void main() {
  final files = [
    'lib/features/admin/kategori_page.dart',
    'lib/features/admin/produk_page.dart',
    'lib/features/admin/diskon_page.dart'
  ];

  final snackbarRegex = RegExp(r"ScaffoldMessenger\.of\([^)]*\)\.showSnackBar\(\s*const\s*SnackBar\(\s*content:\s*Text\(([^)]+)\)\s*\)\s*\);?", multiLine: true);
  final snackbarRegex2 = RegExp(r"ScaffoldMessenger\.of\([^)]*\)\.showSnackBar\(\s*SnackBar\(\s*content:\s*Text\(([^)]+)\)\s*\)\s*\);?", multiLine: true);
  
  for (var file in files) {
    var f = File(file);
    if (!f.existsSync()) continue;
    var content = f.readAsStringSync();
    
    content = content.replaceAllMapped(snackbarRegex, (match) => 'showAdminToast(context, ${match.group(1)});');
    content = content.replaceAllMapped(snackbarRegex2, (match) => 'showAdminToast(context, ${match.group(1)});');
      
    f.writeAsStringSync(content);
  }
}
