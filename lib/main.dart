import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'cart.dart';
import 'screens/accounting_screen.dart';
import 'screens/credit_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/settings_screen.dart';
import 'store.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.init();
  runApp(MizanApp(store: store));
}

class MizanApp extends StatelessWidget {
  final Store store;
  const MizanApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الميزان برو',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kGreen),
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: HomeShell(store: store),
    );
  }
}

class HomeShell extends StatefulWidget {
  final Store store;
  const HomeShell({super.key, required this.store});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final Cart _cart = Cart();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeWelcome());
  }

  /// First launch: ask for the shop name. The app starts empty for everyone.
  Future<void> _maybeWelcome() async {
    final store = widget.store;
    if (store.setupDone || !mounted) return;
    final name = TextEditingController();
    final sample = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('مرحباً بك في الميزان برو'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'بياناتك تبقى في هاتفك فقط. أدخل اسم محلك للبدء (يمكنك تغييره لاحقاً):'),
          const SizedBox(height: 12),
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'اسم المحل')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('تجربة بسلع تجريبية')),
          FilledButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('ابدأ بمحل فارغ')),
        ],
      ),
    );
    await store.setSetting('store_name', name.text.trim());
    await store.setSetting('setup_done', '1');
    if (sample == true) await store.loadSampleProducts();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final st = store.stats;
        return Scaffold(
          appBar: AppBar(
            title: Text(
                store.storeName.isEmpty ? 'الميزان برو' : store.storeName,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            backgroundColor: kGreen,
            foregroundColor: Colors.white,
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('مبيعات اليوم: ${formatDA(st.revenue)} د.ج',
                          style: const TextStyle(fontSize: 11)),
                      Text('الربح الصافي: ${formatDA(st.netProfit)} د.ج',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'الإعدادات',
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SettingsScreen(store: store)),
                ),
              ),
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              PosScreen(
                store: store,
                cart: _cart,
                isActive: _tab == 0,
                // The POS refused to sell something out of stock: open the
                // inventory tab and ask to restock that product.
                onGoToInventory: (p) {
                  setState(() => _tab = 1);
                  store.restockRequest.value = p;
                },
              ),
              InventoryScreen(store: store),
              CreditScreen(store: store),
              AccountingScreen(store: store),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(
                  icon: Icon(Icons.point_of_sale), label: 'البيع'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: st.lowStock > 0,
                  label: Text('${st.lowStock}'),
                  child: const Icon(Icons.inventory_2_outlined),
                ),
                label: 'المخزون',
              ),
              const NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined), label: 'الكريدي'),
              const NavigationDestination(
                  icon: Icon(Icons.bar_chart), label: 'المحاسبة'),
            ],
          ),
        );
      },
    );
  }
}
