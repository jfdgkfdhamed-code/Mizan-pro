import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../ui.dart';
import 'pos_screen.dart' show receiptText;

class AccountingScreen extends StatefulWidget {
  final Store store;
  const AccountingScreen({super.key, required this.store});

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  String _expCategory = kExpenseCategories.first;
  final _expAmount = TextEditingController();
  final _expNote = TextEditingController();
  String _filter = 'all'; // all | cash | credit

  @override
  void dispose() {
    _expAmount.dispose();
    _expNote.dispose();
    super.dispose();
  }

  Future<void> _addExpense() async {
    final amount = parseNum(_expAmount.text) ?? 0;
    final ok = await guard(
        context, () => widget.store.addExpense(_expCategory, amount, _expNote.text));
    if (ok) {
      _expAmount.clear();
      _expNote.clear();
      if (mounted) FocusScope.of(context).unfocus();
    }
  }

  Future<void> _cancelSale(Sale s) async {
    if (!await confirmDialog(
        context, 'إلغاء الفاتورة ${s.invoiceNumber} وإرجاع السلع للمخزون؟',
        okText: 'إلغاء الفاتورة')) {
      return;
    }
    if (!mounted) return;
    await guard(context, () => widget.store.cancelSale(s.id));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final st = widget.store.stats;
        final s0 = widget.store.startOfToday;
        final todayExpenses = widget.store.expenses
            .where((e) => !e.createdAt.isBefore(s0))
            .toList();

        // Best sellers among the loaded invoices.
        final top = <String, List<double>>{}; // name -> [qty, revenue, profit]
        for (final s in widget.store.sales) {
          for (final i in s.items) {
            final v = top.putIfAbsent(i.productName, () => [0, 0, 0]);
            v[0] += i.quantity;
            v[1] += i.subtotal;
            v[2] += i.profit;
          }
        }
        final topList = top.entries.toList()
          ..sort((a, b) => b.value[1].compareTo(a.value[1]));

        final sales = widget.store.sales.where((s) {
          if (_filter == 'cash') return s.paymentMethod == 'cash';
          if (_filter == 'credit') return s.paymentMethod != 'cash';
          return true;
        }).take(100).toList();

        return ListView(
          padding: const EdgeInsets.all(10),
          children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.6,
              children: [
                kpiCard('مبيعات اليوم', formatDA(st.revenue), Icons.account_balance_wallet,
                    Colors.blueGrey.shade800, sub: '${st.invoices} فاتورة'),
                kpiCard('صافي الربح (بعد المصاريف)', formatDA(st.netProfit),
                    Icons.trending_up, kGreen,
                    sub: 'ربح السلع ${formatDA(st.grossProfit)} − مصاريف ${formatDA(st.expenses)}'),
                kpiCard('السيولة في الصندوق', formatDA(st.cashInDrawer), Icons.payments,
                    Colors.teal.shade700,
                    sub: 'كاش ${formatDA(st.cashFromSales)} + ديون ${formatDA(st.debtRepayments)} − مصاريف'),
                kpiCard('كريدي اليوم', formatDA(st.newCredit), Icons.menu_book,
                    Colors.amber.shade900,
                    sub: 'إجمالي الدفتر ${formatDA(st.totalDebt)}'),
              ],
            ),
            const SizedBox(height: 12),
            _expensesCard(st, todayExpenses),
            const SizedBox(height: 12),
            _section('السلع الأكثر مبيعاً (آخر الفواتير)'),
            if (topList.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('لا توجد مبيعات بعد')),
            for (final e in topList.take(6))
              ListTile(
                dense: true,
                title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('الكمية: ${fmtQty(e.value[0])}  •  الربح: ${formatDA(e.value[2])} د.ج'),
                trailing: Text('${formatDA(e.value[1])} د.ج',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _section('سجل الفواتير')),
              for (final f in const [('all', 'الكل'), ('cash', 'كاش'), ('credit', 'كريدي')])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text(f.$2),
                    selected: _filter == f.$1,
                    onSelected: (_) => setState(() => _filter = f.$1),
                  ),
                ),
            ]),
            if (sales.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('لا توجد فواتير')),
            for (final s in sales)
              Card(
                elevation: 0,
                child: ExpansionTile(
                  title: Text('${s.invoiceNumber} — ${formatDA(s.totalAmount)} د.ج',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      '${fmtDateTime(s.createdAt)} • ${s.customerName ?? ''}'
                      '${s.creditAmount > 0 ? ' • كريدي ${formatDA(s.creditAmount)}' : ''}'),
                  childrenPadding: const EdgeInsets.all(12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(receiptText(s), style: const TextStyle(height: 1.5)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text('الربح: ${formatDA(s.totalProfit)} د.ج',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: kGreen)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => copyText(context, receiptText(s)),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('نسخ'),
                      ),
                      TextButton.icon(
                        onPressed: () => _cancelSale(s),
                        icon: const Icon(Icons.undo, size: 16, color: Colors.red),
                        label: const Text('إلغاء', style: TextStyle(color: Colors.red)),
                      ),
                    ]),
                  ],
                ),
              ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      );

  Widget _expensesCard(Stats st, List<Expense> today) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.receipt_long, color: Colors.redAccent),
            const SizedBox(width: 6),
            const Text('مصاريف المحل',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const Spacer(),
            Text('اليوم: ${formatDA(st.expenses)} د.ج',
                style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _expCategory,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'النوع'),
            items: [
              for (final c in kExpenseCategories) DropdownMenuItem(value: c, child: Text(c))
            ],
            onChanged: (v) => setState(() => _expCategory = v!),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _expAmount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ (د.ج)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _expNote,
                decoration: const InputDecoration(labelText: 'ملاحظة'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: _addExpense,
              icon: const Icon(Icons.add),
              label: const Text('تسجيل مصروف'),
            ),
          ),
          for (final e in today)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e.category, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: e.note.isEmpty ? null : Text(e.note),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('−${formatDA(e.amount)} د.ج',
                    style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red.shade800)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    if (await confirmDialog(context, 'حذف هذا المصروف؟', okText: 'حذف') &&
                        mounted) {
                      await guard(context, () => widget.store.deleteExpense(e.id));
                    }
                  },
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
