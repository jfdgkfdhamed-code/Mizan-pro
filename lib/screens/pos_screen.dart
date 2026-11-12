import 'package:flutter/material.dart';
import '../barcode.dart';
import '../cart.dart';
import '../models.dart';
import '../store.dart';
import '../ui.dart';
import 'inventory_screen.dart' show ProductDialog;

/// Shown when someone tries to sell more than what is in stock.
/// Returns true if the user chose to go and fix the stock.
Future<bool> showStockProblem(BuildContext context, Product p, double wanted) async {
  final msg = p.stock <= 0
      ? 'السلعة "${p.name}" نفدت من المخزون (الكمية 0).\nلا يمكن بيعها قبل تحديث المخزون.'
      : 'المتوفر من "${p.name}" هو ${fmtQty(p.stock)} ${p.unit} فقط،\nوالمطلوب ${fmtQty(wanted)} ${p.unit}.\nحدّث المخزون أولاً.';
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 38),
      title: const Text('المخزون غير كافٍ'),
      content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(height: 1.6)),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(c, true),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('الذهاب إلى المخزون'),
        ),
      ],
    ),
  );
  return r ?? false;
}

class PosScreen extends StatefulWidget {
  final Store store;
  final Cart cart;

  /// True while the POS tab is the visible one (USB scanner input is only
  /// listened to there).
  final bool isActive;

  /// Switches to the inventory tab and opens the restock dialog for the product.
  final void Function(Product) onGoToInventory;

  const PosScreen({
    super.key,
    required this.store,
    required this.cart,
    required this.isActive,
    required this.onGoToInventory,
  });

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  String _category = 'الكل';
  String _query = '';
  final TextEditingController _search = TextEditingController();
  late final UsbScannerListener _usb;
  Product? _goInventoryAfterScanner;

  @override
  void initState() {
    super.initState();
    _usb = UsbScannerListener(
      isEnabled: () =>
          mounted &&
          widget.isActive &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      onScan: _onUsbScan,
    );
    _usb.attach();
  }

  @override
  void dispose() {
    _usb.detach();
    _search.dispose();
    super.dispose();
  }

  List<Product> get _filtered {
    final q = normalizeArabic(_query);
    return widget.store.products.where((p) {
      if (_category != 'الكل' && p.category != _category) return false;
      if (q.isEmpty) return true;
      return normalizeArabic('${p.name} ${p.brand}').contains(q) ||
          p.barcode.contains(_query.trim());
    }).toList();
  }

  Product _live(Product p) => widget.store.products
      .firstWhere((x) => x.id == p.id, orElse: () => p);

  /// Adds a product to the cart, but NEVER more than what is in stock.
  Future<ScanFeedback> _addProduct(BuildContext ctx, Product p,
      {required bool inScanner}) async {
    final live = _live(p);
    var qty = 1.0;
    if (live.isWeighted) {
      final w = await askNumber(ctx,
          title: 'الكمية بالكيلوغرام — ${live.name}', hint: 'مثال: 0.5');
      if (w == null || w <= 0) return const ScanFeedback('أُلغيت الإضافة', false);
      qty = w;
    }
    final wanted = widget.cart.qtyOf(live.id) + qty;
    if (wanted > live.stock + 1e-9) {
      if (!ctx.mounted) return const ScanFeedback('لا يكفي المخزون', false);
      final go = await showStockProblem(ctx, live, wanted);
      if (go) {
        if (inScanner) {
          _goInventoryAfterScanner = live;
          return const ScanFeedback('لا يكفي المخزون', false, close: true);
        }
        widget.onGoToInventory(live);
      }
      return const ScanFeedback('لا يكفي المخزون — لم تُضف السلعة', false);
    }
    widget.cart.add(live, qty: qty);
    return ScanFeedback('أُضيفت: ${live.name}', true);
  }

  /// Looks the barcode up and adds the product (or offers to register it).
  Future<ScanFeedback?> _handleBarcode(BuildContext ctx, String code,
      {bool inScanner = false}) async {
    final p = widget.store.productByBarcode(code);
    if (p == null) {
      final create = await confirmDialog(
          ctx, 'الباركود $code غير مسجل في المخزون.\nهل تريد إضافة سلعة بهذا الباركود؟',
          okText: 'إضافة سلعة');
      if (create && ctx.mounted) {
        await showDialog<void>(
          context: ctx,
          builder: (_) => ProductDialog(store: widget.store, initialBarcode: code),
        );
      }
      return const ScanFeedback('باركود غير مسجل', false);
    }
    return _addProduct(ctx, p, inScanner: inScanner);
  }

  Future<void> _onUsbScan(String code) async {
    if (!mounted) return;
    // The scanner also "typed" the digits into the search box: clean it.
    _search.clear();
    setState(() => _query = '');
    final fb = await _handleBarcode(context, code);
    if (fb != null && mounted) snack(context, fb.text, error: !fb.ok);
  }

  Future<void> _submitSearch(String v) async {
    final p = widget.store.productByBarcode(v);
    if (p == null) return;
    _search.clear();
    setState(() => _query = '');
    await _addProduct(context, p, inScanner: false);
  }

  Future<void> _openCameraScanner() async {
    _goInventoryAfterScanner = null;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BarcodeScannerPage(
        title: 'مسح السلع بالكاميرا',
        onCode: (ctx, code) => _handleBarcode(ctx, code, inScanner: true),
        footer: ListenableBuilder(
          listenable: widget.cart,
          builder: (ctx, _) => Container(
            color: Colors.black87,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(children: [
              Expanded(
                child: Text(
                  'السلة: ${widget.cart.count} سلعة — ${formatDA(widget.cart.total)} د.ج',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('تم'),
              ),
            ]),
          ),
        ),
      ),
    ));
    final go = _goInventoryAfterScanner;
    _goInventoryAfterScanner = null;
    if (go != null && mounted) widget.onGoToInventory(go);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final cats = [
          'الكل',
          ...{for (final p in widget.store.products) p.category}
        ];
        final items = _filtered;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    onSubmitted: _submitSearch,
                    decoration: const InputDecoration(
                      hintText: 'ابحث عن سلعة أو امسح الباركود...',
                      prefixIcon: Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'مسح الباركود بالكاميرا',
                  onPressed: _openCameraScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ]),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final c in cats)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('لا توجد سلع مطابقة'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 170,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _ProductTile(
                        product: items[i],
                        onTap: () => _addProduct(context, items[i], inScanner: false),
                      ),
                    ),
            ),
            ListenableBuilder(
              listenable: widget.cart,
              builder: (context, _) {
                if (widget.cart.count == 0) return const SizedBox.shrink();
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => CheckoutSheet(
                            store: widget.store,
                            cart: widget.cart,
                            onGoToInventory: widget.onGoToInventory,
                          ),
                        ),
                        icon: const Icon(Icons.shopping_cart_checkout),
                        label: Text(
                          'السلة (${widget.cart.count}) — ${formatDA(widget.cart.total)} د.ج',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final color = p.isOut
        ? Colors.red
        : p.isLow
            ? Colors.orange.shade800
            : kGreen;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.isOut ? Colors.red.shade200 : Colors.black12),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(p.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Text('${formatDA(p.sellingPrice)} د.ج${p.isWeighted ? ' / كغ' : ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, color: kGreen, fontSize: 14)),
              Text(p.isOut ? 'نفد من المخزون' : 'المخزون: ${fmtQty(p.stock)} ${p.unit}',
                  style: TextStyle(fontSize: 10.5, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- checkout
class CheckoutSheet extends StatefulWidget {
  final Store store;
  final Cart cart;
  final void Function(Product) onGoToInventory;
  const CheckoutSheet({
    super.key,
    required this.store,
    required this.cart,
    required this.onGoToInventory,
  });

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  String _method = 'cash';
  final _splitPaid = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  int? _customerId;
  bool _newCustomer = false;
  bool _busy = false;

  @override
  void dispose() {
    _splitPaid.dispose();
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _creditPart {
    final total = widget.cart.total;
    if (_method == 'cash') return 0;
    if (_method == 'credit') return total;
    final paid = (parseNum(_splitPaid.text) ?? 0).clamp(0, total).toDouble();
    return total - paid;
  }

  Product _live(Product p) => widget.store.products
      .firstWhere((x) => x.id == p.id, orElse: () => p);

  /// Increases a quantity only if the stock allows it; otherwise explains and
  /// offers to go to the inventory page.
  Future<void> _changeQty(CartLine l, double newQty) async {
    if (newQty > l.qty) {
      final live = _live(l.product);
      if (newQty > live.stock + 1e-9) {
        final go = await showStockProblem(context, live, newQty);
        if (go && mounted) {
          Navigator.pop(context);
          widget.onGoToInventory(live);
        }
        return;
      }
    }
    widget.cart.setQty(l, newQty);
  }

  Future<void> _confirm() async {
    // Last safety check: stock may have changed since the item was added.
    for (final l in widget.cart.lines) {
      final live = _live(l.product);
      if (l.qty > live.stock + 1e-9) {
        final go = await showStockProblem(context, live, l.qty);
        if (go && mounted) {
          Navigator.pop(context);
          widget.onGoToInventory(live);
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() => _busy = true);
    Sale? sale;
    final ok = await guard(context, () async {
      sale = await widget.store.completeSale(
        lines: List.of(widget.cart.lines),
        method: _method,
        paid: parseNum(_splitPaid.text) ?? 0,
        customerId: _newCustomer ? null : _customerId,
        newName: _newCustomer ? _name.text : '',
        newPhone: _newCustomer ? _phone.text : '',
        note: _note.text,
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && sale != null) {
      final s = sale!;
      widget.cart.clear();
      final nav = Navigator.of(context);
      nav.pop();
      showDialog<void>(
          context: nav.context, builder: (_) => ReceiptDialog(sale: s));
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = widget.store.customers;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListenableBuilder(
        listenable: widget.cart,
        builder: (context, _) {
          final cart = widget.cart;
          if (cart.count == 0) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('السلة فارغة'),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إغلاق')),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Text('السلة',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: cart.clear,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('تفريغ'),
                  ),
                ]),
                for (final l in cart.lines) _lineRow(l),
                const Divider(height: 24),
                Row(children: [
                  const Text('الإجمالي:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${formatDA(cart.total)} د.ج',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900, color: kGreen)),
                ]),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cash', label: Text('كاش')),
                    ButtonSegment(value: 'credit', label: Text('كريدي')),
                    ButtonSegment(value: 'split', label: Text('جزئي')),
                  ],
                  selected: {_method},
                  onSelectionChanged: (s) => setState(() => _method = s.first),
                ),
                if (_method == 'split') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _splitPaid,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'المبلغ المدفوع الآن (د.ج)'),
                  ),
                ],
                if (_method != 'cash') ...[
                  const SizedBox(height: 10),
                  Text('يُسجَّل في الكريدي: ${formatDA(_creditPart)} د.ج',
                      style: TextStyle(
                          color: Colors.orange.shade900, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (!_newCustomer)
                    DropdownButtonFormField<int>(
                      value: _customerId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'الزبون'),
                      items: [
                        for (final c in customers)
                          DropdownMenuItem(
                              value: c.id,
                              child: Text('${c.name} (دين: ${formatDA(c.totalDebt)})')),
                      ],
                      onChanged: (v) => setState(() => _customerId = v),
                    ),
                  if (_newCustomer) ...[
                    TextField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'اسم الزبون الجديد')),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right,
                        decoration: const InputDecoration(labelText: 'الهاتف (اختياري)')),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => setState(() => _newCustomer = !_newCustomer),
                      child: Text(_newCustomer ? 'اختيار زبون موجود' : '+ زبون جديد'),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                TextField(
                    controller: _note,
                    decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
                const SizedBox(height: 14),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _confirm,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_circle),
                    label: const Text('تأكيد الفاتورة',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _lineRow(CartLine l) {
    final step = l.product.isWeighted ? 0.25 : 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              InkWell(
                onTap: () async {
                  final v = await askNumber(context,
                      title: 'سعر الوحدة (د.ج)', initial: l.price);
                  if (v != null) widget.cart.setPrice(l, v);
                },
                child: Text('${formatDA(l.price)} د.ج  ✎',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            ],
          ),
        ),
        IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => widget.cart.setQty(l, l.qty - step),
            icon: const Icon(Icons.remove_circle_outline)),
        InkWell(
          onTap: () async {
            final v = await askNumber(context,
                title: 'الكمية (${l.product.unit})', initial: l.qty);
            if (v != null) await _changeQty(l, v);
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 40),
            alignment: Alignment.center,
            child: Text(fmtQty(l.qty),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ),
        IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _changeQty(l, l.qty + step),
            icon: const Icon(Icons.add_circle_outline)),
        SizedBox(
          width: 70,
          child: Text(formatDA(l.subtotal),
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}

// --------------------------------------------------------------------- receipt
String receiptText(Sale s) {
  final b = StringBuffer()
    ..writeln('فاتورة ${s.invoiceNumber}')
    ..writeln(fmtDateTime(s.createdAt))
    ..writeln('الزبون: ${s.customerName ?? '-'}')
    ..writeln('------------------');
  for (final i in s.items) {
    b.writeln(i.productName);
    b.writeln(ltr('${fmtQty(i.quantity)} × ${formatDA(i.unitPrice)} = ${formatDA(i.subtotal)}'));
  }
  b
    ..writeln('------------------')
    ..writeln('الإجمالي: ${formatDA(s.totalAmount)} د.ج')
    ..writeln('المدفوع: ${formatDA(s.paidAmount)} د.ج');
  if (s.creditAmount > 0) b.writeln('كريدي: ${formatDA(s.creditAmount)} د.ج');
  return b.toString();
}

class ReceiptDialog extends StatelessWidget {
  final Sale sale;
  const ReceiptDialog({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('تمت الفاتورة ${sale.invoiceNumber} ✔'),
      content: SingleChildScrollView(
        child: Text(receiptText(sale), style: const TextStyle(height: 1.5)),
      ),
      actions: [
        TextButton(
            onPressed: () => copyText(context, receiptText(sale)),
            child: const Text('نسخ الفاتورة')),
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }
}
