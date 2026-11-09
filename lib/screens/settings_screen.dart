import 'package:flutter/material.dart';
import '../store.dart';
import '../ui.dart';

class SettingsScreen extends StatefulWidget {
  final Store store;
  const SettingsScreen({super.key, required this.store});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _name = TextEditingController(text: widget.store.storeName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final ok = await guard(
        context, () => widget.store.setSetting('store_name', _name.text.trim()));
    if (ok && mounted) snack(context, 'تم حفظ اسم المحل');
  }

  Future<void> _reset() async {
    final first = await confirmDialog(
        context,
        'سيتم حذف كل بيانات هذا الهاتف نهائياً: السلع والمبيعات والزبائن والكريدي والمصاريف.\n\nلا يمكن التراجع. هل تريد المتابعة؟',
        okText: 'متابعة');
    if (!first || !mounted) return;
    final second = await confirmDialog(context, 'تأكيد أخير: حذف كل البيانات؟',
        okText: 'نعم، احذف كل شيء');
    if (!second || !mounted) return;
    final ok = await guard(context, () => widget.store.resetAllData());
    if (ok && mounted) snack(context, 'تم حذف كل البيانات');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text('اسم المحل',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              hintText: 'يظهر أعلى التطبيق وفي رسالة تذكير الكريدي',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(onPressed: _saveName, child: const Text('حفظ الاسم')),
          ),
          const Divider(height: 36),
          const Text('خصوصية البيانات',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text(
            'كل بياناتك (السلع والأسعار والزبائن والمبيعات) محفوظة داخل هذا الهاتف فقط، '
            'ولا تُرسل إلى أي خادم، ولا تنتقل مع ملف التطبيق عند مشاركته مع غيرك. '
            'كل من يثبّت التطبيق يبدأ بمحل فارغ خاص به.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await guard(context, () => widget.store.loadSampleProducts());
              if (ok && context.mounted) snack(context, 'أُضيفت سلع تجريبية');
            },
            icon: const Icon(Icons.science_outlined),
            label: const Text('إضافة سلع تجريبية (للتجربة فقط)'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: _reset,
            icon: const Icon(Icons.delete_forever),
            label: const Text('حذف كل بيانات المحل من هذا الهاتف'),
          ),
        ],
      ),
    );
  }
}
