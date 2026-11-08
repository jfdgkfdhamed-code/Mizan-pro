import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'cart.dart';
import 'screens/accounting_screen.dart';
import 'screens/credit_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/pos_screen.dart';
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
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final st = store.stats;
        return Scaffold(
          appBar: AppBar(
            title: const Text('الميزان برو',
                style: TextStyle(fontWeight: FontWeight.w900)),
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
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              PosScreen(store: store, cart: _cart),
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
