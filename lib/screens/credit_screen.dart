import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../store.dart';
import '../ui.dart';

class CreditScreen extends StatefulWidget {
  final Store store;
  const CreditScreen({super.key, required this.store});

  @override
  State<CreditScreen> createState() => _CreditScreenState();
}

class _CreditScreenState extends State<CreditScreen> {
  String _query = '';

  Future<void> _addCustomer() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final notes = TextEditingController();
    final debt = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('زبون جديد'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
            const SizedBox(height: 10),
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'الهاتف (لتذكير واتساب)')),
            const SizedBox(height: 10),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'ملاحظات')),
            const SizedBox(height: 10),
            TextField(
                controller: debt,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'دين سابق (اختياري)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await guard(
          context,
          () => widget.store.addCustomer(name.text, phone.text, notes.text,
              parseNum(debt.text) ?? 0, 15000));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomer,
        icon: const Icon(Icons.person_add),
        label: const Text('زبون جديد'),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final q = normalizeArabic(_query);
          final list = widget.store.customers
              .where((c) =>
                  q.isEmpty ||
                  normalizeArabic(c.name).contains(q) ||
                  c.phone.contains(q))
              .toList();
          return Column(children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Text('إجمالي الكريدي عند الزبائن',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${formatDA(widget.store.stats.totalDebt)} د.ج',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'ابحث بالاسم أو الهاتف...',
                  prefixIcon: Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('لا يوجد زبائن'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 90),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final c = list[i];
                        return Card(
                          elevation: 0,
                          child: ListTile(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => CustomerPage(
                                      store: widget.store, customerId: c.id)),
                            ),
                            leading: CircleAvatar(
                                child: Text(c.name.isEmpty ? '?' : c.name[0])),
                            title: Text(c.name,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(c.phone.isEmpty ? 'بدون هاتف' : c.phone),
                            trailing: Text('${formatDA(c.totalDebt)} د.ج',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: c.totalDebt > 0
                                        ? Colors.amber.shade900
                                        : Colors.green.shade700)),
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

class CustomerPage extends StatelessWidget {
  final Store store;
  final int customerId;
  const CustomerPage({super.key, required this.store, required this.customerId});

  Future<void> _txDialog(BuildContext context, Customer c, bool payment) async {
    final amount = TextEditingController(
        text: payment && c.totalDebt > 0 ? fmtQty(c.totalDebt) : '');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(payment ? 'تسديد دفعة — ${c.name}' : 'إضافة دين — ${c.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(labelText: 'المبلغ (د.ج)'),
          ),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final v = parseNum(amount.text) ?? 0;
    await guard(
        context,
        () => payment
            ? store.addPayment(c.id, v, note.text)
            : store.addManualDebt(c.id, v, note.text));
  }

  Future<void> _whatsapp(BuildContext context, Customer c) async {
    final link = debtReminderLink(c.phone, c.name, c.totalDebt,
        storeName: store.storeName);
    if (link == null) {
      snack(context, 'أضف رقم هاتف جزائري صحيح للزبون', error: true);
      return;
    }
    try {
      final ok = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) snack(context, 'تعذر فتح واتساب', error: true);
    } catch (_) {
      if (context.mounted) snack(context, 'تعذر فتح واتساب', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final matches = store.customers.where((c) => c.id == customerId);
        if (matches.isEmpty) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('الحساب غير موجود')));
        }
        final c = matches.first;
        final history = store.creditTxs.where((t) => t.customerId == c.id).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(c.name),
            actions: [
              IconButton(
                tooltip: 'حذف الحساب',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirmDialog(context, 'حذف حساب "${c.name}"؟', okText: 'حذف')) return;
                  if (!context.mounted) return;
                  final nav = Navigator.of(context);
                  if (await guard(context, () => store.deleteCustomer(c.id))) nav.pop();
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('الهاتف: ${c.phone.isEmpty ? 'غير مسجل' : c.phone}'
                  '${c.notes.isEmpty ? '' : '  |  ${c.notes}'}',
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade300, width: 2),
                    borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  const Text('المبلغ المطلوب من الزبون',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${formatDA(c.totalDebt)} د.ج',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                ]),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: c.totalDebt > 0 ? () => _txDialog(context, c, true) : null,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('تسديد دفعة'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _txDialog(context, c, false),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('إضافة دين'),
                ),
                if (c.totalDebt > 0)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600),
                    onPressed: () => _whatsapp(context, c),
                    icon: const Icon(Icons.chat),
                    label: const Text('تذكير عبر واتساب'),
                  ),
              ]),
              const SizedBox(height: 16),
              const Text('سجل الحساب',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              if (history.isEmpty) const Text('لا توجد حركات'),
              for (final t in history) _txTile(t),
            ],
          ),
        );
      },
    );
  }

  Widget _txTile(CreditTx t) {
    final isDebt = t.type == 'debt';
    final color = isDebt ? Colors.amber.shade800 : Colors.green.shade700;
    return Card(
      elevation: 0,
      child: ListTile(
        leading: Icon(isDebt ? Icons.arrow_upward : Icons.arrow_downward, color: color),
        title: Text('${isDebt ? '+' : '−'}${formatDA(t.amount)} د.ج',
            style: TextStyle(fontWeight: FontWeight.w900, color: color)),
        subtitle: Text('${t.note}\n${fmtDateTime(t.createdAt)}'),
        isThreeLine: true,
        trailing: Text('الرصيد\n${formatDA(t.balanceAfter)}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}
