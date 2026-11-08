import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'store.dart';

const kCategories = [
  'حليب ومشتقاته',
  'مواد أساسية',
  'عجائن وحبوب',
  'معلبات وزيوت',
  'مشروبات وعصائر',
  'بسكويت وحلويات',
  'خضر وفواكه',
  'مواد التنظيف',
  'أخرى',
];
const kUnits = ['حبة', 'علبة', 'قارورة', 'كيس', 'كغ'];
const kExpenseCategories = [
  'شراء بضاعة من المورّد',
  'كراء المحل',
  'كهرباء وماء وغاز',
  'أجور العمال',
  'نقل وتوصيل',
  'صيانة وتجهيزات',
  'أخرى',
];

const kGreen = Color(0xFF047857);

/// 12500 -> "12 500"
String formatDA(double v) {
  final r = (v * 100).round() / 100;
  final neg = r < 0;
  final s = (neg ? -r : r).toStringAsFixed(r == r.roundToDouble() ? 0 : 2);
  final parts = s.split('.');
  final buf = StringBuffer();
  final ip = parts[0];
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) buf.write(' ');
    buf.write(ip[i]);
  }
  return '${neg ? '-' : ''}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String fmtQty(double q) {
  if (q == q.roundToDouble()) return q.toStringAsFixed(0);
  return q
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String fmtDateTime(DateTime d) {
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(d.day)}/${t(d.month)}/${d.year} ${t(d.hour)}:${t(d.minute)}';
}

String normalizeArabic(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[أإآا]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .trim();

/// WhatsApp link with a ready debt-reminder message. 0550123456 -> 213550123456
String? debtReminderLink(String phone, String name, double debt) {
  var d = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (d.startsWith('+')) {
    d = d.substring(1);
  } else if (d.startsWith('00')) {
    d = d.substring(2);
  } else if (d.startsWith('0')) {
    d = '213${d.substring(1)}';
  }
  if (!RegExp(r'^213\d{8,9}$').hasMatch(d)) return null;
  final msg = 'السلام عليكم $name،\n'
      'نذكّركم بلطف أن المبلغ المتبقي عليكم في المحل هو ${formatDA(debt)} د.ج.\n'
      'نرجو التسوية في أقرب وقت ممكن. بارك الله فيكم وشكراً.';
  return 'https://wa.me/$d?text=${Uri.encodeComponent(msg)}';
}

void snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
}

/// Runs a store action and shows the error message (if any) as a snackbar.
Future<bool> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on AppError catch (e) {
    if (context.mounted) snack(context, e.message, error: true);
  } catch (_) {
    if (context.mounted) snack(context, 'حدث خطأ غير متوقع', error: true);
  }
  return false;
}

Future<bool> confirmDialog(BuildContext context, String message,
    {String okText = 'تأكيد'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(okText)),
      ],
    ),
  );
  return r ?? false;
}

Future<double?> askNumber(BuildContext context,
    {required String title, String hint = '', double? initial}) {
  final ctrl = TextEditingController(text: initial == null ? '' : fmtQty(initial));
  return showDialog<double>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(c, parseNum(ctrl.text)),
          child: const Text('موافق'),
        ),
      ],
    ),
  );
}

/// Accepts "1,5" and Arabic-Indic digits too.
double? parseNum(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var t = s.trim().replaceAll(',', '.').replaceAll('،', '.');
  for (var i = 0; i < 10; i++) {
    t = t.replaceAll(ar[i], '$i');
  }
  return double.tryParse(t);
}

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) snack(context, 'تم النسخ');
}

Widget kpiCard(String title, String value, IconData icon, Color color,
    {String? sub}) {
  return Card(
    elevation: 0,
    color: color.withAlpha(24),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    maxLines: 2)),
          ]),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$value د.ج',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          ),
          if (sub != null)
            Text(sub, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
        ],
      ),
    ),
  );
}
