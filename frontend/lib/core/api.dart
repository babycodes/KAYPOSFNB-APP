// KAYPOS OFFLINE — Embedded Local Router
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
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
        final List<Map<String, dynamic>> result = [];
        for (final c in rows) {
          try {
            result.add({
              'id': (c['id'] as num).toInt(),
              'name': (c['name'] ?? 'Kategori').toString(),
              'icon': (c['icon'] ?? '📦').toString(),
              'sort_order': c['sort_order'] ?? 0,
              'total_products': (c['total_products'] as num?)?.toInt() ?? 0,
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
          SELECT 
            p.id, 
            p.category_id, 
            p.name, 
            p.description, 
            p.price, 
            p.image_url, 
            p.barcode,
            c.name as category_name, 
            c.icon as category_icon,
            p.is_active,
            COALESCE(p.is_paket, 0) as is_paket,
            CASE 
              WHEN COALESCE(p.is_paket, 0) = 1 THEN IFNULL((SELECT SUM(pi.qty * IFNULL((SELECT SUM(r.qty_needed * (CASE WHEN LOWER(b.unit) IN ('kg','liter','l') THEN b.cost_price / 1000.0 ELSE b.cost_price END)) FROM resep r JOIN bahan_baku b ON r.bahan_baku_id = b.id WHERE r.product_id = pi.product_id), 0)) FROM paket_items pi WHERE pi.paket_id = p.id), 0)
              ELSE IFNULL((SELECT SUM(r.qty_needed * (CASE WHEN LOWER(b.unit) IN ('kg','liter','l') THEN b.cost_price / 1000.0 ELSE b.cost_price END)) FROM resep r JOIN bahan_baku b ON r.bahan_baku_id = b.id WHERE r.product_id = p.id), 0)
            END as total_hpp,
            (SELECT CAST(MIN((CASE WHEN LOWER(b.unit) IN ('kg','liter','l') THEN b.stock * 1000 ELSE b.stock END) / r.qty_needed) AS INTEGER) FROM resep r JOIN bahan_baku b ON r.bahan_baku_id = b.id WHERE r.product_id = p.id AND r.qty_needed > 0) as available_portions
          FROM products p
          LEFT JOIN categories c ON p.category_id = c.id
          $activeFilter
          ORDER BY p.name ASC
        ''');
        
        // Post-process: compute available_portions for paket products
        List<Map<String, dynamic>> result = [];
        for (final r in rows) {
          final map = {
            ...r,
            'category_name': r['category_name'] ?? '-',
            'category_icon': r['category_icon'] ?? '\u{1F4E6}',
            'is_active': r['is_active'] ?? 1,
          };
          if ((r['is_paket'] as num?)?.toInt() == 1) {
            try {
              final paketItems = await db.rawQuery('''
                SELECT pi.*, p.name as product_name 
                FROM paket_items pi 
                JOIN products p ON pi.product_id = p.id 
                WHERE pi.paket_id = ?
              ''', [r['id']]);
              map['paket_items'] = paketItems;
              // Do NOT set available_portions here — paket stock is computed
              // dynamically on the client side via _getEffectiveStock() to avoid
              // stale snapshot race conditions.
              map['available_portions'] = null;
            } catch (_) {
              map['paket_items'] = [];
              map['available_portions'] = null;
            }
          }
          result.add(map);
        }
        return result;
      }

      // --- SINGLE PRODUCT (for Restock Dialog) ---
      if (RegExp(r'^/products/\d+$').hasMatch(path)) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Produk tidak valid');
        final rows = await db.rawQuery('''
          SELECT 
            p.id, 
            p.category_id, 
            p.name, 
            p.description, 
            p.price, 
            p.image_url, 
            p.barcode,
            c.name as category_name, 
            c.icon as category_icon,
            p.is_active,
            CASE 
              WHEN COALESCE(p.is_paket, 0) = 1 THEN IFNULL((SELECT SUM(pi.qty * IFNULL((SELECT SUM(r.qty_needed * (CASE WHEN LOWER(b.unit) IN ('kg','liter','l') THEN b.cost_price / 1000.0 ELSE b.cost_price END)) FROM resep r JOIN bahan_baku b ON r.bahan_baku_id = b.id WHERE r.product_id = pi.product_id), 0)) FROM paket_items pi WHERE pi.paket_id = p.id), 0)
              ELSE IFNULL((SELECT SUM(r.qty_needed * (CASE WHEN LOWER(b.unit) IN ('kg','liter','l') THEN b.cost_price / 1000.0 ELSE b.cost_price END)) FROM resep r JOIN bahan_baku b ON r.bahan_baku_id = b.id WHERE r.product_id = p.id), 0)
            END as total_hpp
          FROM products p
          LEFT JOIN categories c ON p.category_id = c.id
          WHERE p.id = ?
        ''', [id]);
        if (rows.isEmpty) throw Exception('Produk tidak ditemukan');
        final r = rows.first;
        return {
          ...r,
          'category_name': r['category_name'] ?? '-',
          'category_icon': r['category_icon'] ?? '\u{1F4E6}',
        };
      }

      // --- KATEGORI BAHAN ---
      if (path == '/kategori-bahan') {
        final rows = await db.rawQuery('''
          SELECT kb.*, (SELECT COUNT(id) FROM bahan_baku WHERE kategori_bahan_id = kb.id) as item_count
          FROM kategori_bahan kb
          ORDER BY kb.name ASC
        ''');
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      }

      // --- BAHAN BAKU ---
      if (path == '/bahan-baku') {
        final rows = await db.rawQuery('''
          SELECT b.*, COALESCE(kb.name, b.kategori, 'Lainnya') as kategori_name
          FROM bahan_baku b
          LEFT JOIN kategori_bahan kb ON b.kategori_bahan_id = kb.id
          ORDER BY b.name ASC
        ''');
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      }
      
      if (path == '/bahan-baku/alerts') {
        final rows = await db.rawQuery('SELECT * FROM bahan_baku WHERE stock <= min_stock_alert');
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      }

      // --- STOCK POOL (Recipes + Material Stocks for Cashier real-time calc) ---
      if (path == '/stock-pool') {
        final rows = await db.rawQuery('''
          SELECT r.product_id, r.bahan_baku_id, r.qty_needed, b.stock as bahan_stock, b.unit as bahan_unit
          FROM resep r
          JOIN bahan_baku b ON r.bahan_baku_id = b.id
          WHERE r.qty_needed > 0
        ''');
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      }

      // --- RESEP (By Product ID) ---
      if (RegExp(r'^/resep/\d+$').hasMatch(path)) {
        final productId = int.tryParse(path.split('/').last);
        if (productId == null) throw Exception('ID Produk tidak valid');
        
        final rows = await db.rawQuery('''
          SELECT r.*, b.name as bahan_name, b.unit as bahan_unit, b.cost_price as bahan_cost_price
          FROM resep r
          JOIN bahan_baku b ON r.bahan_baku_id = b.id
          WHERE r.product_id = ?
        ''', [productId]);
        return rows;
      }

      // --- PAKET ITEMS (By Paket Product ID) ---
      if (RegExp(r'^/paket-items/\d+$').hasMatch(path)) {
        final paketId = int.tryParse(path.split('/').last);
        if (paketId == null) throw Exception('ID Paket tidak valid');
        
        final rows = await db.rawQuery('''
          SELECT pi.*, p.name as product_name, p.price as product_price,
            c.icon as product_icon, c.name as category_name,
            IFNULL((SELECT SUM(r.qty_needed * (CASE WHEN LOWER(b.unit) IN ('kg','liter','l') THEN b.cost_price / 1000.0 ELSE b.cost_price END)) FROM resep r JOIN bahan_baku b ON r.bahan_baku_id = b.id WHERE r.product_id = pi.product_id), 0) as hpp
          FROM paket_items pi
          JOIN products p ON pi.product_id = p.id
          LEFT JOIN categories c ON p.category_id = c.id
          WHERE pi.paket_id = ?
        ''', [paketId]);
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      }

      // --- BOTTLENECK DETAIL (Why out of stock) ---
      if (RegExp(r'^/products/\d+/bottleneck$').hasMatch(path)) {
        final productId = int.tryParse(path.split('/')[2]);
        if (productId == null) throw Exception('ID Produk tidak valid');
        
        // Check if paket
        final pRow = await db.query('products', columns: ['is_paket'], where: 'id = ?', whereArgs: [productId]);
        final isPaket = pRow.isNotEmpty && (pRow.first['is_paket'] as num?)?.toInt() == 1;
        
        if (isPaket) {
          // For paket: find child products that are out of stock
          final items = await db.rawQuery('''
            SELECT pi.qty, p.name as product_name,
              (SELECT CAST(MIN((CASE WHEN LOWER(b.unit) IN ('kg','liter','l') THEN b.stock * 1000 ELSE b.stock END) / re.qty_needed) AS INTEGER) 
               FROM resep re JOIN bahan_baku b ON re.bahan_baku_id = b.id 
               WHERE re.product_id = pi.product_id AND re.qty_needed > 0) as child_portions
            FROM paket_items pi
            JOIN products p ON pi.product_id = p.id
            WHERE pi.paket_id = ?
          ''', [productId]);
          
          final missing = <Map<String, dynamic>>[];
          for (final item in items) {
            final childPortions = (item['child_portions'] as num?)?.toInt() ?? 0;
            final qty = (item['qty'] as num?)?.toInt() ?? 1;
            if (childPortions < qty) {
              missing.add({
                'name': item['product_name'],
                'available': childPortions,
                'needed': qty,
              });
            }
          }
          return {'is_paket': true, 'items': missing};
        } else {
          // For regular: find insufficient ingredients
          final rows = await db.rawQuery('''
            SELECT b.name, b.stock, r.qty_needed, b.unit,
              (CASE WHEN LOWER(b.unit) IN ('kg','liter','l') THEN b.stock * 1000 ELSE b.stock END) as normalized_stock
            FROM resep r
            JOIN bahan_baku b ON r.bahan_baku_id = b.id
            WHERE r.product_id = ? AND (CASE WHEN LOWER(b.unit) IN ('kg','liter','l') THEN b.stock * 1000 ELSE b.stock END) < r.qty_needed
          ''', [productId]);
          return {'is_paket': false, 'items': rows.map((r) => Map<String, dynamic>.from(r)).toList()};
        }
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
        final txRows = await db.query('transactions',
          where: "created_at >= ? AND (status IS NULL OR status != 'voided')",
          whereArgs: [todayStart]);
        
        double totalSales = 0;
        double totalProfit = 0;
        try {
          final statsRows = await db.rawQuery('''
            WITH ProductCOGS AS (
              SELECT r.product_id, SUM(r.qty_needed * b.cost_price) as hpp_per_unit
              FROM resep r
              JOIN bahan_baku b ON r.bahan_baku_id = b.id
              GROUP BY r.product_id
            ),
            TotalCOGS AS (
              SELECT SUM((td.quantity - COALESCE(td.refunded_qty, 0)) * pc.hpp_per_unit) as cogs
              FROM transaction_details td
              JOIN transactions t ON td.transaction_id = t.id
              JOIN ProductCOGS pc ON td.product_id = pc.product_id
              WHERE t.created_at >= ? AND (t.status IS NULL OR t.status != 'voided')
            ),
            TotalSales AS (
              SELECT SUM(total_amount) as sales
              FROM transactions
              WHERE created_at >= ? AND (status IS NULL OR status != 'voided')
            )
            SELECT s.sales, COALESCE(c.cogs, 0) as cogs
            FROM TotalSales s
            LEFT JOIN TotalCOGS c ON 1=1
          ''', [todayStart, todayStart]);
          
          if (statsRows.isNotEmpty) {
            totalSales = (statsRows.first['sales'] as num?)?.toDouble() ?? 0.0;
            final totalCogs = (statsRows.first['cogs'] as num?)?.toDouble() ?? 0.0;
            totalProfit = totalSales - totalCogs;
          }
        } catch (_) {}
        
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
        final details = await db.rawQuery('''
          SELECT td.*, COALESCE(p.is_paket, 0) as is_paket
          FROM transaction_details td
          LEFT JOIN products p ON td.product_id = p.id
          WHERE td.transaction_id = ?
        ''', [txId]);
        
        List<Map<String, dynamic>> enrichedDetails = [];
        for (var d in details) {
          final m = Map<String, dynamic>.from(d);
          m['unit_used'] = m['unit_used'] ?? 'pcs';
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
          final details = await db.rawQuery('''
            SELECT td.*, COALESCE(p.is_paket, 0) as is_paket
            FROM transaction_details td
            LEFT JOIN products p ON td.product_id = p.id
            WHERE td.transaction_id = ?
          ''', [t['id']]);
          List<Map<String, dynamic>> enrichedDetails = [];
          double refundedAmount = 0;
          for (var d in details) {
            final dm = Map<String, dynamic>.from(d);
            dm['unit_used'] = dm['unit_used'] ?? 'pcs';
            enrichedDetails.add(dm);

            final refundedQty = (dm['refunded_qty'] as num?)?.toDouble() ?? 0;
            if (refundedQty > 0) {
              final soldPrice = (dm['sold_price'] as num?)?.toDouble() ?? 0;
              final discountPct = (dm['discount_percent'] as num?)?.toDouble() ?? 0;
              final effectivePrice = soldPrice * (1 - discountPct / 100);
              refundedAmount += refundedQty * effectivePrice;
            }
          }
          final m = Map<String, dynamic>.from(t);
          m['items'] = enrichedDetails;
          m['refunded_amount'] = refundedAmount;
          results.add(m);
        }
        
        final limited = (limitParam != null) ? results.take(limitParam).toList() : results;
        return {'data': limited, 'total': results.length};
      }
      
      // --- INVENTORY: FULL LIST (for Stok/Inventaris page) ---
      if (path == '/inventory') {
        final rows = await db.rawQuery('''
          SELECT 
            p.id, 
            p.category_id, 
            p.name, 
            p.description, 
            p.price, 
            p.image_url, 
            p.barcode,
            c.name as category_name, 
            c.icon as category_icon,
            p.is_active
          FROM products p
          LEFT JOIN categories c ON p.category_id = c.id
          WHERE p.is_active = 1
          ORDER BY p.name ASC
        ''');
        return rows.map((r) {
          return {
            ...r,
            'id': r['id'],
            'product_id': r['id'],
            'name': r['name']?.toString() ?? '',
            'category_name': r['category_name'] ?? '-',
            'category_icon': r['category_icon'] ?? '\u{1F4E6}',
            'stock_quantity': 0.0,
            'min_stock_alert': 0.0,
            'purchase_price': (r['price'] as num?)?.toDouble() ?? 0.0,
            'base_unit': 'pcs',
            'units': [],
          };
        }).toList();
      }

      // --- INVENTORY: LOW STOCK ---
      if (path == '/inventory/low-stock' || path == '/inventory/out-of-stock') {
        final rows = await db.rawQuery('''
          SELECT id, name, unit, stock, min_stock_alert, cost_price
          FROM bahan_baku
          WHERE min_stock_alert > 0 AND stock <= min_stock_alert
          ORDER BY stock ASC
        ''');
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      }

      // --- REPORTS: DASHBOARD SUMMARY ---
      if (path == '/reports/dashboard-summary') {
        final now = DateTime.now();
        final todayStart = '${now.toIso8601String().substring(0, 10)} 00:00:00';
        final monthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';

        // Today's revenue & count (exclude voided)
        final todayRows = await db.rawQuery('''
          SELECT COUNT(*) as cnt, COALESCE(SUM(total_amount), 0) as revenue
          FROM transactions
          WHERE created_at >= ? AND (status IS NULL OR status != 'voided')
        ''', [todayStart]);
        final todayRevenue = (todayRows.first['revenue'] as num?)?.toDouble() ?? 0;
        final todayTxCount = (todayRows.first['cnt'] as num?)?.toInt() ?? 0;

        // Monthly revenue (exclude voided)
        final monthRows = await db.rawQuery('''
          SELECT COALESCE(SUM(total_amount), 0) as revenue
          FROM transactions
          WHERE created_at LIKE ? AND (status IS NULL OR status != 'voided')
        ''', ['$monthPrefix%']);
        final monthlyRevenue = (monthRows.first['revenue'] as num?)?.toDouble() ?? 0;

        // Monthly COGS (HPP) — BOM-based via CTE
        double monthlyCogs = 0;
        try {
          final cogsRows = await db.rawQuery('''
            WITH ProductCOGS AS (
              SELECT r.product_id, SUM(r.qty_needed * b.cost_price) as hpp_per_unit
              FROM resep r
              JOIN bahan_baku b ON r.bahan_baku_id = b.id
              GROUP BY r.product_id
            )
            SELECT COALESCE(SUM((td.quantity - COALESCE(td.refunded_qty, 0)) * pc.hpp_per_unit), 0) as total_cogs
            FROM transaction_details td
            JOIN transactions t ON td.transaction_id = t.id
            JOIN ProductCOGS pc ON td.product_id = pc.product_id
            WHERE t.created_at LIKE ? AND (t.status IS NULL OR t.status != 'voided')
          ''', ['$monthPrefix%']);
          monthlyCogs = (cogsRows.first['total_cogs'] as num?)?.toDouble() ?? 0;
        } catch (e) {
          debugPrint('Error calculating monthly COGS: \$e');
        }

        final monthlyProfit = monthlyRevenue - monthlyCogs;

        return {
          'today_revenue': todayRevenue,
          'today_tx_count': todayTxCount,
          'monthly_revenue': monthlyRevenue,
          'monthly_cogs': monthlyCogs,
          'monthly_profit': monthlyProfit,
        };
      }

      // --- REPORTS: TOP WASTE (Top 5 by financial loss) ---
      if (path == '/reports/top-waste') {
        final now = DateTime.now();
        final monthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        final rows = await db.rawQuery('''
          SELECT il.bahan_baku_id,
                 b.name, b.unit,
                 COALESCE(SUM(ABS(il.qty_change)), 0) AS total_qty,
                 COALESCE(SUM(ABS(il.financial_value)), 0) AS total_loss
          FROM inventory_ledger il
          JOIN bahan_baku b ON b.id = il.bahan_baku_id
          WHERE il.transaction_type = 'WASTE' AND il.timestamp LIKE ?
          GROUP BY il.bahan_baku_id
          ORDER BY total_loss DESC
          LIMIT 5
        ''', ['$monthPrefix%']);
        return rows.map((r) => {
          'bahan_baku_id': r['bahan_baku_id'],
          'name': r['name']?.toString() ?? '',
          'unit': r['unit']?.toString() ?? '',
          'total_qty': (r['total_qty'] as num?)?.toDouble() ?? 0,
          'total_loss': (r['total_loss'] as num?)?.toDouble() ?? 0,
        }).toList();
      }

      // --- REPORTS: CHART 28 DAYS ---
      if (path == '/reports/chart28') {
        final past28 = DateTime.now().subtract(const Duration(days: 28)).toIso8601String().substring(0, 10);
        
        // Get daily sales and COGS using CTE
        final chartRows = await db.rawQuery('''
          WITH ProductCOGS AS (
            SELECT r.product_id, SUM(r.qty_needed * b.cost_price) as hpp_per_unit
            FROM resep r
            JOIN bahan_baku b ON r.bahan_baku_id = b.id
            GROUP BY r.product_id
          ),
          DailyCOGS AS (
            SELECT date(t.created_at) as date, 
                   SUM((td.quantity - COALESCE(td.refunded_qty, 0)) * pc.hpp_per_unit) as cogs
            FROM transaction_details td
            JOIN transactions t ON td.transaction_id = t.id
            JOIN ProductCOGS pc ON td.product_id = pc.product_id
            WHERE date(t.created_at) >= ? AND (t.status IS NULL OR t.status != 'voided')
            GROUP BY date(t.created_at)
          ),
          DailySales AS (
            SELECT date(created_at) as date, SUM(total_amount) as sales
            FROM transactions
            WHERE date(created_at) >= ? AND (status IS NULL OR status != 'voided')
            GROUP BY date(created_at)
          )
          SELECT s.date, s.sales, COALESCE(c.cogs, 0) as cogs
          FROM DailySales s
          LEFT JOIN DailyCOGS c ON s.date = c.date
          ORDER BY s.date ASC
        ''', [past28, past28]);
        
        List<Map<String, dynamic>> result = [];
        for (var row in chartRows) {
          final sales = (row['sales'] as num?)?.toDouble() ?? 0.0;
          final cogs = (row['cogs'] as num?)?.toDouble() ?? 0.0;
          result.add({
            'date': row['date']?.toString() ?? '',
            'sales': sales,
            'profit': sales - cogs,
          });
        }
        return result;
      }

      // --- REPORTS: TOP PRODUCTS (exclude voided, use effective qty) ---
      if (path.startsWith('/reports/products')) {
        final rows = await db.rawQuery('''
          SELECT d.product_id, d.product_name,
                 COALESCE(SUM(d.quantity - d.refunded_qty), 0) as total_qty,
                 COALESCE(SUM((d.sold_price * (1 - d.discount_percent / 100.0)) * (d.quantity - d.refunded_qty)), 0) as total_revenue
          FROM transaction_details d
          JOIN transactions t ON t.id = d.transaction_id
          WHERE (t.status IS NULL OR t.status != 'voided')
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
        
        // Summary (exclude voided)
        final sumRows = await db.rawQuery('''
          SELECT COUNT(*) as cnt, COALESCE(SUM(total_amount), 0) as sales
          FROM transactions WHERE created_at LIKE ? AND (status IS NULL OR status != 'voided')
        ''', ['$prefix%']);
        
        final summary = {
          'total_transactions': (sumRows.first['cnt'] as num?)?.toInt() ?? 0,
          'total_sales': (sumRows.first['sales'] as num?)?.toDouble() ?? 0.0,
        };
        
        // Daily breakdown (exclude voided)
        final dailyRows = await db.rawQuery('''
          SELECT date(created_at) as date, COUNT(*) as count, COALESCE(SUM(total_amount), 0) as sales
          FROM transactions WHERE created_at LIKE ? AND (status IS NULL OR status != 'voided')
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
      // --- REPORTS: KARTU STOK (Inventory Ledger per bahan_baku) ---
      if (path.startsWith('/reports/kartu-stok')) {
        String? dateStart;
        String? dateEnd;
        int? kategoriId;
        if (path.contains('?')) {
          final query = path.split('?').last;
          for (final part in query.split('&')) {
            final kv = part.split('=');
            if (kv.length == 2) {
              if (kv[0] == 'start_date') dateStart = kv[1];
              if (kv[0] == 'end_date') dateEnd = kv[1];
              if (kv[0] == 'kategori_id') kategoriId = int.tryParse(kv[1]);
            }
          }
        }
        // Default: current month 1st → today
        final now = DateTime.now();
        dateStart ??= '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
        dateEnd ??= '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

        // Base query: all bahan_baku (optionally filtered by category)
        final bahanWhere = kategoriId != null ? 'WHERE b.kategori_bahan_id = ?' : '';
        final bahanArgs = kategoriId != null ? [kategoriId] : <dynamic>[];

        final bahanRows = await db.rawQuery('''
          SELECT b.id, b.name, b.unit, b.stock as system_stock, b.cost_price,
                 COALESCE(kb.name, b.kategori, 'Lainnya') as kategori_name,
                 b.kategori_bahan_id
          FROM bahan_baku b
          LEFT JOIN kategori_bahan kb ON b.kategori_bahan_id = kb.id
          $bahanWhere
          ORDER BY b.name ASC
        ''', bahanArgs);

        final tsStart = '$dateStart 00:00:00';
        final tsEnd = '$dateEnd 23:59:59';

        List<Map<String, dynamic>> result = [];
        for (final bahan in bahanRows) {
          final bbId = (bahan['id'] as num).toInt();

          // Aggregate ledger by transaction_type for this material + date range
          final ledger = await db.rawQuery('''
            SELECT
              transaction_type,
              COALESCE(SUM(qty_change), 0) AS total_qty,
              COALESCE(SUM(financial_value), 0) AS total_value,
              COUNT(*) AS entry_count
            FROM inventory_ledger
            WHERE bahan_baku_id = ?
              AND timestamp >= ? AND timestamp <= ?
            GROUP BY transaction_type
          ''', [bbId, tsStart, tsEnd]);

          double totalIn = 0, totalOut = 0, totalWaste = 0, totalAdjustment = 0, totalRefund = 0;
          double restockValue = 0, wasteValue = 0, adjustmentValue = 0;
          int restockCount = 0, saleCount = 0, wasteCount = 0, adjCount = 0, refundCount = 0;

          for (final row in ledger) {
            final type = row['transaction_type']?.toString() ?? '';
            final qty = (row['total_qty'] as num?)?.toDouble() ?? 0;
            final val = (row['total_value'] as num?)?.toDouble() ?? 0;
            final cnt = (row['entry_count'] as num?)?.toInt() ?? 0;
            switch (type) {
              case 'RESTOCK':
                totalIn = qty;
                restockValue = val;
                restockCount = cnt;
              case 'SALE':
                totalOut = qty.abs();
                saleCount = cnt;
              case 'WASTE':
                totalWaste = qty.abs();
                wasteValue = val;
                wasteCount = cnt;
              case 'ADJUSTMENT':
                totalAdjustment = qty;
                adjustmentValue = val;
                adjCount = cnt;
              case 'REFUND':
                totalRefund = qty;
                refundCount = cnt;
            }
          }

          result.add({
            'id': bbId,
            'name': bahan['name'],
            'unit': bahan['unit'],
            'kategori_name': bahan['kategori_name'],
            'kategori_bahan_id': bahan['kategori_bahan_id'],
            'system_stock': (bahan['system_stock'] as num?)?.toDouble() ?? 0,
            'cost_price': (bahan['cost_price'] as num?)?.toDouble() ?? 0,
            'total_in': totalIn,
            'total_out': totalOut,
            'total_waste': totalWaste,
            'total_adjustment': totalAdjustment,
            'total_refund': totalRefund,
            'restock_value': restockValue,
            'waste_value': wasteValue,
            'adjustment_value': adjustmentValue,
            'restock_count': restockCount,
            'sale_count': saleCount,
            'waste_count': wasteCount,
            'adjustment_count': adjCount,
            'refund_count': refundCount,
          });
        }
        return {'data': result, 'start_date': dateStart, 'end_date': dateEnd};
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
        
        try {
          await db.transaction((txn) async {
            await txn.insert('categories', {
              'name': name,
              'icon': icon,
              'sort_order': sortOrder,
            });
          });
          return {'success': true};
        } catch (e) {
          if (e.toString().contains('UNIQUE constraint failed')) {
            throw Exception('Nama kategori "$name" sudah ada, silakan gunakan nama lain.');
          }
          rethrow;
        }
      }

      // --- KATEGORI BAHAN ---
      if (path == '/kategori-bahan') {
        final name = body?['name']?.toString().trim() ?? '';
        if (name.isEmpty) throw Exception('Nama kategori wajib diisi');
        await db.insert('kategori_bahan', {'name': name});
        return {'success': true};
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
            final quantity = (item['quantity'] as num).toDouble();
            final addonSummaryStr = item['addon_summary']?.toString() ?? '[]';

            // Fetch product info
            final pRow = await txn.query('products', where: 'id = ?', whereArgs: [productId]);
            if (pRow.isEmpty) throw Exception('Produk ID $productId tidak ditemukan');
            final product = pRow.first;
            
            // Allow frontend to pass calculated price (if addons applied) or fallback to base price
            final soldPrice = (item['price'] as num?)?.toDouble() ?? (product['price'] as num?)?.toDouble() ?? 0.0;
            
            final subtotal = soldPrice * quantity;
            final discountPercent = (item['discount_percent'] as num?)?.toDouble() ?? 0.0;
            final discountAmount = (item['discount_amount'] as num?)?.toDouble() ?? 0.0;
            
            final isPaketProduct = (product['is_paket'] as num?)?.toInt() == 1;
            
            resolvedItems.add({
              'product_id': productId,
              'product_name': product['name']?.toString() ?? 'Item',
              'is_paket': isPaketProduct ? 1 : 0,
              'sold_price': soldPrice,
              'quantity': quantity,
              'subtotal': subtotal,
              'addon_summary': addonSummaryStr,
              'discount_percent': discountPercent,
              'discount_amount': discountAmount,
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
              'quantity': ri['quantity'],
              'subtotal': ri['subtotal'],
              'addon_summary': ri['addon_summary'],
              'discount_percent': ri['discount_percent'],
              'discount_amount': ri['discount_amount'],
            });
            detailRows.add(ri);

            // BOM Deduction: Handle both regular and paket products
            final productRow = await txn.query('products', columns: ['is_paket'], where: 'id = ?', whereArgs: [ri['product_id']]);
            final isPaket = productRow.isNotEmpty && (productRow.first['is_paket'] as num?)?.toInt() == 1;
            
            if (isPaket) {
              // Paket: deduct stock for each child product's recipe
              final paketChildren = await txn.query('paket_items', where: 'paket_id = ?', whereArgs: [ri['product_id']]);
              for (var child in paketChildren) {
                final childProductId = child['product_id'];
                final childQty = (child['qty'] as num?)?.toInt() ?? 1;
                final childResep = await txn.query('resep', where: 'product_id = ?', whereArgs: [childProductId]);
                for (var r in childResep) {
                  final bbId = r['bahan_baku_id'];
                  final qtyNeeded = (r['qty_needed'] as num).toDouble();
                  final rawDeduction = qtyNeeded * childQty * (ri['quantity'] as double);
                  // Unit-aware deduction: convert recipe base unit → bahan_baku master unit
                  final bbRow = await txn.query('bahan_baku', columns: ['unit'], where: 'id = ?', whereArgs: [bbId]);
                  final bbUnit = bbRow.isNotEmpty ? (bbRow.first['unit']?.toString().toLowerCase() ?? '') : '';
                  final deduction = (bbUnit == 'kg' || bbUnit == 'liter' || bbUnit == 'l') ? rawDeduction / 1000 : rawDeduction;
                  await txn.rawUpdate('UPDATE bahan_baku SET stock = stock - ? WHERE id = ?', [deduction, bbId]);
                  // 📋 Inventory Ledger: record SALE deduction
                  try { await txn.insert('inventory_ledger', {
                    'bahan_baku_id': bbId,
                    'transaction_type': 'SALE',
                    'qty_change': -deduction,
                    'financial_value': 0,
                    'notes': 'Auto-deduct: ${ri['product_name']}',
                  }); } catch (_) {}
                }
              }
            } else {
              // Regular: deduct from bahan_baku based on resep
              final resepRows = await txn.query('resep', where: 'product_id = ?', whereArgs: [ri['product_id']]);
              for (var r in resepRows) {
                final bbId = r['bahan_baku_id'];
                final qtyNeeded = (r['qty_needed'] as num).toDouble();
                final rawDeduction = qtyNeeded * (ri['quantity'] as double);
                // Unit-aware deduction: convert recipe base unit → bahan_baku master unit
                final bbRow = await txn.query('bahan_baku', columns: ['unit'], where: 'id = ?', whereArgs: [bbId]);
                final bbUnit = bbRow.isNotEmpty ? (bbRow.first['unit']?.toString().toLowerCase() ?? '') : '';
                final deduction = (bbUnit == 'kg' || bbUnit == 'liter' || bbUnit == 'l') ? rawDeduction / 1000 : rawDeduction;
                await txn.rawUpdate('UPDATE bahan_baku SET stock = stock - ? WHERE id = ?', [deduction, bbId]);
                // 📋 Inventory Ledger: record SALE deduction
                try { await txn.insert('inventory_ledger', {
                  'bahan_baku_id': bbId,
                  'transaction_type': 'SALE',
                  'qty_change': -deduction,
                  'financial_value': 0,
                  'notes': 'Auto-deduct: ${ri['product_name']}',
                }); } catch (_) {}
              }
            }
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
        final price = (body?['price'] as num?)?.toDouble() ?? 0.0;
        final description = body?['description']?.toString() ?? '';
        final isPaket = (body?['is_paket'] as num?)?.toInt() ?? 0;
        
        final id = await db.insert('products', {
          'name': name,
          'category_id': categoryId,
          'barcode': barcode.isEmpty ? null : barcode,
          'price': price,
          'description': description,
          'is_active': 1,
          'is_paket': isPaket,
        });
        
        return {'success': true, 'id': id};
      }

      // --- BAHAN BAKU ---
      if (path == '/bahan-baku') {
        await db.insert('bahan_baku', {
          'name': body?['name']?.toString() ?? '',
          'unit': body?['unit']?.toString() ?? '',
          'stock': (body?['stock'] as num?)?.toDouble() ?? 0,
          'cost_price': (body?['cost_price'] as num?)?.toDouble() ?? 0,
          'min_stock_alert': (body?['min_stock_alert'] as num?)?.toDouble() ?? 0,
          'kategori': body?['kategori']?.toString() ?? 'Lainnya',
          'kategori_bahan_id': (body?['kategori_bahan_id'] as num?)?.toInt() ?? 0,
        });
        return {'success': true};
      }

      // --- RESEP ---
      if (path == '/resep') {
        await db.insert('resep', {
          'product_id': body?['product_id'],
          'bahan_baku_id': body?['bahan_baku_id'],
          'qty_needed': (body?['qty_needed'] as num?)?.toDouble() ?? 0,
        });
        return {'success': true};
      }

      // --- PAKET ITEMS ---
      if (path == '/paket-items') {
        await db.insert('paket_items', {
          'paket_id': body?['paket_id'],
          'product_id': body?['product_id'],
          'qty': (body?['qty'] as num?)?.toInt() ?? 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        return {'success': true};
      }
      // --- INVENTORY: STOCK OPNAME / ADJUSTMENT ---
      if (path == '/inventory/opname') {
        final bbId = (body?['bahan_baku_id'] as num?)?.toInt();
        final actualStock = (body?['actual_physical_stock'] as num?)?.toDouble();
        final notes = body?['notes']?.toString() ?? '';

        if (bbId == null || actualStock == null) {
          throw Exception('bahan_baku_id dan actual_physical_stock wajib diisi');
        }
        if (actualStock < 0) throw Exception('Stok fisik tidak boleh negatif');

        await db.transaction((txn) async {
          // Fetch current DB stock and cost_price
          final bbRow = await txn.query('bahan_baku',
              columns: ['stock', 'cost_price'],
              where: 'id = ?',
              whereArgs: [bbId]);
          if (bbRow.isEmpty) throw Exception('Bahan baku tidak ditemukan');

          final currentStock = (bbRow.first['stock'] as num?)?.toDouble() ?? 0;
          final costPrice = (bbRow.first['cost_price'] as num?)?.toDouble() ?? 0;

          // Calculate discrepancy
          final qtyChange = actualStock - currentStock;
          // Financial impact: positive if surplus (gain), negative if shrinkage (loss)
          final financialValue = qtyChange * costPrice;

          // Update bahan_baku stock to the physical count
          await txn.update('bahan_baku',
              {'stock': actualStock},
              where: 'id = ?',
              whereArgs: [bbId]);

          // Insert ADJUSTMENT ledger row
          await txn.insert('inventory_ledger', {
            'bahan_baku_id': bbId,
            'transaction_type': 'ADJUSTMENT',
            'qty_change': qtyChange,
            'financial_value': financialValue,
            'notes': 'Stock Opname: ${notes.isEmpty ? "Penyesuaian stok" : notes}',
          });
        });

        return {'success': true};
      }
      // --- TRANSACTIONS: PARTIAL REFUND ---
      final refundMatch = RegExp(r'^/transactions/(\d+)/refund$').firstMatch(path);
      if (refundMatch != null) {
        final txId = int.parse(refundMatch.group(1)!);
        final items = (body?['items'] as List?) ?? [];
        if (items.isEmpty) throw Exception('Tidak ada item untuk di-refund');

        double totalRefundAmount = 0;

        await db.transaction((txn) async {
          // Verify transaction exists and is not fully voided
          final txRows = await txn.query('transactions', where: 'id = ?', whereArgs: [txId]);
          if (txRows.isEmpty) throw Exception('Transaksi tidak ditemukan');
          final txStatus = txRows.first['status']?.toString() ?? 'completed';
          if (txStatus == 'voided') throw Exception('Transaksi sudah di-void seluruhnya');

          for (final item in items) {
            final detailId = (item['detail_id'] as num?)?.toInt();
            final qtyToRefund = (item['qty_to_refund'] as num?)?.toDouble() ?? 0;
            if (detailId == null || qtyToRefund <= 0) continue;

            // Fetch detail row
            final detailRows = await txn.query('transaction_details',
                where: 'id = ? AND transaction_id = ?', whereArgs: [detailId, txId]);
            if (detailRows.isEmpty) throw Exception('Detail item #$detailId tidak ditemukan');
            final detail = detailRows.first;

            final qty = (detail['quantity'] as num?)?.toDouble() ?? 0;
            final alreadyRefunded = (detail['refunded_qty'] as num?)?.toDouble() ?? 0;
            final soldPrice = (detail['sold_price'] as num?)?.toDouble() ?? 0;
            final discountPercent = (detail['discount_percent'] as num?)?.toDouble() ?? 0;
            final productId = (detail['product_id'] as num?)?.toInt() ?? 0;
            final productName = detail['product_name']?.toString() ?? '';

            // Validate
            if (alreadyRefunded + qtyToRefund > qty) {
              throw Exception('Refund melebihi qty asli untuk "$productName" (sisa: ${qty - alreadyRefunded})');
            }

            // Calculate monetary refund (price after discount)
            final priceAfterDiscount = soldPrice * (1 - discountPercent / 100);
            final itemRefund = priceAfterDiscount * qtyToRefund;
            totalRefundAmount += itemRefund;

            // Update refunded_qty
            await txn.rawUpdate(
                'UPDATE transaction_details SET refunded_qty = refunded_qty + ? WHERE id = ?',
                [qtyToRefund, detailId]);

            // ── INVENTORY REVERSAL: Add stock back using same BOM logic as checkout ──
            final productRow = await txn.query('products', columns: ['is_paket'], where: 'id = ?', whereArgs: [productId]);
            final isPaket = productRow.isNotEmpty && (productRow.first['is_paket'] as num?)?.toInt() == 1;

            if (isPaket) {
              // Paket: reverse each child product's recipe
              final paketChildren = await txn.query('paket_items', where: 'paket_id = ?', whereArgs: [productId]);
              for (var child in paketChildren) {
                final childProductId = child['product_id'];
                final childQty = (child['qty'] as num?)?.toInt() ?? 1;
                final childResep = await txn.query('resep', where: 'product_id = ?', whereArgs: [childProductId]);
                for (var r in childResep) {
                  final bbId = r['bahan_baku_id'];
                  final qtyNeeded = (r['qty_needed'] as num).toDouble();
                  final rawReturn = qtyNeeded * childQty * qtyToRefund;
                  final bbRow = await txn.query('bahan_baku', columns: ['unit'], where: 'id = ?', whereArgs: [bbId]);
                  final bbUnit = bbRow.isNotEmpty ? (bbRow.first['unit']?.toString().toLowerCase() ?? '') : '';
                  final returnQty = (bbUnit == 'kg' || bbUnit == 'liter' || bbUnit == 'l') ? rawReturn / 1000 : rawReturn;
                  await txn.rawUpdate('UPDATE bahan_baku SET stock = stock + ? WHERE id = ?', [returnQty, bbId]);
                  try { await txn.insert('inventory_ledger', {
                  'bahan_baku_id': bbId, 'transaction_type': 'REFUND',
                    'qty_change': returnQty, 'financial_value': 0,
                    'notes': 'Refund Item: $productName (Tx #$txId)',
                  }); } catch (_) {}
                }
              }
            } else {
              // Regular: reverse from bahan_baku based on resep
              final resepRows = await txn.query('resep', where: 'product_id = ?', whereArgs: [productId]);
              for (var r in resepRows) {
                final bbId = r['bahan_baku_id'];
                final qtyNeeded = (r['qty_needed'] as num).toDouble();
                final rawReturn = qtyNeeded * qtyToRefund;
                final bbRow = await txn.query('bahan_baku', columns: ['unit'], where: 'id = ?', whereArgs: [bbId]);
                final bbUnit = bbRow.isNotEmpty ? (bbRow.first['unit']?.toString().toLowerCase() ?? '') : '';
                final returnQty = (bbUnit == 'kg' || bbUnit == 'liter' || bbUnit == 'l') ? rawReturn / 1000 : rawReturn;
                await txn.rawUpdate('UPDATE bahan_baku SET stock = stock + ? WHERE id = ?', [returnQty, bbId]);
                try { await txn.insert('inventory_ledger', {
                  'bahan_baku_id': bbId, 'transaction_type': 'REFUND',
                  'qty_change': returnQty, 'financial_value': 0,
                  'notes': 'Refund Item: $productName (Tx #$txId)',
                }); } catch (_) {}
              }
            }
          }

          // Deduct refund from transaction total_amount
          await txn.rawUpdate(
              'UPDATE transactions SET total_amount = MAX(0, total_amount - ?) WHERE id = ?',
              [totalRefundAmount, txId]);

          // Determine new status: check if ALL items fully refunded
          final allDetails = await txn.query('transaction_details', where: 'transaction_id = ?', whereArgs: [txId]);
          bool allFullyRefunded = allDetails.every((d) {
            final q = (d['quantity'] as num?)?.toDouble() ?? 0;
            final r = (d['refunded_qty'] as num?)?.toDouble() ?? 0;
            return r >= q;
          });
          final newStatus = allFullyRefunded ? 'voided' : 'partial_refund';
          await txn.update('transactions', {'status': newStatus}, where: 'id = ?', whereArgs: [txId]);
        });

        return {'success': true, 'refund_amount': totalRefundAmount};
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
        final price = (body?['price'] as num?)?.toDouble();
        final description = body?['description']?.toString();
        
        Map<String, dynamic> pData = {};
        if (name != null) pData['name'] = name;
        if (categoryId != null) pData['category_id'] = categoryId;
        if (barcode != null) pData['barcode'] = barcode.isEmpty ? null : barcode;
        if (price != null) pData['price'] = price;
        if (description != null) pData['description'] = description;
        if (body?['is_paket'] != null) pData['is_paket'] = (body!['is_paket'] as num?)?.toInt() ?? 0;
        
        if (pData.isNotEmpty) {
          await db.update('products', pData, where: 'id = ?', whereArgs: [id]);
        }
        
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

      // --- KATEGORI BAHAN ---
      if (path.startsWith('/kategori-bahan/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Kategori Bahan tidak valid');
        final name = body?['name']?.toString().trim() ?? '';
        if (name.isEmpty) throw Exception('Nama kategori wajib diisi');
        await db.update('kategori_bahan', {'name': name}, where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }

      // --- BAHAN BAKU ---
      if (path.startsWith('/bahan-baku/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Bahan Baku tidak valid');

        Map<String, dynamic> data = {};
        if (body?['name'] != null) data['name'] = body!['name']?.toString() ?? '';
        if (body?['unit'] != null) data['unit'] = body!['unit']?.toString() ?? '';
        if (body?['stock'] != null) data['stock'] = (body!['stock'] as num?)?.toDouble() ?? 0;
        if (body?['cost_price'] != null) data['cost_price'] = (body!['cost_price'] as num?)?.toDouble() ?? 0;
        if (body?['min_stock_alert'] != null) data['min_stock_alert'] = (body!['min_stock_alert'] as num?)?.toDouble() ?? 0;
        if (body?['kategori'] != null) data['kategori'] = body!['kategori']?.toString() ?? 'Lainnya';
        if (body?['kategori_bahan_id'] != null) data['kategori_bahan_id'] = (body!['kategori_bahan_id'] as num?)?.toInt() ?? 0;
        
        if (data.isNotEmpty) {
          await db.update('bahan_baku', data, where: 'id = ?', whereArgs: [id]);
        }
        return {'success': true};
      }

      // --- RESEP: UPDATE QTY ---
      if (path.startsWith('/resep/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Resep tidak valid');
        final qtyNeeded = (body?['qty_needed'] as num?)?.toDouble();
        if (qtyNeeded != null && qtyNeeded > 0) {
          await db.update('resep', {'qty_needed': qtyNeeded}, where: 'id = ?', whereArgs: [id]);
        }
        return {'success': true};
      }
      
      // --- PAKET ITEMS: UPDATE QTY ---
      if (path.startsWith('/paket-items/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Paket Item tidak valid');
        final qty = (body?['qty'] as num?)?.toInt();
        if (qty != null && qty > 0) {
          await db.update('paket_items', {'qty': qty}, where: 'id = ?', whereArgs: [id]);
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
        // Cascade: delete all products in this category and their recipes
        final products = await db.query('products', columns: ['id'], where: 'category_id = ?', whereArgs: [id]);
        for (final p in products) {
          await db.delete('resep', where: 'product_id = ?', whereArgs: [p['id']]);
        }
        await db.delete('products', where: 'category_id = ?', whereArgs: [id]);
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

      // --- BAHAN BAKU ---
      if (path.startsWith('/bahan-baku/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Bahan Baku tidak valid');
        await db.delete('bahan_baku', where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }

      // --- KATEGORI BAHAN ---
      if (path.startsWith('/kategori-bahan/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Kategori Bahan tidak valid');
        // Cascade: delete all bahan_baku in this category
        await db.delete('bahan_baku', where: 'kategori_bahan_id = ?', whereArgs: [id]);
        await db.delete('kategori_bahan', where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }

      // --- RESEP ---
      if (path.startsWith('/resep/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Resep tidak valid');
        await db.delete('resep', where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }

      // --- PAKET ITEMS ---
      if (path.startsWith('/paket-items/')) {
        final id = int.tryParse(path.split('/').last);
        if (id == null) throw Exception('ID Paket Item tidak valid');
        await db.delete('paket_items', where: 'id = ?', whereArgs: [id]);
        return {'success': true};
      }
      
      throw Exception('Endpoint DELETE $path belum diimplementasikan di Offline Router');
    } catch (e) {
      if (e.toString().contains('Exception:')) rethrow;
      throw Exception('Gagal menghapus data lokal: ${e.toString()}');
    }
  }
}
