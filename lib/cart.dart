import 'package:flutter/foundation.dart';
import 'models.dart';

class CartLine {
  final Product product;
  double qty;
  double price;
  CartLine(this.product, this.qty, this.price);
  double get subtotal => (qty * price * 100).round() / 100;
}

class Cart extends ChangeNotifier {
  final List<CartLine> lines = [];

  double get total => lines.fold(0.0, (a, l) => a + l.subtotal);
  int get count => lines.length;

  /// Quantity of a product already in the cart.
  double qtyOf(int productId) {
    for (final l in lines) {
      if (l.product.id == productId) return l.qty;
    }
    return 0;
  }

  void add(Product p, {double qty = 1}) {
    final i = lines.indexWhere((l) => l.product.id == p.id);
    if (i >= 0) {
      lines[i].qty += qty;
    } else {
      lines.add(CartLine(p, qty, p.sellingPrice));
    }
    notifyListeners();
  }

  void setQty(CartLine l, double q) {
    if (q <= 0) {
      lines.remove(l);
    } else {
      l.qty = q;
    }
    notifyListeners();
  }

  void setPrice(CartLine l, double price) {
    l.price = price < 0 ? 0 : price;
    notifyListeners();
  }

  void remove(CartLine l) {
    lines.remove(l);
    notifyListeners();
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }
}
