import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../ui.dart';

class InventoryScreen extends StatefulWidget {
  final Store store;
  const InventoryScreen({super.key, required this.store});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _query = '';
  bool _onlyLow = false;

  Future<void> _edit([Product? p]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ProductDialog(store: widget.store, product: p),
    );
  }

  Future<void> _restock(Product p) async {
    await showDialog<void>(
      context: context,
      builder: (_) => RestockDialog(store: widget.store, product: p),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('سلعة جديدة'),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final q = normalizeArabic(_query);
          final items = widget.store.products.where((p) {
            if (_onlyLow && !p.isLow) return false;
            return q.isEmpty ||
                normalizeArabic('${p.name} ${p.brand} ${p.category}').contains(q);
          }).toList();
          final stockValue = widget.store.products
              .fold(0.0, (a, p) => a + p.stock * p.costPrice);

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'ابحث في المخزون...',
                  prefixIcon: Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                FilterChip(
                  label: Text('قاربت النفاد (${widget.store.stats.lowStock})'),
                  selected: _onlyLow,
                  onSelected: (v) => setState(() => _onlyLow = v),
                ),
                const Spacer(),
                Text('قيمة المخزون: ${formatDA(stockValue)} د.ج',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'لا توجد سلع بعد.\nاضغط «سلعة جديدة» لإضافة أول سلعة.',
                          textAlign: TextAlign.center,
                          style: TextStyle(height: 1.6),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 90),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final p = items[i];
                        final color = p.isOut
                            ? Colors.red
                            : p.isLow
                                ? Colors.orange.shade800
                                : kGreen;
                        return Card(
                          elevation: 0,
                          child: ListTile(
                            onTap: () => _edit(p),
                            title: Text(p.name,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                '${p.category} • شراء ${formatDA(p.costPrice)} • بيع ${formatDA(p.sellingPrice)} د.ج'),
                            leading: CircleAvatar(
                              backgroundColor: color.withAlpha(30),
                              child: Text(fmtQty(p.stock),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: color)),
                            ),
                            trailing: IconButton(
                              tooltip: 'إضافة كمية',
                              icon: const Icon(Icons.add_box_outlined),
                              onPressed: () => _restock(p),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class ProductDialog extends StatefulWidget {
  final Store store;
  final Product? product;
  const ProductDialog({super.key, required this.store, this.product});

  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _brand = TextEditingController(text: widget.product?.brand ?? '');
  late final _cost = TextEditingController(
      text: widget.product == null ? '' : fmtQty(widget.product!.costPrice));
  late final _price = TextEditingController(
      text: widget.product == null ? '' : fmtQty(widget.product!.sellingPrice));
  late final _stock = TextEditingController(
      text: widget.product == null ? '' : fmtQty(widget.product!.stock));
  late final _min = TextEditingController(
      text: fmtQty(widget.product?.minAlert ?? 10));
  late String _category = widget.product?.category ?? kCategories.first;
  late String _unit = widget.product?.unit ?? kUnits.first;
  late bool _popular = widget.product?.isPopular ?? false;
  bool _recordPurchase = true; // only used for a NEW product

  @override
  void dispose() {
    for (final c in [_name, _brand, _cost, _price, _stock, _min]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _num(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        decoration: InputDecoration(labelText: label),
      );

  Future<void> _save() async {
    final price = parseNum(_price.text) ?? 0;
    final cost = parseNum(_cost.text) ?? (price * 0.82).roundToDouble();
    final p = Product(
      name: _name.text.trim(),
      brand: _brand.text.trim(),
      category: _category,
      unit: _unit,
      isWeighted: _unit == 'كغ',
      isPopular: _popular,
      costPrice: cost < 0 ? 0 : cost,
      sellingPrice: price < 0 ? 0 : price,
      stock: (parseNum(_stock.text) ?? 0).clamp(0, double.infinity).toDouble(),
      minAlert: (parseNum(_min.text) ?? 10).clamp(0, double.infinity).toDouble(),
    );
    final ok = await guard(
        context,
        () => widget.store.saveProduct(p,
            id: widget.product?.id, recordPurchase: _recordPurchase));
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, 'حذف "${widget.product!.name}" نهائياً؟',
        okText: 'حذف')) {
      return;
    }
    if (!mounted) return;
    final ok = await guard(
        context, () => widget.store.deleteProduct(widget.product!.id));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final gap = const SizedBox(height: 10);
    return AlertDialog(
      title: Text(widget.product == null ? 'سلعة جديدة' : 'تعديل السلعة'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم السلعة')),
          gap,
          TextField(
              controller: _brand,
              decoration: const InputDecoration(labelText: 'العلامة (اختياري)')),
          gap,
          DropdownButtonFormField<String>(
            value: _category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الصنف'),
            items: [
              for (final c in {...kCategories, _category})
                DropdownMenuItem(value: c, child: Text(c))
            ],
            onChanged: (v) => setState(() => _category = v!),
          ),
          gap,
          DropdownButtonFormField<String>(
            value: _unit,
            decoration: const InputDecoration(labelText: 'الوحدة (كغ = بالوزن)'),
            items: [
              for (final u in kUnits) DropdownMenuItem(value: u, child: Text(u))
            ],
            onChanged: (v) => setState(() => _unit = v!),
          ),
          gap,
          _num(_cost, 'سعر الشراء (د.ج)'),
          gap,
          _num(_price, 'سعر البيع (د.ج)'),
          gap,
          _num(_stock, 'الكمية في المخزون'),
          gap,
          _num(_min, 'تنبيه عند نزول المخزون إلى'),
          if (widget.product == null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('خصم ثمن الشراء تلقائياً'),
              subtitle: const Text(
                  'يُسجَّل مصروف شراء = الكمية × سعر الشراء، ويُخصم من الصندوق'),
              value: _recordPurchase,
              onChanged: (v) => setState(() => _recordPurchase = v),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('سلعة شائعة (تظهر أولاً)'),
            value: _popular,
            onChanged: (v) => setState(() => _popular = v),
          ),
        ]),
      ),
      actions: [
        if (widget.product != null)
          TextButton(
              onPressed: _delete,
              child: const Text('حذف', style: TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}


/// Adds stock and (optionally) records the supplier purchase as an expense
/// automatically: quantity x unit cost.
class RestockDialog extends StatefulWidget {
  final Store store;
  final Product product;
  const RestockDialog({super.key, required this.store, required this.product});

  @override
  State<RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<RestockDialog> {
  final _qty = TextEditingController();
  late final _cost =
      TextEditingController(text: fmtQty(widget.product.costPrice));
  bool _record = true;

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  double get _q => parseNum(_qty.text) ?? 0;
  double get _c => parseNum(_cost.text) ?? widget.product.costPrice;

  Future<void> _save() async {
    if (_q == 0) {
      snack(context, 'أدخل الكمية', error: true);
      return;
    }
    final ok = await guard(
        context,
        () => widget.store
            .restock(widget.product.id, _q, unitCost: _c, recordExpense: _record));
    if (ok && mounted) {
      Navigator.pop(context);
      if (_record && _q > 0 && _c > 0) {
        snack(context,
            'تمت الإضافة وخُصم ${formatDA(_q * _c)} د.ج من الصندوق كمشتريات');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final total = _q > 0 ? _q * _c : 0.0;
    return AlertDialog(
      title: Text('إضافة للمخزون — ${p.name}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _qty,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
            decoration: InputDecoration(labelText: 'الكمية المضافة (${p.unit})'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cost,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
                labelText: 'سعر شراء ال${p.unit} من المورّد (د.ج)'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('خصم ثمن الشراء تلقائياً'),
            subtitle: Text(_record && total > 0
                ? 'سيُخصم ${formatDA(total)} د.ج من الصندوق'
                : 'تسجيل مصروف شراء من المورّد'),
            value: _record,
            onChanged: (v) => setState(() => _record = v),
          ),
          if (_c != p.costPrice)
            Text('سيتحدّث سعر الشراء المسجّل من ${formatDA(p.costPrice)} إلى ${formatDA(_c)} د.ج',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _save, child: const Text('إضافة')),
      ],
    );
  }
}
