/// Category used for supplier purchases (recorded automatically when stock is added).
const kPurchaseCategory = 'شراء بضاعة من المورّد';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class Product {
  final int id;
  final String name, brand, category, unit;
  final bool isWeighted, isPopular;
  final double costPrice, sellingPrice, stock, minAlert;

  const Product({
    this.id = 0,
    required this.name,
    this.brand = '',
    required this.category,
    this.unit = 'حبة',
    this.isWeighted = false,
    this.isPopular = false,
    required this.costPrice,
    required this.sellingPrice,
    required this.stock,
    this.minAlert = 10,
  });

  bool get isLow => stock <= minAlert;
  bool get isOut => stock <= 0;

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: _i(m['id']),
        name: m['name'] as String,
        brand: m['brand'] as String? ?? '',
        category: m['category'] as String,
        unit: m['unit'] as String? ?? 'حبة',
        isWeighted: _i(m['is_weighted']) == 1,
        isPopular: _i(m['is_popular']) == 1,
        costPrice: _d(m['cost_price']),
        sellingPrice: _d(m['selling_price']),
        stock: _d(m['stock_quantity']),
        minAlert: _d(m['min_stock_alert']),
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'brand': brand,
        'category': category,
        'unit': unit,
        'is_weighted': isWeighted ? 1 : 0,
        'is_popular': isPopular ? 1 : 0,
        'cost_price': costPrice,
        'selling_price': sellingPrice,
        'stock_quantity': stock,
        'min_stock_alert': minAlert,
      };
}

class Customer {
  final int id;
  final String name, phone, notes;
  final double totalDebt, creditLimit;

  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.notes,
    required this.totalDebt,
    required this.creditLimit,
  });

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: _i(m['id']),
        name: m['name'] as String,
        phone: m['phone'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
        totalDebt: _d(m['total_debt']),
        creditLimit: _d(m['credit_limit']),
      );
}

class SaleItem {
  final int id;
  final int saleId;
  final String productName, unit;
  final double quantity, unitPrice, subtotal, profit;

  const SaleItem({
    required this.id,
    required this.saleId,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    required this.profit,
  });

  factory SaleItem.fromMap(Map<String, Object?> m) => SaleItem(
        id: _i(m['id']),
        saleId: _i(m['sale_id']),
        productName: m['product_name'] as String,
        unit: m['unit'] as String,
        quantity: _d(m['quantity']),
        unitPrice: _d(m['unit_price']),
        subtotal: _d(m['subtotal']),
        profit: _d(m['profit']),
      );
}

class Sale {
  final int id;
  final String invoiceNumber, paymentMethod, note;
  final String? customerName;
  final int? customerId;
  final double totalAmount, totalProfit, paidAmount, creditAmount;
  final DateTime createdAt;
  final List<SaleItem> items;

  const Sale({
    required this.id,
    required this.invoiceNumber,
    required this.paymentMethod,
    required this.note,
    required this.customerName,
    required this.customerId,
    required this.totalAmount,
    required this.totalProfit,
    required this.paidAmount,
    required this.creditAmount,
    required this.createdAt,
    required this.items,
  });

  factory Sale.fromMap(Map<String, Object?> m, List<SaleItem> items) => Sale(
        id: _i(m['id']),
        invoiceNumber: m['invoice_number'] as String,
        paymentMethod: m['payment_method'] as String,
        note: m['note'] as String? ?? '',
        customerName: m['customer_name'] as String?,
        customerId: m['customer_id'] == null ? null : _i(m['customer_id']),
        totalAmount: _d(m['total_amount']),
        totalProfit: _d(m['total_profit']),
        paidAmount: _d(m['paid_amount']),
        creditAmount: _d(m['credit_amount']),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        items: items,
      );
}

class CreditTx {
  final int id, customerId;
  final String type, note; // debt | payment | reversal
  final double amount, balanceAfter;
  final DateTime createdAt;

  const CreditTx({
    required this.id,
    required this.customerId,
    required this.type,
    required this.note,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
  });

  factory CreditTx.fromMap(Map<String, Object?> m) => CreditTx(
        id: _i(m['id']),
        customerId: _i(m['customer_id']),
        type: m['type'] as String,
        note: m['note'] as String? ?? '',
        amount: _d(m['amount']),
        balanceAfter: _d(m['balance_after']),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

class Expense {
  final int id;
  final String category, note;
  final double amount;
  final DateTime createdAt;

  const Expense({
    required this.id,
    required this.category,
    required this.note,
    required this.amount,
    required this.createdAt,
  });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: _i(m['id']),
        category: m['category'] as String,
        note: m['note'] as String? ?? '',
        amount: _d(m['amount']),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

class Stats {
  final double revenue, grossProfit, expenses, purchases, cashFromSales,
      debtRepayments, newCredit, totalDebt;
  final int invoices, lowStock, outOfStock;

  const Stats({
    this.revenue = 0,
    this.grossProfit = 0,
    this.expenses = 0,
    this.purchases = 0,
    this.cashFromSales = 0,
    this.debtRepayments = 0,
    this.newCredit = 0,
    this.totalDebt = 0,
    this.invoices = 0,
    this.lowStock = 0,
    this.outOfStock = 0,
  });

  /// Running costs (rent, electricity, wages...) = all expenses except purchases.
  double get operatingExpenses => expenses - purchases;

  /// Real net profit = profit on goods sold - running costs.
  /// Purchases are NOT subtracted here: the cost of the goods is already inside
  /// each invoice's profit, so subtracting it again would count it twice.
  double get netProfit => grossProfit - operatingExpenses;

  /// Cash in the drawer = cash sales + debts collected - ALL expenses paid
  /// (purchases included, because that money really left the drawer).
  double get cashInDrawer => cashFromSales + debtRepayments - expenses;
}
