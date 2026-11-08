import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'cart.dart';
import 'models.dart';

/// An error with a message that is safe to show to the shop owner.
class AppError implements Exception {
  final String message;
  AppError(this.message);
  @override
  String toString() => message;
}

double _r2(double n) => (n * 100).round() / 100;
String _now() => DateTime.now().toUtc().toIso8601String();

class Store extends ChangeNotifier {
  late final Database db;

  List<Product> products = [];
  List<Customer> customers = [];
  List<Sale> sales = [];
  List<CreditTx> creditTxs = [];
  List<Expense> expenses = [];
  Stats stats = const Stats();

  Future<void> init() async {
    final path = p.join(await getDatabasesPath(), 'mizan_pro.db');
    db = await openDatabase(
      path,
      version: 1,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, v) async {
        for (final sql in _schema) {
          await d.execute(sql);
        }
        await _seed(d);
      },
    );
    await refresh();
  }

  static const _schema = [
    '''CREATE TABLE products (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, brand TEXT NOT NULL DEFAULT '',
      category TEXT NOT NULL, unit TEXT NOT NULL DEFAULT 'حبة',
      is_weighted INTEGER NOT NULL DEFAULT 0,
      cost_price REAL NOT NULL, selling_price REAL NOT NULL,
      stock_quantity REAL NOT NULL, min_stock_alert REAL NOT NULL DEFAULT 10,
      is_popular INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      total_debt REAL NOT NULL DEFAULT 0, credit_limit REAL NOT NULL DEFAULT 15000,
      last_transaction_at TEXT NOT NULL, created_at TEXT NOT NULL)''',
    '''CREATE TABLE sales (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_number TEXT NOT NULL,
      total_amount REAL NOT NULL, total_cost REAL NOT NULL, total_profit REAL NOT NULL,
      payment_method TEXT NOT NULL, paid_amount REAL NOT NULL,
      credit_amount REAL NOT NULL DEFAULT 0,
      customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
      customer_name TEXT, items_count INTEGER NOT NULL,
      note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''',
    '''CREATE TABLE sale_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
      product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
      product_name TEXT NOT NULL, unit TEXT NOT NULL,
      quantity REAL NOT NULL, unit_price REAL NOT NULL, cost_price REAL NOT NULL,
      subtotal REAL NOT NULL, profit REAL NOT NULL)''',
    '''CREATE TABLE credit_transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
      sale_id INTEGER REFERENCES sales(id) ON DELETE SET NULL,
      type TEXT NOT NULL, amount REAL NOT NULL, balance_after REAL NOT NULL,
      note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''',
    '''CREATE TABLE expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category TEXT NOT NULL, amount REAL NOT NULL,
      note TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''',
    'CREATE INDEX sales_created_idx ON sales(created_at)',
    'CREATE INDEX credit_tx_customer_idx ON credit_transactions(customer_id)',
    'CREATE INDEX sale_items_sale_idx ON sale_items(sale_id)',
  ];

  // A few sample products so the app is not empty on first launch.
  // (name, category, unit, cost, price, stock, min alert, popular)
  static const _demo = [
    ('حليب شكارة 1 لتر', 'حليب ومشتقاته', 'كيس', 22.0, 25.0, 90.0, 20.0, true),
    ('خبز', 'مواد أساسية', 'حبة', 8.5, 10.0, 100.0, 30.0, true),
    ('سكر', 'مواد أساسية', 'كغ', 95.0, 105.0, 40.0, 10.0, true),
    ('سميد', 'عجائن وحبوب', 'كغ', 55.0, 65.0, 50.0, 10.0, true),
    ('زيت مائدة 1 لتر', 'معلبات وزيوت', 'قارورة', 170.0, 195.0, 30.0, 8.0, false),
    ('معجون طماطم', 'معلبات وزيوت', 'علبة', 55.0, 70.0, 24.0, 6.0, false),
    ('قهوة 250غ', 'مواد أساسية', 'علبة', 180.0, 220.0, 20.0, 5.0, false),
    ('عصير 1 لتر', 'مشروبات وعصائر', 'قارورة', 90.0, 110.0, 36.0, 10.0, false),
    ('ماء معدني 1.5 لتر', 'مشروبات وعصائر', 'قارورة', 28.0, 35.0, 60.0, 12.0, true),
    ('بسكويت', 'بسكويت وحلويات', 'علبة', 35.0, 45.0, 45.0, 10.0, false),
    ('مسحوق غسيل 1 كغ', 'مواد التنظيف', 'كيس', 230.0, 280.0, 15.0, 4.0, false),
    ('بطاطا', 'خضر وفواكه', 'كغ', 50.0, 70.0, 80.0, 15.0, false),
  ];

  Future<void> _seed(Database d) async {
    for (final x in _demo) {
      await d.insert('products', {
        'name': x.$1,
        'category': x.$2,
        'unit': x.$3,
        'is_weighted': x.$3 == 'كغ' ? 1 : 0,
        'cost_price': x.$4,
        'selling_price': x.$5,
        'stock_quantity': x.$6,
        'min_stock_alert': x.$7,
        'is_popular': x.$8 ? 1 : 0,
      });
    }
  }

  // ---------------------------------------------------------------- loading
  Future<void> refresh() async {
    products = (await db.query('products', orderBy: 'is_popular DESC, id'))
        .map(Product.fromMap)
        .toList();
    customers = (await db.query('customers', orderBy: 'total_debt DESC, id'))
        .map(Customer.fromMap)
        .toList();

    final saleRows = await db.query('sales',
        orderBy: 'created_at DESC, id DESC', limit: 1000);
    final itemRows = await db.rawQuery(
        'SELECT * FROM sale_items WHERE sale_id IN '
        '(SELECT id FROM sales ORDER BY created_at DESC, id DESC LIMIT 1000) '
        'ORDER BY id');
    final bySale = <int, List<SaleItem>>{};
    for (final r in itemRows) {
      final it = SaleItem.fromMap(r);
      (bySale[it.saleId] ??= []).add(it);
    }
    sales = saleRows
        .map((r) => Sale.fromMap(r, bySale[r['id'] as int] ?? const []))
        .toList();

    creditTxs = (await db.query('credit_transactions',
            orderBy: 'created_at DESC, id DESC', limit: 5000))
        .map(CreditTx.fromMap)
        .toList();
    expenses = (await db.query('expenses',
            orderBy: 'created_at DESC, id DESC', limit: 300))
        .map(Expense.fromMap)
        .toList();

    _computeStats();
    notifyListeners();
  }

  DateTime get startOfToday {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void _computeStats() {
    final s0 = startOfToday;
    bool today(DateTime d) => !d.isBefore(s0);
    final ts = sales.where((s) => today(s.createdAt));
    stats = Stats(
      revenue: ts.fold(0.0, (a, s) => a + s.totalAmount),
      grossProfit: ts.fold(0.0, (a, s) => a + s.totalProfit),
      cashFromSales: ts.fold(0.0, (a, s) => a + s.paidAmount),
      newCredit: ts.fold(0.0, (a, s) => a + s.creditAmount),
      invoices: ts.length,
      debtRepayments: creditTxs
          .where((t) => t.type == 'payment' && today(t.createdAt))
          .fold(0.0, (a, t) => a + t.amount),
      expenses: expenses
          .where((e) => today(e.createdAt))
          .fold(0.0, (a, e) => a + e.amount),
      totalDebt: customers.fold(0.0, (a, c) => a + c.totalDebt),
      lowStock: products.where((x) => x.isLow).length,
      outOfStock: products.where((x) => x.isOut).length,
    );
  }

  // ------------------------------------------------------------------ sales
  /// Saves a whole invoice in ONE transaction: nothing is half-written.
  Future<Sale> completeSale({
    required List<CartLine> lines,
    required String method, // cash | credit | split
    double paid = 0,
    int? customerId,
    String newName = '',
    String newPhone = '',
    String note = '',
  }) async {
    if (lines.isEmpty) throw AppError('السلة فارغة، أضف سلعة واحدة على الأقل');

    final saleId = await db.transaction<int>((txn) async {
      double total = 0, cost = 0;
      final items = <Map<String, Object?>>[];
      for (final l in lines) {
        // The cost always comes from the database, never from the screen.
        final rows = await txn
            .query('products', where: 'id = ?', whereArgs: [l.product.id]);
        final c = rows.isEmpty
            ? l.product.costPrice
            : (rows.first['cost_price'] as num).toDouble();
        final qty = math.max(0.05, l.qty);
        final price = math.max(0.0, l.price);
        final sub = _r2(qty * price);
        final ct = _r2(qty * c);
        total += sub;
        cost += ct;
        items.add({
          'product_id': rows.isEmpty ? null : l.product.id,
          'product_name': l.product.name,
          'unit': l.product.unit,
          'quantity': qty,
          'unit_price': price,
          'cost_price': c,
          'subtotal': sub,
          'profit': _r2(sub - ct),
        });
      }
      total = _r2(total);
      cost = _r2(cost);

      double paidAmount = total, creditAmount = 0;
      if (method == 'credit') {
        paidAmount = 0;
        creditAmount = total;
      } else if (method == 'split') {
        paidAmount = math.min(total, math.max(0.0, paid));
        creditAmount = _r2(total - paidAmount);
      }

      int? custId = customerId;
      String custName = 'زبون مباشر (كاش)';
      final now = _now();

      if (creditAmount > 0) {
        if (custId == null && newName.trim().isNotEmpty) {
          custId = await txn.insert('customers', {
            'name': newName.trim(),
            'phone': newPhone.trim(),
            'notes': 'أضيف من شاشة البيع',
            'total_debt': 0,
            'credit_limit': 15000,
            'last_transaction_at': now,
            'created_at': now,
          });
          custName = newName.trim();
        } else if (custId != null) {
          final r = await txn
              .query('customers', where: 'id = ?', whereArgs: [custId]);
          if (r.isEmpty) throw AppError('الزبون غير موجود في دفتر الكريدي');
          custName = r.first['name'] as String;
        } else {
          throw AppError('اختر الزبون أو اكتب اسمه لتسجيل الدين');
        }
      } else if (custId != null) {
        final r = await txn
            .query('customers', where: 'id = ?', whereArgs: [custId]);
        if (r.isNotEmpty) custName = r.first['name'] as String;
      }

      final id = await txn.insert('sales', {
        'invoice_number': 'TMP',
        'total_amount': total,
        'total_cost': cost,
        'total_profit': _r2(total - cost),
        'payment_method': creditAmount == 0 ? 'cash' : method,
        'paid_amount': paidAmount,
        'credit_amount': creditAmount,
        'customer_id': custId,
        'customer_name': custName,
        'items_count': items.length,
        'note': note.trim(),
        'created_at': now,
      });
      final invoice = 'FAC-${id + 1000}';
      await txn.update('sales', {'invoice_number': invoice},
          where: 'id = ?', whereArgs: [id]);

      for (final it in items) {
        await txn.insert('sale_items', {'sale_id': id, ...it});
        if (it['product_id'] != null) {
          await txn.rawUpdate(
              'UPDATE products SET stock_quantity = '
              'MAX(0, ROUND(stock_quantity - ?, 3)) WHERE id = ?',
              [it['quantity'], it['product_id']]);
        }
      }

      if (creditAmount > 0 && custId != null) {
        await txn.rawUpdate(
            'UPDATE customers SET total_debt = ROUND(total_debt + ?, 2), '
            'last_transaction_at = ? WHERE id = ?',
            [creditAmount, now, custId]);
        final bal = (await txn.query('customers',
                columns: ['total_debt'], where: 'id = ?', whereArgs: [custId]))
            .first['total_debt'] as num;
        final summary = items
            .take(4)
            .map((i) => '${i['product_name']} (${i['quantity']} ${i['unit']})')
            .join('، ');
        await txn.insert('credit_transactions', {
          'customer_id': custId,
          'sale_id': id,
          'type': 'debt',
          'amount': creditAmount,
          'balance_after': bal.toDouble(),
          'note': note.trim().isNotEmpty
              ? note.trim()
              : 'فاتورة $invoice: $summary${items.length > 4 ? '...' : ''}',
          'created_at': now,
        });
      }
      return id;
    });

    await refresh();
    return sales.firstWhere((s) => s.id == saleId);
  }

  /// Cancels an invoice: goods go back to stock, debt is taken off the customer.
  Future<void> cancelSale(int id) async {
    await db.transaction((txn) async {
      final rows = await txn.query('sales', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw AppError('الفاتورة غير موجودة');
      final sale = rows.first;
      final items = await txn
          .query('sale_items', where: 'sale_id = ?', whereArgs: [id]);
      for (final it in items) {
        if (it['product_id'] != null) {
          await txn.rawUpdate(
              'UPDATE products SET stock_quantity = '
              'ROUND(stock_quantity + ?, 3) WHERE id = ?',
              [it['quantity'], it['product_id']]);
        }
      }
      final credit = (sale['credit_amount'] as num).toDouble();
      final custId = sale['customer_id'] as int?;
      if (credit > 0 && custId != null) {
        final now = _now();
        await txn.rawUpdate(
            'UPDATE customers SET total_debt = '
            'MAX(0, ROUND(total_debt - ?, 2)), last_transaction_at = ? '
            'WHERE id = ?',
            [credit, now, custId]);
        final c = await txn.query('customers',
            columns: ['total_debt'], where: 'id = ?', whereArgs: [custId]);
        if (c.isNotEmpty) {
          // "reversal" is NOT cash received, so it is not counted in the drawer.
          await txn.insert('credit_transactions', {
            'customer_id': custId,
            'sale_id': null,
            'type': 'reversal',
            'amount': credit,
            'balance_after': (c.first['total_debt'] as num).toDouble(),
            'note': 'إلغاء واسترجاع الفاتورة ${sale['invoice_number']}',
            'created_at': now,
          });
        }
      }
      await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [id]);
      await txn.delete('sales', where: 'id = ?', whereArgs: [id]);
    });
    await refresh();
  }

  // ----------------------------------------------------------------- credit
  Future<void> addPayment(int customerId, double amount, String note) async {
    if (amount <= 0) throw AppError('أدخل مبلغاً صحيحاً أكبر من الصفر');
    await db.transaction((txn) async {
      final r = await txn
          .query('customers', where: 'id = ?', whereArgs: [customerId]);
      if (r.isEmpty) throw AppError('الزبون غير موجود');
      final debt = (r.first['total_debt'] as num).toDouble();
      if (debt <= 0) throw AppError('هذا الزبون ليس عليه أي دين');
      final applied = math.min(amount, debt); // never more than the debt
      final now = _now();
      final newDebt = _r2(math.max(0.0, debt - applied));
      await txn.update(
          'customers', {'total_debt': newDebt, 'last_transaction_at': now},
          where: 'id = ?', whereArgs: [customerId]);
      await txn.insert('credit_transactions', {
        'customer_id': customerId,
        'type': 'payment',
        'amount': applied,
        'balance_after': newDebt,
        'note': note.trim().isEmpty ? 'تسديد دفعة نقدية' : note.trim(),
        'created_at': now,
      });
    });
    await refresh();
  }

  Future<void> addManualDebt(int customerId, double amount, String note) async {
    if (amount <= 0) throw AppError('أدخل مبلغاً صحيحاً أكبر من الصفر');
    await db.transaction((txn) async {
      final r = await txn
          .query('customers', where: 'id = ?', whereArgs: [customerId]);
      if (r.isEmpty) throw AppError('الزبون غير موجود');
      final now = _now();
      final newDebt =
          _r2((r.first['total_debt'] as num).toDouble() + amount);
      await txn.update(
          'customers', {'total_debt': newDebt, 'last_transaction_at': now},
          where: 'id = ?', whereArgs: [customerId]);
      await txn.insert('credit_transactions', {
        'customer_id': customerId,
        'type': 'debt',
        'amount': amount,
        'balance_after': newDebt,
        'note': note.trim().isEmpty ? 'إضافة دين يدوي' : note.trim(),
        'created_at': now,
      });
    });
    await refresh();
  }

  Future<void> addCustomer(String name, String phone, String notes,
      double initialDebt, double creditLimit) async {
    if (name.trim().isEmpty) throw AppError('اسم الزبون مطلوب');
    await db.transaction((txn) async {
      final now = _now();
      final debt = math.max(0.0, initialDebt);
      final id = await txn.insert('customers', {
        'name': name.trim(),
        'phone': phone.trim(),
        'notes': notes.trim(),
        'total_debt': debt,
        'credit_limit': math.max(1000.0, creditLimit),
        'last_transaction_at': now,
        'created_at': now,
      });
      if (debt > 0) {
        await txn.insert('credit_transactions', {
          'customer_id': id,
          'type': 'debt',
          'amount': debt,
          'balance_after': debt,
          'note': 'رصيد افتتاحي عند فتح الحساب',
          'created_at': now,
        });
      }
    });
    await refresh();
  }

  Future<void> deleteCustomer(int id) async {
    final r = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) return;
    final debt = (r.first['total_debt'] as num).toDouble();
    if (debt > 0) {
      throw AppError('لا يمكن حذف الحساب: على الزبون دين. سدّد الدين أولاً.');
    }
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
    await refresh();
  }

  // --------------------------------------------------------------- products
  Future<void> saveProduct(Product x, {int? id}) async {
    if (x.name.trim().isEmpty) throw AppError('اسم السلعة مطلوب');
    if (id == null) {
      await db.insert('products', x.toMap());
    } else {
      await db.update('products', x.toMap(), where: 'id = ?', whereArgs: [id]);
    }
    await refresh();
  }

  Future<void> restock(int id, double delta) async {
    await db.rawUpdate(
        'UPDATE products SET stock_quantity = '
        'MAX(0, ROUND(stock_quantity + ?, 3)) WHERE id = ?',
        [delta, id]);
    await refresh();
  }

  Future<void> deleteProduct(int id) async {
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
    await refresh();
  }

  // --------------------------------------------------------------- expenses
  Future<void> addExpense(String category, double amount, String note) async {
    if (amount <= 0) throw AppError('أدخل مبلغ المصروف');
    await db.insert('expenses', {
      'category': category,
      'amount': _r2(amount),
      'note': note.trim(),
      'created_at': _now(),
    });
    await refresh();
  }

  Future<void> deleteExpense(int id) async {
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    await refresh();
  }
}
