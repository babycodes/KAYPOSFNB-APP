// KAYPOS OFFLINE — Embedded Local Router
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_db.dart';

class Api {
  static String _authToken = '';

  // UI Compatibility variables (Ignored in offline mode)
  static void setServerUrl(String url) {}
  static String? getServerUrl() => null;
  static String getApiBase() => 'offline://localhost';
  static void setToken(String token) { _authToken = token; }
  static String getToken() => _authToken;

  static Future<dynamic> get(String path) async {
    try {
      final db = await LocalDb.instance;
      
      // --- SETTINGS ---
      if (path == '/settings') {
        final rows = await db.query('settings');
        return { for (var e in rows) e['key'] as String: e['value'] };
      }

      // --- USERS ---
      if (path == '/users') {
        final rows = await db.query('users');
        return rows.map((u) {
          final map = Map<String, dynamic>.from(u);
          map.remove('password'); // Hide password
          return map;
        }).toList();
      }

      // --- CATEGORIES ---
      if (path == '/categories') {
        final rows = await db.rawQuery('''
          SELECT c.*, COUNT(p.id) as total_products
          FROM categories c
          LEFT JOIN products p ON c.id = p.category_id
          GROUP BY c.id
          ORDER BY c.name ASC
        ''');
        List<Map<String, dynamic>> allUnits = [];
        try { allUnits = await db.query('category_units'); } catch (_) {}
        
        final List<Map<String, dynamic>> result = [];
        for (final c in rows) {
          try {
            result.add({
              'id': (c['id'] as num).toInt(),
              'name': (c['name'] ?? 'Kategori').toString(),
              'icon': (c['icon'] ?? '📦').toString(),
              'sort_order': c['sort_order'] ?? 0,
              'total_products': (c['total_products'] as num?)?.toInt() ?? 0,
              'units': allUnits.where((u) => u['category_id'] == c['id']).map((u) => Map<String, dynamic>.from(u)).toList(),
            });
          } catch (e) {
            debugPrint('CATEGORY MAPPING ERROR: $e');
            result.add(Map<String, dynamic>.from(c));
          }
        }
        return result;
      }
      
      // --- PRODUCTS ---
      if (path == '/products' || path == '/products/all') {
        final activeFilter = path == '/products' ? 'WHERE p.is_active = 1' : '';
        final rows = await db.rawQuery('''
          SELECT p.*, c.name as category_name, c.icon as category_icon,
                 i.stock_quantity, i.min_stock_alert, i.stock_unit,
                 u.price as sell_price, COALESCE(NULLIF(p.base_unit, ''), p.purchase_unit, 'pcs') as base_unit
          FROM products p
          LEFT JOIN categories c ON p.category_id = c.id
          LEFT JOIN inventory i ON p.id = i.product_id
          LEFT JOIN product_units u ON p.id = u.product_id AND u.unit_name = COALESCE(NULLIF(p.base_unit, ''), p.purchase_unit, 'pcs')
          $activeFilter
          ORDER BY p.name ASC
        ''');
        
        // Fetch units for all products
        final allUnits = await db.query('product_units');
        
        return rows.map((r) {
          try {
            final pUnits = allUnits.where((u) => u['product_id'] == r['id']).toList();
            return {
              ...r,
              'category_name': r['category_name'] ?? '-',
              'category_icon': r['category_icon'] ?? '📦',
              'stock_quantity': (r['stock_quantity'] as num?)?.toDouble() ?? 0.0,
              'min_stock_alert': (r['min_stock_alert'] as num?)?.toDouble() ?? 0.0,
              'purchase_price': (r['purchase_price'] as num?)?.toDouble() ?? 0.0,
              'is_active': r['is_active'] ?? 1,
              'units': pUnits.isNotEmpty ? pUnits.map((pu) => {
                ...pu,
                'qty_per_unit': (pu['qty_per_unit'] as num?)?.toDouble() ?? 1.0,
                'price': (pu['price'] as num?)?.toDouble() ?? 0.0,
              }).toList() : [{
                'unit_name': r['base_unit'] ?? 'pcs', 
                'qty_per_unit': 1.0, 
                'price': (r['sell_price'] as num?)?.toDouble() ?? 0.0
              }]
            };
          } catch (err) {
            print('MAPPING ERROR in /products: $err');
            return r; // Fallback
          }
        }).toList();
      }

      // --- SINGLE PRODUCT (for Restock Dialog) ---
      if (RegExp(r'^/products/\d+$').hasMatch(path)) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Produk tidak valid');
        final rows = await db.rawQuery('''
          SELECT p.*, c.name as category_name, c.icon as category_icon,
                 i.stock_quantity, i.min_stock_alert, i.stock_unit
          FROM products p
          LEFT JOIN categories c ON p.category_id = c.id
          LEFT JOIN inventory i ON p.id = i.product_id
          WHERE p.id = ?
        ''', [id]);
        if (rows.isEmpty) throw Exception('Produk tidak ditemukan');
        final r = rows.first;
        final allUnits = await db.query('product_units', where: 'product_id = ?', whereArgs: [id]);
        return {
          ...r,
          'category_name': r['category_name'] ?? '-',
          'category_icon': r['category_icon'] ?? '\u{1F4E6}',
          'stock_quantity': (r['stock_quantity'] as num?)?.toDouble() ?? 0.0,
          'min_stock_alert': (r['min_stock_alert'] as num?)?.toDouble() ?? 0.0,
          'purchase_price': (r['purchase_price'] as num?)?.toDouble() ?? 0.0,
          'base_unit': (r['base_unit']?.toString() ?? '').isNotEmpty ? r['base_unit'].toString() : (r['purchase_unit']?.toString() ?? 'pcs'),
          'units': allUnits.map((u) => {
            ...u,
            'qty_per_unit': (u['qty_per_unit'] as num?)?.toDouble() ?? 1.0,
            'price': (u['price'] as num?)?.toDouble() ?? 0.0,
          }).toList(),
        };
      }

      // --- AUTH ME ---
      if (path == '/auth/me') {
        if (_authToken.isEmpty) throw Exception('Sesi habis, silakan login kembali');
        final userId = _authToken.replaceFirst('offline-token-', '');
        final users = await db.query('users', where: 'id = ?', whereArgs: [userId]);
        if (users.isEmpty) throw Exception('Sesi habis, silakan login kembali');
        final user = Map<String, dynamic>.from(users.first);
        user.remove('password');
        return user;
      }
      
      // --- HELD CARTS (alias: /held-carts OR /transactions/held) ---
      if (path == '/transactions/held' || path == '/held-carts') {
        final rows = await db.query('held_carts', orderBy: 'created_at DESC');
        return rows.map((e) {
          final m = Map<String, dynamic>.from(e);
          try { m['cart_data'] = jsonDecode(e['cart_data'] as String); } catch (_) {}
          return m;
        }).toList();
      }

      // --- TRANSACTIONS: STATS (TODAY) ---
      if (path == '/transactions/today') {
        final todayStart = '${DateTime.now().toIso8601String().substring(0, 10)} 00:00:00';
        final txRows = await db.query('transactions', where: 'created_at >= ?', whereArgs: [todayStart]);
        
        double totalSales = 0;
        double totalProfit = 0;
        
        for (var tx in txRows) {
          totalSales += (tx['total_amount'] as num?)?.toDouble() ?? 0;
          final details = await db.query('transaction_details', where: 'transaction_id = ?', whereArgs: [tx['id']]);
          for (var item in details) {
            final subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0;
            final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
            final hpp = (item['purchase_price'] as num?)?.toDouble() ?? 0;
            // Profit = Revenue - Cost. Revenue = subtotal, Cost = hpp * qty (base units)
            totalProfit += subtotal - (hpp * qty);
          }
        }
        
        return {
          'total_transactions': txRows.length,
          'total_sales': totalSales,
          'total_profit': totalProfit,
          'avg_transaction': txRows.isEmpty ? 0 : totalSales / txRows.length,
        };
      }

      // --- SINGLE TRANSACTION (for receipt) ---
      if (RegExp(r'^/transactions/\d+$').hasMatch(path)) {
        final txId = int.tryParse(path.split('/').last);
        if (txId == null) throw Exception('ID Transaksi tidak valid');
        final txRows = await db.query('transactions', where: 'id = ?', whereArgs: [txId]);
        if (txRows.isEmpty) throw Exception('Transaksi tidak ditemukan');
        final details = await db.query('transaction_details', where: 'transaction_id = ?', whereArgs: [txId]);
        
        List<Map<String, dynamic>> enrichedDetails = [];
        for (var d in details) {
          final m = Map<String, dynamic>.from(d);
          final pId = m['product_id'];
          final pRow = await db.query('products', where: 'id = ?', whereArgs: [pId]);
          final uRows = await db.query('product_units', where: 'product_id = ?', whereArgs: [pId]);
          
          m['base_unit'] = pRow.isNotEmpty && pRow.first['base_unit']?.toString().isNotEmpty == true ? pRow.first['base_unit'].toString() : '';
          m['product_units'] = uRows;
          try {
            m['current_unit_data'] = uRows.firstWhere((u) => u['unit_name'] == m['unit_used']);
            // transaction_details stores quantity as baseQty! To use formatCartItemDisplay, we must provide original qty.
            final currentMultiplier = (m['current_unit_data']['qty_per_unit'] as num?)?.toDouble() ?? 1.0;
            m['original_quantity'] = (m['quantity'] as num).toDouble() / currentMultiplier;
          } catch (_) {
            m['current_unit_data'] = null;
            m['original_quantity'] = (m['quantity'] as num).toDouble();
          }
          enrichedDetails.add(m);
        }
        
        return {
          'transaction': Map<String, dynamic>.from(txRows.first),
          'details': enrichedDetails,
        };
      }

      // --- TRANSACTIONS: LIST (with optional ?date=, ?date_start=, ?date_end=, ?limit= filters) ---
      if (path.startsWith('/transactions')) {
        // Parse query params from path
        String? dateParam;
        String? dateStart;
        String? dateEnd;
        int? limitParam;
        if (path.contains('?')) {
          final query = path.split('?').last;
          for (final part in query.split('&')) {
            final kv = part.split('=');
            if (kv.length == 2) {
              if (kv[0] == 'date') dateParam = kv[1];
              if (kv[0] == 'date_start') dateStart = kv[1];
              if (kv[0] == 'date_end') dateEnd = kv[1];
              if (kv[0] == 'limit') limitParam = int.tryParse(kv[1]);
            }
          }
        }
        
        List<Map<String, dynamic>> rows;
        if (dateStart != null && dateEnd != null) {
          // Date range query
          rows = await db.query('transactions',
            where: 'created_at >= ? AND created_at <= ?',
            whereArgs: ['$dateStart 00:00:00', '$dateEnd 23:59:59'],
            orderBy: 'created_at DESC');
        } else if (dateParam != null) {
          // Single day query
          final dayStart = '$dateParam 00:00:00';
          final dayEnd = '$dateParam 23:59:59';
          rows = await db.query('transactions', where: 'created_at >= ? AND created_at <= ?', whereArgs: [dayStart, dayEnd], orderBy: 'created_at DESC');
        } else {
          rows = await db.query('transactions', orderBy: 'created_at DESC');
        }
        
        List<Map<String, dynamic>> results = [];
        for (var t in rows) {
          final details = await db.query('transaction_details', where: 'transaction_id = ?', whereArgs: [t['id']]);
          List<Map<String, dynamic>> enrichedDetails = [];
          for (var d in details) {
            final dm = Map<String, dynamic>.from(d);
            final pId = dm['product_id'];
            final pRow = await db.query('products', where: 'id = ?', whereArgs: [pId]);
            final uRows = await db.query('product_units', where: 'product_id = ?', whereArgs: [pId]);
            
            dm['base_unit'] = pRow.isNotEmpty ? (pRow.first['purchase_unit']?.toString() ?? 'pcs') : 'pcs';
            dm['product_units'] = uRows;
            try {
              dm['current_unit_data'] = uRows.firstWhere((u) => u['unit_name'] == dm['unit_used']);
              final currentMultiplier = (dm['current_unit_data']['qty_per_unit'] as num?)?.toDouble() ?? 1.0;
              dm['original_quantity'] = (dm['quantity'] as num).toDouble() / currentMultiplier;
            } catch (_) {
              dm['current_unit_data'] = null;
              dm['original_quantity'] = (dm['quantity'] as num).toDouble();
            }
            enrichedDetails.add(dm);
          }
          final m = Map<String, dynamic>.from(t);
          m['items'] = enrichedDetails;
          results.add(m);
        }
        
        final limited = (limitParam != null) ? results.take(limitParam).toList() : results;
        return {'data': limited, 'total': results.length};
      }
      
      // --- INVENTORY: FULL LIST (for Stok/Inventaris page) ---
      if (path == '/inventory') {
        final rows = await db.rawQuery('''
          SELECT p.id as product_id, p.name, p.purchase_price, p.purchase_unit as base_unit,
                 c.name as category_name, c.icon as category_icon,
                 COALESCE(i.stock_quantity, 0) as stock_quantity,
                 COALESCE(i.min_stock_alert, 0) as min_stock_alert
          FROM products p
          LEFT JOIN inventory i ON p.id = i.product_id
          LEFT JOIN categories c ON p.category_id = c.id
          WHERE p.is_active = 1
          ORDER BY p.name ASC
        ''');
        final allUnits = await db.query('product_units');
        return rows.map((r) {
          final pUnits = allUnits.where((u) => u['product_id'] == r['product_id']).toList();
          return {
            ...r,
            'id': r['product_id'],
            'product_id': r['product_id'],
            'name': r['name']?.toString() ?? '',
            'category_name': r['category_name'] ?? '-',
            'category_icon': r['category_icon'] ?? '\u{1F4E6}',
            'stock_quantity': (r['stock_quantity'] as num?)?.toDouble() ?? 0.0,
            'min_stock_alert': (r['min_stock_alert'] as num?)?.toDouble() ?? 0.0,
            'purchase_price': (r['purchase_price'] as num?)?.toDouble() ?? 0.0,
            'base_unit': r['base_unit']?.toString() ?? 'pcs',
            'units': pUnits.map((u) => {
              ...u,
              'qty_per_unit': (u['qty_per_unit'] as num?)?.toDouble() ?? 1.0,
              'price': (u['price'] as num?)?.toDouble() ?? 0.0,
            }).toList(),
          };
        }).toList();
      }

      // --- INVENTORY: LOW STOCK ---
      if (path == '/inventory/low-stock' || path == '/inventory/out-of-stock') {
        final isOut = path == '/inventory/out-of-stock';
        final condition = isOut ? '<= 0' : '> 0 AND i.stock_quantity <= i.min_stock_alert';
        final rows = await db.rawQuery('''
          SELECT p.*, c.name as category_name, c.icon as category_icon, i.stock_quantity, i.min_stock_alert 
          FROM products p 
          LEFT JOIN inventory i ON p.id = i.product_id 
          LEFT JOIN categories c ON p.category_id = c.id 
          WHERE p.is_active = 1 AND i.stock_quantity $condition
          ORDER BY i.stock_quantity ASC
        ''');
        return rows.map((r) {
          try {
            return {
              ...r,
              'category_name': r['category_name'] ?? '-',
              'category_icon': r['category_icon'] ?? '\u{1F4E6}',
              'stock_quantity': (r['stock_quantity'] as num?)?.toDouble() ?? 0.0,
              'min_stock_alert': (r['min_stock_alert'] as num?)?.toDouble() ?? 0.0,
              'purchase_price': (r['purchase_price'] as num?)?.toDouble() ?? 0.0,
            };
          } catch (err) {
            debugPrint('Mapping Error in low-stock: $err');
            return r;
          }
        }).toList();
      }

      // --- REPORTS: CHART 28 DAYS ---
      if (path == '/reports/chart28') {
        final past28 = DateTime.now().subtract(const Duration(days: 28)).toIso8601String().substring(0, 10);
        final rows = await db.rawQuery('''
          SELECT date(t.created_at) as date, 
                 COALESCE(SUM(t.total_amount), 0) as sales,
                 COALESCE(SUM(d.subtotal - (d.purchase_price * d.quantity)), 0) as profit
          FROM transactions t
          LEFT JOIN transaction_details d ON t.id = d.transaction_id
          WHERE date(t.created_at) >= ?
          GROUP BY date(t.created_at)
          ORDER BY date ASC
        ''', [past28]);
        return rows.map((r) {
          return {
            'date': r['date']?.toString() ?? '',
            'sales': (r['sales'] as num?)?.toDouble() ?? 0.0,
            'profit': (r['profit'] as num?)?.toDouble() ?? 0.0,
          };
        }).toList();
      }

      // --- REPORTS: TOP PRODUCTS ---
      if (path.startsWith('/reports/products')) {
        final rows = await db.rawQuery('''
          SELECT d.product_id, d.product_name, COALESCE(SUM(d.quantity),0) as total_qty, COALESCE(SUM(d.subtotal),0) as total_revenue
          FROM transaction_details d
          JOIN transactions t ON t.id = d.transaction_id
          GROUP BY d.product_id, d.product_name
          ORDER BY total_revenue DESC
          LIMIT 10
        ''');
        return rows.map((r) {
          return {
            'product_id': r['product_id'],
            'product_name': r['product_name']?.toString() ?? '',
            'total_qty': (r['total_qty'] as num?)?.toDouble() ?? 0.0,
            'total_revenue': (r['total_revenue'] as num?)?.toDouble() ?? 0.0,
          };
        }).toList();
      }

      // --- REPORTS: MONTHLY SUMMARY ---
      if (path.startsWith('/reports/monthly')) {
        String? monthParam;
        String? yearParam;
        if (path.contains('?')) {
          final query = path.split('?').last;
          for (final part in query.split('&')) {
            final kv = part.split('=');
            if (kv.length == 2) {
              if (kv[0] == 'month') monthParam = kv[1];
              if (kv[0] == 'year') yearParam = kv[1];
            }
          }
        }
        if (monthParam == null || yearParam == null) {
          return {'summary': {'total_transactions': 0, 'total_sales': 0}, 'daily': []};
        }
        
        final prefix = '$yearParam-$monthParam';
        
        // Summary
        final sumRows = await db.rawQuery('''
          SELECT COUNT(*) as cnt, COALESCE(SUM(total_amount), 0) as sales
          FROM transactions WHERE created_at LIKE ?
        ''', ['$prefix%']);
        
        final summary = {
          'total_transactions': (sumRows.first['cnt'] as num?)?.toInt() ?? 0,
          'total_sales': (sumRows.first['sales'] as num?)?.toDouble() ?? 0.0,
        };
        
        // Daily breakdown
        final dailyRows = await db.rawQuery('''
          SELECT date(created_at) as date, COUNT(*) as count, COALESCE(SUM(total_amount), 0) as sales
          FROM transactions WHERE created_at LIKE ?
          GROUP BY date(created_at) ORDER BY date ASC
        ''', ['$prefix%']);
        
        final daily = dailyRows.map((d) => {
          'date': d['date']?.toString() ?? '',
          'count': (d['count'] as num?)?.toInt() ?? 0,
          'sales': (d['sales'] as num?)?.toDouble() ?? 0.0,
        }).toList();
        
        return {'summary': summary, 'daily': daily};
      }
      
      // --- DISCOUNTS ---
      if (path == '/discounts') {
        final rows = await db.query('discounts');
        return rows.map((e) {
          final map = Map<String, dynamic>.from(e);
          try {
            map['target_categories'] = jsonDecode(map['target_categories'] ?? '[]');
            map['target_products'] = jsonDecode(map['target_products'] ?? '[]');
          } catch (_) {
            map['target_categories'] = [];
            map['target_products'] = [];
          }
          return map;
        }).toList();
      }

      throw Exception('Endpoint GET $path belum diimplementasikan di Offline Router');
    } catch (e) {
      if (e.toString().contains('Exception:')) rethrow;
      throw Exception('Gagal membaca data lokal: ${e.toString()}');
    }
  }

  static Future<dynamic> post(String path, {dynamic body}) async {
    try {
      final db = await LocalDb.instance;
      
      // --- AUTH LOGIN ---
      if (path == '/auth/login') {
        final username = body?['username']?.toString().toLowerCase() ?? '';
        final password = body?['password']?.toString() ?? '';
        
        final users = await db.query('users', 
          where: 'username = ? AND is_active = 1', 
          whereArgs: [username],
          limit: 1
        );
        
        if (users.isEmpty || users.first['password'] != password) {
          throw Exception('Username atau password salah');
        }
        
        final user = users.first;
        return {
          'token': 'offline-token-${user['id']}',
          'user': {
            'id': user['id'],
            'username': user['username'],
            'name': user['name'],
            'role': user['role']
          }
        };
      }
      
      // --- AUTH PIN VERIFY ---
      if (path == '/auth/verify-pin') {
        final pin = body?['pin']?.toString() ?? '';
        if (pin.isEmpty) throw Exception('PIN wajib diisi');
        
        if (_authToken.isEmpty) throw Exception('Sesi habis, silakan login kembali');
        final userId = _authToken.replaceFirst('offline-token-', '');
        
        final users = await db.query('users', where: 'id = ?', whereArgs: [userId]);
        
        if (users.isEmpty || users.first['pin'] != pin) {
          throw Exception('PIN salah');
        }
        return {'success': true};
      }

      // --- LOGOUT ---
      if (path == '/auth/logout') {
        _authToken = '';
        return {'success': true};
      }

      // --- USERS: RESET PASSWORD & PIN ---
      if (RegExp(r'^/users/\d+/reset$').hasMatch(path)) {
        final id = int.tryParse(path.split('/')[2]);
        if (id == null) throw Exception('ID User tidak valid');
        await db.update('users', {'password': 'pwkasir', 'pin': '000000'}, where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }

      // --- USERS ---
      if (path == '/users') {
        final username = body?['username']?.toString().trim().toLowerCase() ?? '';
        try {
          await db.insert('users', {
            'username': username,
            'name': body?['name']?.toString().trim() ?? 'Kasir Baru',
            'password': body?['password']?.toString() ?? 'pwkasir',
            'pin': body?['pin']?.toString() ?? '000000',
            'role': body?['role']?.toString().trim() ?? 'kasir',
            'is_active': 1,
          });
          return {'success': true};
        } catch (e) {
          if (e.toString().contains('2067') || e.toString().contains('UNIQUE constraint failed')) {
            throw Exception('Username sudah digunakan, silakan pilih yang lain.');
          }
          rethrow;
        }
      }

      // --- CATEGORIES ---
      if (path == '/categories') {
        final name = body?['name']?.toString().trim() ?? 'Kategori Baru';
        final icon = body?['icon']?.toString() ?? '📦';
        final sortOrder = (body?['sort_order'] as num?)?.toInt() ?? 0;
        final unitsList = body?['units'] as List? ?? [];
        
        try {
          await db.transaction((txn) async {
            final catId = await txn.insert('categories', {
              'name': name,
              'icon': icon,
              'sort_order': sortOrder,
            });
            
            for (int i = 0; i < unitsList.length; i++) {
              await txn.insert('category_units', {
                'category_id': catId,
                'unit_name': unitsList[i].toString().trim().toLowerCase(),
                'sort_order': i,
              });
            }
          });
          return {'success': true};
        } catch (e) {
          if (e.toString().contains('UNIQUE constraint failed')) {
            throw Exception('Nama kategori "$name" sudah ada, silakan gunakan nama lain.');
          }
          rethrow;
        }
      }

      // --- TRANSACTIONS: PARK / HOLD CART (alias: /transactions/held OR /held-carts) ---
      if (path == '/transactions/held' || path == '/held-carts') {
        final label = body?['label']?.toString() ?? 'Draft';
        final cartData = jsonEncode(body?['cart_data'] ?? []);
        final total = (body?['total'] as num?)?.toDouble() ?? 0.0;
        final userId = _authToken.replaceFirst('offline-token-', '');
        
        await db.insert('held_carts', {
          'label': label,
          'cart_data': cartData,
          'total': total,
          'created_by': int.tryParse(userId),
        });
        return {'success': true};
      }

      // --- DISCOUNTS ---
      if (path == '/discounts') {
        await db.insert('discounts', {
          'name': body?['name']?.toString() ?? '',
          'target_categories': jsonEncode(body?['target_categories'] ?? []),
          'target_products': jsonEncode(body?['target_products'] ?? []),
          'discount_percent': (body?['discount_percent'] as num?)?.toInt() ?? 0,
          'schedule_type': body?['schedule_type']?.toString() ?? 'all_day',
          'schedule_value': body?['schedule_value']?.toString() ?? '',
          'is_active': (body?['is_active'] == true || body?['is_active'] == 1) ? 1 : 0,
        });
        return {'success': true};
      }

      // --- TRANSACTIONS: CHECKOUT (ACID Compliance) ---
      if (path == '/transactions') {
        final userId = _authToken.replaceFirst('offline-token-', '');
        final paidAmount = (body?['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final paymentMethod = body?['payment_method']?.toString() ?? 'cash';
        final note = body?['note']?.toString();
        final items = body?['items'] as List<dynamic>? ?? [];
        
        final discountTotal = (body?['discount_total'] as num?)?.toDouble() ?? 0.0;
        final discountType = body?['discount_type']?.toString() ?? 'system';
        final discountBy = body?['discount_by']?.toString() ?? 'system';

        // Resolve cashier name
        String cashierName = 'Kasir Offline';
        try {
          final uRows = await db.query('users', columns: ['name'], where: 'id = ?', whereArgs: [userId]);
          if (uRows.isNotEmpty) cashierName = uRows.first['name']?.toString() ?? 'Kasir Offline';
        } catch (_) {}

        late int transactionId;
        double totalAmount = 0.0;
        List<Map<String, dynamic>> detailRows = [];

        // Strict SQLite Transaction (Rollback on failure)
        await db.transaction((txn) async {
          // Step A: Pre-resolve each item's price and name from DB
          List<Map<String, dynamic>> resolvedItems = [];
          for (var item in items) {
            final productId = item['product_id'];
            final unitName = item['unit_name']?.toString() ?? 'pcs';
            final quantity = (item['quantity'] as num).toDouble();

            // Fetch product info
            final pRow = await txn.query('products', where: 'id = ?', whereArgs: [productId]);
            if (pRow.isEmpty) throw Exception('Produk ID $productId tidak ditemukan');
            final product = pRow.first;
            
            // Fetch unit price
            final uRow = await txn.query('product_units', where: 'product_id = ? AND unit_name = ?', whereArgs: [productId, unitName]);
            final unitQty = uRow.isNotEmpty ? (uRow.first['qty_per_unit'] as num?)?.toDouble() ?? 1.0 : 1.0;
            final soldPrice = uRow.isNotEmpty ? (uRow.first['price'] as num?)?.toDouble() ?? 0.0 : 0.0;
            
            final subtotal = soldPrice * quantity;
            final baseQty = quantity * unitQty; // convert to base unit for stock deduction
            final hpp = (product['purchase_price'] as num?)?.toDouble() ?? 0.0;

            final allUnits = await txn.query('product_units', where: 'product_id = ?', whereArgs: [productId]);
            final discountPercent = (item['discount_percent'] as num?)?.toDouble() ?? 0.0;
            final discountAmount = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
            
            resolvedItems.add({
              'product_id': productId,
              'product_name': product['name']?.toString() ?? 'Item',
              'sold_price': soldPrice,
              'purchase_price': hpp,
              'quantity': baseQty,
              'original_quantity': quantity,
              'unit_used': unitName,
              'subtotal': subtotal,
              'discount_percent': discountPercent,
              'discount_amount': discountAmount,
              'current_unit_data': uRow.isNotEmpty ? uRow.first : null,
              'product_units': allUnits,
              'base_unit': product['base_unit']?.toString().isNotEmpty == true ? product['base_unit'].toString() : '',
            });
            totalAmount += subtotal;
          }

          final finalTotal = totalAmount - discountTotal;
          final finalChange = paidAmount - finalTotal;

          // Step B: Insert Main Invoice
          transactionId = await txn.insert('transactions', {
            'cashier_id': int.tryParse(userId),
            'cashier_name': cashierName,
            'total_amount': totalAmount,
            'discount_total': discountTotal,
            'discount_type': discountType,
            'discount_by': discountBy,
            'paid_amount': paidAmount,
            'change_amount': finalChange > 0 ? finalChange : 0,
            'payment_method': paymentMethod,
            'note': note,
          });

          // Step C: Insert items and deduct stock
          for (var ri in resolvedItems) {
            await txn.insert('transaction_details', {
              'transaction_id': transactionId,
              'product_id': ri['product_id'],
              'product_name': ri['product_name'],
              'sold_price': ri['sold_price'],
              'purchase_price': ri['purchase_price'],
              'quantity': ri['quantity'],
              'unit_used': ri['unit_used'],
              'subtotal': ri['subtotal'],
              'discount_percent': ri['discount_percent'],
              'discount_amount': ri['discount_amount'],
            });
            detailRows.add(ri);

            // Deduct from inventory safely
            await txn.rawUpdate(
              'UPDATE inventory SET stock_quantity = stock_quantity - ? WHERE product_id = ?',
              [ri['quantity'], ri['product_id']]
            );
          }
        });

        // Return receipt data for the UI
        final txRow = await db.query('transactions', where: 'id = ?', whereArgs: [transactionId]);
        return {
          'success': true,
          'transaction': txRow.isNotEmpty ? Map<String, dynamic>.from(txRow.first) : {'id': transactionId, 'total_amount': totalAmount},
          'details': detailRows,
        };
      }

      // --- INVENTORY: RESTOCK (ACID Compliance) ---
      if (path == '/inventory/restock') {
        final productId = body?['product_id'];
        final addedStock = (body?['added_stock'] as num?)?.toDouble() ?? 0.0;
        final totalCost = (body?['total_cost'] as num?)?.toDouble() ?? 0.0;
        final newPurchasePrice = (body?['new_purchase_price'] as num?)?.toDouble() ?? 0.0;
        
        await db.transaction((txn) async {
          final pRow = await txn.query('products', columns: ['purchase_price'], where: 'id = ?', whereArgs: [productId]);
          final oldPurchasePrice = pRow.isNotEmpty ? (pRow.first['purchase_price'] as num).toDouble() : 0.0;

          await txn.insert('restock_history', {
            'product_id': productId,
            'added_base_stock': addedStock,
            'total_cost': totalCost,
            'old_purchase_price': oldPurchasePrice,
            'new_purchase_price': newPurchasePrice,
          });

          await txn.update('products', {'purchase_price': newPurchasePrice}, where: 'id = ?', whereArgs: [productId]);
          
          final count = await txn.rawUpdate('UPDATE inventory SET stock_quantity = stock_quantity + ? WHERE product_id = ?', [addedStock, productId]);
          if (count == 0) {
            await txn.insert('inventory', {
              'product_id': productId,
              'stock_quantity': addedStock,
              'min_stock_alert': 0,
            });
          }
        });
        return {'success': true};
      }

      // --- PRODUCTS/:ID/RESTOCK (Used by RestockDialog) ---
      if (RegExp(r'^/products/\d+/restock$').hasMatch(path)) {
        final productId = int.tryParse(path.split('/')[2]);
        if (productId == null) throw Exception('ID Produk tidak valid');
        
        final addedQty = (body?['added_qty'] as num?)?.toDouble() ?? 0.0;
        final totalCost = (body?['total_cost'] as num?)?.toDouble() ?? 0.0;
        final updatedPrices = body?['updated_selling_prices'] as List? ?? [];
        
        late double newPurchasePrice;
        
        await db.transaction((txn) async {
          // Get current stock and purchase price
          final pRow = await txn.query('products', columns: ['purchase_price'], where: 'id = ?', whereArgs: [productId]);
          final oldPP = pRow.isNotEmpty ? (pRow.first['purchase_price'] as num).toDouble() : 0.0;
          
          final iRow = await txn.query('inventory', columns: ['stock_quantity'], where: 'product_id = ?', whereArgs: [productId]);
          final oldStock = iRow.isNotEmpty ? (iRow.first['stock_quantity'] as num).toDouble() : 0.0;
          
          // AVCO calculation
          final totalOldValue = oldPP * oldStock;
          final newTotalStock = oldStock + addedQty;
          newPurchasePrice = newTotalStock > 0 ? (totalOldValue + totalCost) / newTotalStock : (addedQty > 0 ? totalCost / addedQty : 0);
          
          // Record history
          await txn.insert('restock_history', {
            'product_id': productId,
            'added_base_stock': addedQty,
            'total_cost': totalCost,
            'old_purchase_price': oldPP,
            'new_purchase_price': newPurchasePrice,
          });
          
          // Update purchase price
          await txn.update('products', {'purchase_price': newPurchasePrice}, where: 'id = ?', whereArgs: [productId]);
          
          // Update stock
          final count = await txn.rawUpdate('UPDATE inventory SET stock_quantity = stock_quantity + ? WHERE product_id = ?', [addedQty, productId]);
          if (count == 0) {
            await txn.insert('inventory', {'product_id': productId, 'stock_quantity': addedQty, 'min_stock_alert': 0});
          }
          
          // Update selling prices if provided
          if (updatedPrices.isNotEmpty) {
            await txn.delete('product_units', where: 'product_id = ?', whereArgs: [productId]);
            for (var u in updatedPrices) {
              await txn.insert('product_units', {
                'product_id': productId,
                'unit_name': u['unit_name']?.toString() ?? 'pcs',
                'qty_per_unit': (u['qty_per_unit'] as num?)?.toDouble() ?? 1.0,
                'price': (u['price'] as num?)?.toDouble() ?? 0.0,
              });
            }
          }
        });
        
        return {'success': true, 'purchase_price': newPurchasePrice};
      }

      // --- PRODUCTS: ADD NEW ---
      if (path == '/products') {
        final name = body?['name']?.toString() ?? 'Produk Baru';
        final categoryId = body?['category_id'] as int?;
        final barcode = body?['barcode']?.toString() ?? '';
        final purchasePrice = (body?['purchase_price'] as num?)?.toDouble() ?? 0.0;
        final stockQuantity = (body?['stock'] as num?)?.toDouble() ?? 0.0;
        final minStockAlert = (body?['min_stock'] as num?)?.toDouble() ?? 0.0;
        final baseUnit = body?['base_unit']?.toString() ?? 'pcs';
        final purchaseUnit = body?['purchase_unit']?.toString() ?? '';
        final stockUnit = body?['stock_unit']?.toString() ?? '';
        final unitPrices = body?['unit_prices'] as List<dynamic>? ?? [];
        
        await db.transaction((txn) async {
          final productId = await txn.insert('products', {
            'name': name,
            'category_id': categoryId,
            'barcode': barcode.isEmpty ? null : barcode,
            'purchase_price': purchasePrice,
            'purchase_unit': purchaseUnit,
            'base_unit': baseUnit,
            'is_active': 1,
          });
          
          await txn.insert('inventory', {
            'product_id': productId,
            'stock_quantity': stockQuantity,
            'min_stock_alert': minStockAlert,
            'stock_unit': stockUnit,
          });
          
          if (unitPrices.isEmpty) {
            await txn.insert('product_units', {
              'product_id': productId,
              'unit_name': baseUnit,
              'qty_per_unit': 1.0,
              'price': 0.0,
            });
          } else {
            for (var u in unitPrices) {
              await txn.insert('product_units', {
                'product_id': productId,
                'unit_name': u['unit_name']?.toString() ?? 'pcs',
                'qty_per_unit': (u['qty_per_unit'] as num?)?.toDouble() ?? 1.0,
                'price': (u['price'] as num?)?.toDouble() ?? 0.0,
              });
            }
          }
        });
        return {'success': true};
      }

      throw Exception('Endpoint POST $path belum diimplementasikan di Offline Router');
    } catch (e) {
      if (e.toString().contains('Exception:')) rethrow;
      throw Exception('Gagal menyimpan data lokal: ${e.toString()}');
    }
  }

  static Future<dynamic> put(String path, {dynamic body}) async {
    try {
      final db = await LocalDb.instance;
      
      // --- SETTINGS ---
      if (path == '/settings') {
        final map = body as Map<String, dynamic>? ?? {};
        final batch = db.batch();
        for (final entry in map.entries) {
          batch.execute(
            'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
            [entry.key, entry.value?.toString() ?? '']
          );
        }
        await batch.commit();
        return {'success': true};
      }

      // --- AUTH PROFILE ---
      if (path == '/auth/profile') {
        if (_authToken.isEmpty) throw Exception('Sesi habis, silakan login kembali');
        final userId = _authToken.replaceFirst('offline-token-', '');
        final users = await db.query('users', where: 'id = ?', whereArgs: [userId]);
        if (users.isEmpty) throw Exception('Sesi habis, silakan login kembali');
        final currentUser = users.first;
        
        Map<String, dynamic> data = {};
        
        // Name update
        if (body?['name'] != null && body!['name'].toString().trim().isNotEmpty) {
          data['name'] = body['name'].toString().trim();
        }
        
        // Password update — UI sends old_password / new_password / confirm_password
        if (body?['new_password'] != null && body!['new_password'].toString().isNotEmpty) {
          final oldPw = body['old_password']?.toString() ?? '';
          final newPw = body['new_password'].toString();
          final confirmPw = body['confirm_password']?.toString() ?? '';
          if (oldPw != currentUser['password'].toString()) throw Exception('Password lama salah');
          if (newPw != confirmPw) throw Exception('Konfirmasi password tidak cocok');
          if (newPw.length < 4) throw Exception('Password minimal 4 karakter');
          data['password'] = newPw;
        }
        
        // PIN update — UI sends old_pin / new_pin / confirm_pin
        if (body?['new_pin'] != null && body!['new_pin'].toString().isNotEmpty) {
          final oldPin = body['old_pin']?.toString() ?? '';
          final newPin = body['new_pin'].toString();
          final confirmPin = body['confirm_pin']?.toString() ?? '';
          if (oldPin != currentUser['pin'].toString()) throw Exception('PIN lama salah');
          if (newPin != confirmPin) throw Exception('Konfirmasi PIN tidak cocok');
          if (newPin.length < 4) throw Exception('PIN minimal 4 digit');
          data['pin'] = newPin;
        }
        
        if (data.isNotEmpty) {
          final count = await db.update('users', data, where: 'id = ?', whereArgs: [userId]);
          debugPrint('AUTH PROFILE UPDATE: $count rows affected for user $userId with keys ${data.keys}');
        }
        return {'success': true};
      }

      // --- USERS ---
      if (path.startsWith('/users/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Kasir tidak valid');
        
        final map = body ?? {};
        Map<String, dynamic> data = {};
        if (map['name'] != null) data['name'] = map['name'];
        if (map['password'] != null) data['password'] = map['password'];
        if (map['pin'] != null) data['pin'] = map['pin'];
        if (map['role'] != null) data['role'] = map['role'];
        if (map['is_active'] != null) data['is_active'] = (map['is_active'] == true || map['is_active'] == 1) ? 1 : 0;
        
        if (data.isNotEmpty) {
          await db.update('users', data, where: 'id = ?', whereArgs: [id]);
        }
        return {'success': true};
      }

      // --- CATEGORIES ---
      if (path.startsWith('/categories/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Kategori tidak valid');
        
        try {
          await db.transaction((txn) async {
            Map<String, dynamic> data = {};
            if (body?['name'] != null) data['name'] = body!['name'].toString().trim();
            if (body?['icon'] != null) data['icon'] = body!['icon'].toString();
            if (body?['sort_order'] != null) data['sort_order'] = (body!['sort_order'] as num?)?.toInt() ?? 0;
            
            if (data.isNotEmpty) {
              await txn.update('categories', data, where: 'id = ?', whereArgs: [id]);
            }
            
            // Replace units if provided
            final unitsList = body?['units'] as List?;
            if (unitsList != null) {
              await txn.delete('category_units', where: 'category_id = ?', whereArgs: [id]);
              for (int i = 0; i < unitsList.length; i++) {
                await txn.insert('category_units', {
                  'category_id': id,
                  'unit_name': unitsList[i].toString().trim().toLowerCase(),
                  'sort_order': i,
                });
              }
            }
          });
          return {'success': true};
        } catch (e) {
          if (e.toString().contains('UNIQUE constraint failed')) {
            throw Exception('Nama kategori sudah ada, silakan gunakan nama lain.');
          }
          rethrow;
        }
      }

      // --- PRODUCTS: UPDATE ---
      if (path.startsWith('/products/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Produk tidak valid');
        
        final isActive = body?['is_active'] as int?;
        if (isActive != null) {
          // Quick toggle
          await db.update('products', {'is_active': isActive}, where: 'id = ?', whereArgs: [id]);
          return {'success': true};
        }

        final name = body?['name']?.toString();
        final categoryId = body?['category_id'] as int?;
        final barcode = body?['barcode']?.toString();
        final purchasePrice = (body?['purchase_price'] as num?)?.toDouble();
        final purchaseUnit = body?['purchase_unit']?.toString();
        final baseUnit = body?['base_unit']?.toString();
        final stockUnit = body?['stock_unit']?.toString();
        final stockQuantity = (body?['stock'] as num?)?.toDouble();
        final minStockAlert = (body?['min_stock'] as num?)?.toDouble();
        final unitPrices = body?['unit_prices'] as List<dynamic>?;
        
        await db.transaction((txn) async {
          Map<String, dynamic> pData = {};
          if (name != null) pData['name'] = name;
          if (categoryId != null) pData['category_id'] = categoryId;
          if (barcode != null) pData['barcode'] = barcode.isEmpty ? null : barcode;
          if (purchasePrice != null) pData['purchase_price'] = purchasePrice;
          if (purchaseUnit != null) pData['purchase_unit'] = purchaseUnit;
          if (baseUnit != null) pData['base_unit'] = baseUnit;
          if (pData.isNotEmpty) await txn.update('products', pData, where: 'id = ?', whereArgs: [id]);
          
          if (stockQuantity != null || minStockAlert != null || stockUnit != null) {
            Map<String, dynamic> iData = {};
            if (stockQuantity != null) iData['stock_quantity'] = stockQuantity;
            if (minStockAlert != null) iData['min_stock_alert'] = minStockAlert;
            if (stockUnit != null) iData['stock_unit'] = stockUnit;
            final count = await txn.update('inventory', iData, where: 'product_id = ?', whereArgs: [id]);
            if (count == 0) {
              await txn.insert('inventory', {
                'product_id': id,
                'stock_quantity': stockQuantity ?? 0,
                'min_stock_alert': minStockAlert ?? 0,
                'stock_unit': stockUnit ?? '',
              });
            }
          }

          if (unitPrices != null && unitPrices.isNotEmpty) {
            await txn.delete('product_units', where: 'product_id = ?', whereArgs: [id]);
            for (var u in unitPrices) {
              await txn.insert('product_units', {
                'product_id': id,
                'unit_name': u['unit_name']?.toString() ?? 'pcs',
                'qty_per_unit': (u['qty_per_unit'] as num?)?.toDouble() ?? 1.0,
                'price': (u['price'] as num?)?.toDouble() ?? 0.0,
              });
            }
          }
        });
        return {'success': true};
      }
      // --- DISCOUNTS ---
      if (path.startsWith('/discounts/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Diskon tidak valid');
        
        final map = body ?? {};
        Map<String, dynamic> data = {};
        if (map['name'] != null) data['name'] = map['name'];
        if (map['target_categories'] != null) data['target_categories'] = jsonEncode(map['target_categories']);
        if (map['target_products'] != null) data['target_products'] = jsonEncode(map['target_products']);
        if (map['discount_percent'] != null) data['discount_percent'] = (map['discount_percent'] as num).toInt();
        if (map['schedule_type'] != null) data['schedule_type'] = map['schedule_type'];
        if (map['schedule_value'] != null) data['schedule_value'] = map['schedule_value'];
        if (map['is_active'] != null) data['is_active'] = (map['is_active'] == true || map['is_active'] == 1) ? 1 : 0;
        
        if (data.isNotEmpty) {
          await db.update('discounts', data, where: 'id = ?', whereArgs: [id]);
        }
        return {'success': true};
      }
      
      throw Exception('Endpoint PUT $path belum diimplementasikan di Offline Router');
    } catch (e) {
      if (e.toString().contains('Exception:')) rethrow;
      throw Exception('Gagal memperbarui data lokal: ${e.toString()}');
    }
  }

  static Future<dynamic> delete(String path) async {
    try {
      final db = await LocalDb.instance;
      
      // --- HELD CARTS: DELETE (alias: /transactions/held/ OR /held-carts/) ---
      if (path.startsWith('/transactions/held/') || path.startsWith('/held-carts/')) {
        final id = path.split('/').last;
        await db.delete('held_carts', where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }

      // --- USERS ---
      if (path.startsWith('/users/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID User tidak valid');
        await db.update('users', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }

      // --- CATEGORIES ---
      if (path.startsWith('/categories/')) {
        final rawId = path.split('/').last.split('?').first; // strip query params like ?force=1
        final id = int.tryParse(rawId);
        if (id == null) throw Exception('ID Kategori tidak valid');
        await db.delete('category_units', where: 'category_id = ?', whereArgs: [id]);
        await db.delete('categories', where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }

      // --- PRODUCTS: DELETE ---
      if (path.startsWith('/products/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Produk tidak valid');
        await db.delete('products', where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }

      // --- DISCOUNTS ---
      if (path.startsWith('/discounts/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Diskon tidak valid');
        await db.delete('discounts', where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }
      
      throw Exception('Endpoint DELETE $path belum diimplementasikan di Offline Router');
    } catch (e) {
      if (e.toString().contains('Exception:')) rethrow;
      throw Exception('Gagal menghapus data lokal: ${e.toString()}');
    }
  }
}
