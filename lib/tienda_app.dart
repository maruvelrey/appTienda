import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:aws_rekognition_api/rekognition-2016-06-27.dart' as rekognition;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'camara_stub.dart' if (dart.library.js_interop) 'camara_web.dart';
import 'firebase_backend.dart';

const _ink = Color(0xFF292523);
const _muted = Color(0xFF817772);
const _paper = Color(0xFFFAF8F5);
const _accent = Color(0xFF9B6251);
const _awsRegion =
    String.fromEnvironment('AWS_REGION', defaultValue: 'us-east-1');
const _awsAccessKey = String.fromEnvironment('AWS_ACCESS_KEY');
const _awsSecretKey = String.fromEnvironment('AWS_SECRET_KEY');
bool get _awsConfigured => _awsAccessKey.isNotEmpty && _awsSecretKey.isNotEmpty;

final _rekognition = rekognition.Rekognition(
  region: _awsRegion,
  credentials: rekognition.AwsClientCredentials(
    accessKey: _awsAccessKey,
    secretKey: _awsSecretKey,
  ),
);

class Product {
  Product({
    required this.name,
    required this.category,
    required this.sku,
    required this.price,
    required this.stock,
    required this.image,
    this.color = 'Arena',
    this.photo,
    this.sizes = const [],
    this.id,
  });

  String name;
  String category;
  String sku;
  double price;
  int stock;
  String image;
  String color;
  Uint8List? photo;
  final List<String> sizes;
  String? id;
}

class Sale {
  Sale({
    required this.code,
    required this.product,
    required this.quantity,
    required this.payment,
    required this.date,
    required this.customer,
    required this.total,
  });
  final String code;
  final String product;
  final int quantity;
  final String payment;
  final DateTime date;
  final String customer;
  final double total;
}

class StoreOrder {
  StoreOrder({
    this.id,
    required this.code,
    required this.customer,
    required this.status,
    required this.total,
  });
  final String? id;
  final String code;
  final String customer;
  String status;
  final double total;
}

class StoreEvent {
  StoreEvent(this.message, this.date);
  final String message;
  final DateTime date;
}

class _CheckoutRequest {
  const _CheckoutRequest(this.customer, this.payment);
  final String customer;
  final String payment;
}

String _money(num value) => 'Q${value.toStringAsFixed(2)}';

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[áàä]'), 'a')
    .replaceAll(RegExp(r'[éèë]'), 'e')
    .replaceAll(RegExp(r'[íìï]'), 'i')
    .replaceAll(RegExp(r'[óòö]'), 'o')
    .replaceAll(RegExp(r'[úùü]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'[^a-z0-9#-]+'), ' ')
    .trim();

final _seedProducts = <Product>[
  Product(
    name: 'Blazer de lino',
    category: 'Ropa',
    sku: 'ROP-1042',
    price: 1290,
    stock: 12,
    color: 'Marfil',
    image:
        'https://images.unsplash.com/photo-1591047139829-d91aecb6caea?w=700&q=85',
  ),
  Product(
    name: 'Bolso Siena',
    category: 'Accesorios',
    sku: 'ACC-2081',
    price: 890,
    stock: 3,
    color: 'Miel',
    image:
        'https://images.unsplash.com/photo-1584917865442-de89df76afd3?w=700&q=85',
  ),
  Product(
    name: 'Vestido Aurora',
    category: 'Ropa',
    sku: 'ROP-1058',
    price: 1150,
    stock: 8,
    color: 'Rosa',
    image:
        'https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=700&q=85',
  ),
  Product(
    name: 'Tenis Court',
    category: 'Zapatos',
    sku: 'ZAP-3024',
    price: 1490,
    stock: 0,
    color: 'Blanco',
    image:
        'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=700&q=85',
  ),
  Product(
    name: 'Suéter Nube',
    category: 'Ropa',
    sku: 'ROP-1093',
    price: 980,
    stock: 17,
    color: 'Avellana',
    image:
        'https://images.unsplash.com/photo-1576566588028-4147f3842f27?w=700&q=85',
  ),
  Product(
    name: 'Lentes Sol',
    category: 'Accesorios',
    sku: 'ACC-2160',
    price: 650,
    stock: 6,
    color: 'Carey',
    image:
        'https://images.unsplash.com/photo-1511499767150-a48a237f0083?w=700&q=85',
  ),
];

enum _Section { dashboard, inventory, sales, orders, reports }

const _sections = [
  (_Section.dashboard, 'Resumen', Icons.grid_view_rounded),
  (_Section.inventory, 'Inventario', Icons.checkroom_rounded),
  (_Section.sales, 'Ventas', Icons.point_of_sale_rounded),
  (_Section.orders, 'Pedidos', Icons.local_shipping_outlined),
  (_Section.reports, 'Reportes', Icons.query_stats_rounded),
];

class TiendaApp extends StatefulWidget {
  const TiendaApp({super.key, this.previewStorefront = false});

  final bool previewStorefront;

  @override
  State<TiendaApp> createState() => _TiendaAppState();
}

class _TiendaAppState extends State<TiendaApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _products = List<Product>.of(_seedProducts);
  final _sales = <Sale>[];
  final _orders = <StoreOrder>[];
  final _events = <StoreEvent>[];
  _Section _section = _Section.dashboard;
  bool _isAdmin = false;
  final _cart = <Product>[];
  int _orderSequence = 0;
  int _saleSequence = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _productsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _ordersSubscription;
  bool _cloudConnected = false;
  bool _cloudProductsAvailable = false;
  bool _cloudAdmin = false;
  bool _seededCloudProducts = false;
  bool _receivedInitialOrders = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && FirebaseBackend.available) {
      _listenForCloudProducts();
    }
  }

  @override
  void dispose() {
    _productsSubscription?.cancel();
    _ordersSubscription?.cancel();
    super.dispose();
  }

  Map<String, Object?> _productData(Product product) => {
        'name': product.name,
        'category': product.category,
        'sku': product.sku,
        'price': product.price,
        'stock': product.stock,
        'image': product.image,
        if (product.photo != null && product.photo!.length <= 500 * 1024)
          'photoBase64': base64Encode(product.photo!),
        'color': product.color,
        'sizes': product.sizes,
      };

  Product _productFromData(Map<String, dynamic> data) => Product(
        id: data['id'] as String,
        name: data['name'] as String? ?? 'Producto',
        category: data['category'] as String? ?? 'Otros',
        sku: data['sku'] as String? ?? data['id'] as String,
        price: (data['price'] as num? ?? 0).toDouble(),
        stock: (data['stock'] as num? ?? 0).toInt(),
        image: data['image'] as String? ?? '',
        photo: data['photoBase64'] is String
            ? base64Decode(data['photoBase64'] as String)
            : null,
        color: data['color'] as String? ?? 'Sin especificar',
        sizes: (data['sizes'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
      );

  void _listenForCloudProducts() {
    _productsSubscription?.cancel();
    _productsSubscription = FirebaseBackend.watchProducts().listen(
      (records) {
        if (!mounted) return;
        if (records.isNotEmpty) {
          setState(() {
            _products
              ..clear()
              ..addAll(records.map(_productFromData));
            _cloudConnected = true;
            _cloudProductsAvailable = true;
          });
        } else {
          setState(() {
            _cloudConnected = true;
            _cloudProductsAvailable = false;
          });
          if (_cloudAdmin && !_seededCloudProducts) {
            _seededCloudProducts = true;
            _seedInitialProducts();
          }
        }
      },
      onError: (Object error) {
        if (mounted) _notify('Error al sincronizar productos: $error');
      },
    );
  }

  Future<void> _seedInitialProducts() async {
    try {
      for (final product in _products) {
        product.id ??= Uri.encodeComponent(product.sku);
        await FirebaseBackend.saveProduct(product.id!, _productData(product));
      }
    } catch (error) {
      if (mounted) _notify('No se pudo publicar el inventario inicial: $error');
    }
  }

  void _listenForCloudOrders() {
    _ordersSubscription?.cancel();
    _ordersSubscription = FirebaseBackend.watchOrders().listen(
      (records) {
        if (!mounted) return;
        final nextOrders = <StoreOrder>[];
        final nextSales = <Sale>[];
        for (final record in records) {
          final code = record['code'] as String? ?? '#SR-${record['id']}';
          final created = record['createdAt'];
          final date = created is DateTime
              ? created
              : created?.toDate() as DateTime? ?? DateTime.now();
          nextOrders.add(StoreOrder(
            id: record['id'] as String,
            code: code,
            customer: record['customer'] as String? ?? 'Cliente',
            status: record['status'] as String? ?? 'Pedido recibido',
            total: (record['total'] as num? ?? 0).toDouble(),
          ));
          final items = record['items'] as List<dynamic>? ?? const [];
          for (final entry in items.whereType<Map<String, dynamic>>()) {
            nextSales.add(Sale(
              code: 'SRV-$code-${entry['productId']}',
              product: entry['name'] as String? ?? 'Producto',
              quantity: (entry['quantity'] as num? ?? 1).toInt(),
              payment: record['payment'] as String? ?? 'No especificado',
              date: date,
              customer: record['customer'] as String? ?? 'Cliente',
              total: (entry['price'] as num? ?? 0).toDouble() *
                  (entry['quantity'] as num? ?? 1).toInt(),
            ));
          }
        }
        final oldCodes = _orders.map((order) => order.code).toSet();
        final arrived = _receivedInitialOrders
            ? nextOrders.where((order) => !oldCodes.contains(order.code))
            : <StoreOrder>[];
        _receivedInitialOrders = true;
        setState(() {
          _orders
            ..clear()
            ..addAll(nextOrders);
          _sales
            ..clear()
            ..addAll(nextSales);
          _cloudConnected = true;
        });
        for (final order in arrived) {
          _events.insert(
            0,
            StoreEvent('Nueva compra ${order.code} · ${_money(order.total)}',
                DateTime.now()),
          );
          _notify('Nueva compra: ${order.code} · ${_money(order.total)}');
        }
      },
      onError: (Object error) {
        if (mounted) _notify('Error al recibir compras: $error');
      },
    );
  }

  Future<void> _signInGoogleAdmin() async {
    try {
      final user = await FirebaseBackend.signInAdminWithGoogle();
      if (!mounted || user == null) return;
      setState(() {
        _isAdmin = true;
        _cloudAdmin = true;
        _section = _Section.dashboard;
      });
      _receivedInitialOrders = false;
      _listenForCloudProducts();
      _listenForCloudOrders();
      _notify('Sesión de administradora conectada. Sincronización activa.');
    } catch (error) {
      if (mounted) _notify('$error');
    }
  }

  String _category = 'Todo';
  String _shopQuery = '';

  void _notify(String message) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signOutAdmin() async {
    if (_cloudAdmin) {
      await _productsSubscription?.cancel();
      await _ordersSubscription?.cancel();
      await FirebaseBackend.signOut();
    }
    if (mounted) {
      setState(() {
        _isAdmin = false;
        _cloudAdmin = false;
      });
    }
  }

  void _addEvent(String message) {
    setState(() => _events.insert(0, StoreEvent(message, DateTime.now())));
    _notify(message);
  }

  Future<void> _addProduct() async {
    final product = await showDialog<Product>(
      context: _navigatorKey.currentContext!,
      builder: (context) => _ProductDialog(
        onCapture: _captureProductPhoto,
        onRecognize: _recognizeProduct,
        onScanBarcode: _scanBarcode,
      ),
    );
    if (product != null && mounted) {
      product.id ??= Uri.encodeComponent(product.sku);
      if (_cloudAdmin) {
        await FirebaseBackend.saveProduct(product.id!, _productData(product));
      }
      setState(() => _products.insert(0, product));
      _addEvent('Se agregó ${product.name} al inventario.');
    }
  }

  Future<void> _deleteProduct(Product product) async {
    if (_cloudAdmin) {
      await FirebaseBackend.deleteProduct(product.id ?? product.sku);
    }
    if (!mounted) return;
    setState(() => _products.remove(product));
    _addEvent('Se eliminó ${product.name} del inventario.');
  }

  Future<void> _updateOrderStatus(StoreOrder order, String status) async {
    if (_cloudAdmin && order.id != null) {
      try {
        await FirebaseBackend.updateOrderStatus(order.id!, status);
      } catch (error) {
        _notify('No se pudo actualizar el pedido: $error');
        return;
      }
    }
    if (!mounted) return;
    setState(() => order.status = status);
    _addEvent('Pedido ${order.code}: $status.');
  }

  Future<String?> _scanBarcode() async {
    return showDialog<String>(
      context: _navigatorKey.currentContext!,
      builder: (_) => const _BarcodeScannerDialog(),
    );
  }

  Future<Uint8List?> _captureProductPhoto(ImageSource source) async {
    try {
      if (source == ImageSource.camera && kIsWeb) {
        return await Navigator.of(_navigatorKey.currentContext!)
            .push<Uint8List>(
          MaterialPageRoute(builder: (_) => const PantallaCamara()),
        );
      }
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1400,
        imageQuality: 85,
      );
      return await file?.readAsBytes();
    } catch (error) {
      if (mounted) _notify('No se pudo abrir la cámara o galería: $error');
      return null;
    }
  }

  Future<List<String>> _recognizeProduct(Uint8List bytes) async {
    if (!_awsConfigured) {
      throw StateError(
        'Configura credenciales AWS temporales para activar la clasificación.',
      );
    }
    final result = await _rekognition.detectLabels(
      image: rekognition.Image(bytes: bytes),
      maxLabels: 12,
      minConfidence: 55,
    );
    return (result.labels ?? [])
        .where((label) => label.name != null)
        .map((label) => label.name!)
        .toList();
  }

  Future<void> _completePurchase(
    List<Product> products,
    String customer,
    String payment,
  ) async {
    final syncPurchase = FirebaseBackend.available && _cloudProductsAvailable;
    if (FirebaseBackend.available && !syncPurchase) {
      throw StateError(
        'El inventario compartido aún está vacío. '
        'Inicia la app administradora con Google para publicar los productos.',
      );
    }
    final orderCode = syncPurchase
        ? await FirebaseBackend.createOrder(
            products: products
                .map((product) => <String, Object?>{
                      'id': product.id ?? product.sku,
                      'price': product.price,
                      'name': product.name,
                      'sku': product.sku,
                    })
                .toList(),
            customer: customer,
            payment: payment,
          )
        : '#SR-${DateTime.now().millisecondsSinceEpoch}-${++_orderSequence}';
    final sales = <Sale>[];
    var total = 0.0;
    for (final product in products) {
      if (product.stock < 1) continue;
      product.stock--;
      total += product.price;
      sales.add(Sale(
        code: 'SRV-${DateTime.now().millisecondsSinceEpoch}-${++_saleSequence}',
        product: product.name,
        quantity: 1,
        payment: payment,
        date: DateTime.now(),
        customer: customer,
        total: product.price,
      ));
    }
    if (sales.isEmpty) {
      _notify('Los productos de la bolsa ya no están disponibles.');
      return;
    }
    setState(() {
      _sales.insertAll(0, sales);
      _orders.insert(
          0,
          StoreOrder(
            id: syncPurchase ? orderCode.substring(4) : null,
            code: orderCode,
            customer: customer,
            status: 'Pedido recibido',
            total: total,
          ));
      _cart.clear();
      _events.insert(
          0,
          StoreEvent(
              'Nueva compra $orderCode · ${_money(total)}', DateTime.now()));
    });
    _notify('Compra confirmada. Código: $orderCode');
  }

  @override
  Widget build(BuildContext context) {
    final showStorefront = kIsWeb || widget.previewStorefront;
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'SevenRoses',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: _paper,
        fontFamily: 'Arial',
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: !showStorefront && _isAdmin
          ? _AdminShell(
              section: _section,
              products: _products,
              sales: _sales,
              orders: _orders,
              events: _events,
              cloudConnected: _cloudConnected,
              onSection: (value) => setState(() => _section = value),
              onProductsChanged: () => setState(() {}),
              onAddProduct: _addProduct,
              onDeleteProduct: _deleteProduct,
              onUpdateOrder: _updateOrderStatus,
              onExit: _signOutAdmin,
            )
          : !showStorefront
              ? _AdminLoginScreen(
                  onLogin: () => setState(() {
                    _isAdmin = true;
                    _section = _Section.dashboard;
                  }),
                  onGoogleLogin: _signInGoogleAdmin,
                  googleAvailable: FirebaseBackend.available,
                )
              : _Storefront(
                  products: _products,
                  cloudConnected: _cloudConnected,
                  cloudProductsAvailable: _cloudProductsAvailable,
                  orders: _orders,
                  category: _category,
                  query: _shopQuery,
                  cart: _cart,
                  onCategory: (value) => setState(() => _category = value),
                  onQuery: (value) => setState(() => _shopQuery = value),
                  onAddToCart: (product) {
                    setState(() => _cart.add(product));
                    _notify('${product.name} se agregó a tu bolsa.');
                  },
                  onCheckout: _completePurchase,
                ),
    );
  }
}

class _AdminLoginScreen extends StatefulWidget {
  const _AdminLoginScreen({
    required this.onLogin,
    required this.onGoogleLogin,
    required this.googleAvailable,
  });
  final VoidCallback onLogin;
  final Future<void> Function() onGoogleLogin;
  final bool googleAvailable;

  @override
  State<_AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<_AdminLoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _login() {
    if (_phone.text.trim() == '+50255550123' &&
        _password.text == 'SevenRoses2026!') {
      widget.onLogin();
      return;
    }
    setState(() => _error = 'Número o contraseña incorrectos.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.local_florist_rounded,
                        color: _accent, size: 38),
                    const SizedBox(height: 12),
                    const Text('SevenRoses',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 24,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Acceso para administradoras',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        hintText: '+502...',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _login,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Iniciar sesión'),
                      ),
                    ),
                    if (widget.googleAvailable) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: widget.onGoogleLogin,
                        icon: const Icon(Icons.login),
                        label: const Text('Continuar con Google'),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'Usuario de prueba sin AWS: +50255550123\\nContraseña: SevenRoses2026!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Cuenta local de demostración. No usar con información real.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Storefront extends StatelessWidget {
  const _Storefront({
    required this.products,
    required this.cloudConnected,
    required this.cloudProductsAvailable,
    required this.orders,
    required this.category,
    required this.query,
    required this.cart,
    required this.onCategory,
    required this.onQuery,
    required this.onAddToCart,
    required this.onCheckout,
  });

  final List<Product> products;
  final bool cloudConnected;
  final bool cloudProductsAvailable;
  final List<StoreOrder> orders;
  final String category;
  final String query;
  final List<Product> cart;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onQuery;
  final ValueChanged<Product> onAddToCart;
  final Future<void> Function(List<Product>, String, String) onCheckout;

  Future<void> _openCheckout(BuildContext context) async {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu bolsa está vacía.')),
      );
      return;
    }
    final request = await showDialog<_CheckoutRequest>(
      context: context,
      builder: (_) => _CheckoutDialog(cart: cart),
    );
    if (request != null) {
      try {
        await onCheckout(
            List<Product>.of(cart), request.customer, request.payment);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo completar la compra: $error')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final categories = ['Todo', 'Ropa', 'Zapatos', 'Accesorios', 'Cosméticos'];
    final visible = products.where((product) {
      final matchesCategory =
          category == 'Todo' || product.category == category;
      final matchesQuery =
          product.name.toLowerCase().contains(query.toLowerCase()) ||
              product.category.toLowerCase().contains(query.toLowerCase());
      return matchesCategory && matchesQuery && product.stock > 0;
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 18 : 48,
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Row(
                            children: [
                              const Icon(Icons.flare_rounded,
                                  color: _accent, size: 28),
                              const SizedBox(width: 8),
                              const Text(
                                'SEVENROSES',
                                style: TextStyle(
                                  fontSize: 21,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w700,
                                  color: _ink,
                                ),
                              ),
                              if (!isMobile) ...[
                                const Spacer(),
                                const Text('Novedades'),
                                const SizedBox(width: 28),
                                const Text('Ropa'),
                                const SizedBox(width: 28),
                                const Text('Accesorios'),
                                const SizedBox(width: 28),
                                const Text('Nuestra historia'),
                              ],
                              const Spacer(),
                              IconButton(
                                tooltip: 'Bolsa de compra',
                                onPressed: () => _openCheckout(context),
                                icon: Badge(
                                  isLabelVisible: cart.isNotEmpty,
                                  label: Text('${cart.length}'),
                                  child:
                                      const Icon(Icons.shopping_bag_outlined),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (FirebaseBackend.configured)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Icon(
                                  cloudConnected
                                      ? Icons.cloud_done_outlined
                                      : Icons.cloud_sync_outlined,
                                  size: 15,
                                  color: cloudConnected
                                      ? const Color(0xFF628C73)
                                      : _muted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  cloudConnected
                                      ? (cloudProductsAvailable
                                          ? 'Inventario sincronizado'
                                          : 'Firebase conectado · inventario vacío')
                                      : 'Conectando inventario…',
                                  style: const TextStyle(
                                      fontSize: 11, color: _muted),
                                ),
                              ],
                            ),
                          ),
                        Container(
                          height: isMobile ? 310 : 390,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: const Color(0xFFE9DED2),
                            image: const DecorationImage(
                              image: NetworkImage(
                                'https://images.unsplash.com/photo-1483985988355-763728e1935b?w=1600&q=88',
                              ),
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                            ),
                          ),
                          child: Container(
                            padding: EdgeInsets.all(isMobile ? 20 : 32),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: const LinearGradient(
                                colors: [Color(0xAD211A16), Color(0x001F1B19)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: isMobile ? 280 : 450,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'COLECCIÓN PRIMAVERA · 2026',
                                      style: TextStyle(
                                        color: Colors.white,
                                        letterSpacing: 2,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 8 : 10),
                                    Text(
                                      'Vestir bonito,\nsentirte tú.',
                                      style: TextStyle(
                                        height: 1.08,
                                        color: Colors.white,
                                        fontSize: isMobile ? 30 : 46,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: isMobile ? 10 : 12),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: _ink,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 22,
                                          vertical: 10,
                                        ),
                                      ),
                                      onPressed: () => onCategory('Todo'),
                                      child: const Text('Descubrir colección'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 34),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Piezas para ti',
                                style: TextStyle(
                                  fontSize: isMobile ? 25 : 31,
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
                              ),
                            ),
                            if (!isMobile)
                              SizedBox(
                                width: 260,
                                child: TextField(
                                  onChanged: onQuery,
                                  decoration: const InputDecoration(
                                    hintText: 'Buscar una pieza',
                                    prefixIcon: Icon(Icons.search),
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(28)),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (isMobile)
                          TextField(
                            onChanged: onQuery,
                            decoration: const InputDecoration(
                              hintText: 'Buscar una pieza',
                              prefixIcon: Icon(Icons.search),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(28)),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            children: categories.map((item) {
                              return ChoiceChip(
                                label: Text(item),
                                selected: category == item,
                                onSelected: (_) => onCategory(item),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 18 : 48),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final count = constraints.crossAxisExtent > 1020
                      ? 4
                      : constraints.crossAxisExtent > 620
                          ? 3
                          : 2;
                  return SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _StoreProductCard(
                        product: visible[index],
                        onAdd: () => onAddToCart(visible[index]),
                      ),
                      childCount: visible.length,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: count,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 16,
                      mainAxisExtent: isMobile ? 280 : 350,
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Text(
                    'SEVENROSES  ·  Hecho para acompañarte',
                    style: TextStyle(
                        color: Colors.brown.shade300, letterSpacing: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _AssistantButton(
        products: products,
        orders: orders,
      ),
    );
  }
}

class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog({required this.cart});
  final List<Product> cart;

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  final _name = TextEditingController();
  String _payment = 'Transferencia';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total =
        widget.cart.fold<double>(0, (sum, product) => sum + product.price);
    return AlertDialog(
      title: const Text('Simular compra'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...widget.cart.map((product) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(product.name),
                    subtitle: Text('1 unidad · ${product.sku}'),
                    trailing: Text(_money(product.price)),
                  )),
              const Divider(),
              Text('Total: ${_money(total)}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Nombre de quien compra',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _payment,
                decoration: const InputDecoration(
                  labelText: 'Método de pago (simulado)',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  'Transferencia',
                  'Tarjeta (simulación)',
                  'Efectivo contra entrega'
                ]
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _payment = value ?? 'Transferencia'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Compra de demostración: no se cobra dinero ni se envía un pedido real.',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Seguir viendo'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _CheckoutRequest(_name.text.trim(), _payment),
                  ),
          child: const Text('Confirmar compra'),
        ),
      ],
    );
  }
}

class _StoreProductCard extends StatelessWidget {
  const _StoreProductCard({required this.product, required this.onAdd});
  final Product product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _ProductPhoto(product: product, fit: BoxFit.cover),
              ),
              Positioned(
                right: 9,
                top: 9,
                child: Material(
                  color: Colors.white.withValues(alpha: .92),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Agregar a la bolsa',
                    onPressed: onAdd,
                    icon:
                        const Icon(Icons.add_shopping_cart_outlined, size: 19),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(product.category.toUpperCase(),
            style: const TextStyle(
                fontSize: 10, letterSpacing: 1.2, color: _muted)),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, color: _ink),
              ),
            ),
            Text(_money(product.price),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        Text(product.color,
            style: const TextStyle(color: _muted, fontSize: 12)),
      ],
    );
  }
}

class _ProductPhoto extends StatelessWidget {
  const _ProductPhoto({
    required this.product,
    required this.fit,
    this.width,
    this.height,
  });

  final Product product;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    Widget errorBuilder(
        BuildContext context, Object error, StackTrace? stackTrace) {
      return Container(
        width: width,
        height: height,
        color: const Color(0xFFEDE5DF),
        child: const Icon(Icons.checkroom_outlined, size: 28, color: _accent),
      );
    }

    if (product.photo != null) {
      return Image.memory(
        product.photo!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder,
      );
    }
    return Image.network(
      product.image,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
    );
  }
}

class _AssistantButton extends StatefulWidget {
  const _AssistantButton({required this.products, required this.orders});
  final List<Product> products;
  final List<StoreOrder> orders;

  @override
  State<_AssistantButton> createState() => _AssistantButtonState();
}

class _AssistantButtonState extends State<_AssistantButton> {
  final _controller = TextEditingController();
  final _messages = <String>[
    '¡Hola! Soy SevenRoses. Pregúntame por un producto, disponibilidad o un pedido.',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(StateSetter updateSheet) {
    final question = _controller.text.trim();
    if (question.isEmpty) return;
    final answer = _answer(question);
    setState(() {
      _messages.add('Tú: $question');
      _messages.add('SevenRoses: $answer');
      _controller.clear();
    });
    updateSheet(() {});
  }

  String _answer(String question) {
    final normalized = _normalize(question);
    final order = widget.orders.cast<StoreOrder?>().firstWhere(
          (item) => normalized.contains(_normalize(item!.code)),
          orElse: () => null,
        );
    if (order != null) {
      return 'El pedido ${order.code} está: ${order.status}. Total ${_money(order.total)}.';
    }

    Product? product;
    var bestScore = 0;
    for (final item in widget.products) {
      final words = _normalize(item.name)
          .split(' ')
          .where((word) => word.length > 2)
          .toSet();
      final score = words.where(normalized.contains).length;
      if (score > bestScore) {
        bestScore = score;
        product = item;
      }
    }
    if (product != null) {
      final colors = 'Color: ${product.color}.';
      final sizes = product.sizes.isEmpty
          ? 'No tenemos tallas registradas para esta pieza; confirma con la tienda antes de comprar.'
          : 'Tallas: ${product.sizes.join(', ')}.';
      if (product.stock == 0) return '${product.name} está agotado.';
      return 'Sí, ${product.name} está disponible: ${_money(product.price)}. '
          'Quedan ${product.stock}. $colors $sizes';
    }
    if (RegExp(r'\b(horario|abren|abierto|cierran)\b').hasMatch(normalized)) {
      return 'Horario de muestra: lunes a sábado, de 10:00 a 19:00.';
    }
    if (RegExp(r'\b(pago|pagos|tarjeta|efectivo|transferencia)\b')
        .hasMatch(normalized)) {
      return 'Para esta simulación aceptamos tarjeta, transferencia y efectivo. '
          'No se realiza ningún cobro real.';
    }
    if (RegExp(r'\b(llega|envio|entrega|pedido|rastreo|seguimiento)\b')
        .hasMatch(normalized)) {
      return 'Escribe el código de tu pedido (por ejemplo, #SR-...) y te digo su estado.';
    }
    if (RegExp(r'\b(direccion|ubicacion|donde)\b').hasMatch(normalized)) {
      return 'La dirección de la tienda aún no está configurada.';
    }
    if (RegExp(r'\b(productos|catalogo|disponible|tienen|hay)\b')
        .hasMatch(normalized)) {
      final available =
          widget.products.where((item) => item.stock > 0).take(6).toList();
      return available.isEmpty
          ? 'No hay productos disponibles en este momento.'
          : 'Disponibles: ${available.map((item) => '${item.name} (${_money(item.price)})').join(', ')}.';
    }
    return 'No encontré esa respuesta. Puedes preguntar por nombre de producto, '
        'precio, disponibilidad, horario o estado de pedido.';
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: _ink,
      foregroundColor: Colors.white,
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 18,
              ),
              child: SizedBox(
                height: 360,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Asistente SevenRoses',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView(
                        children: _messages
                            .map((message) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 5),
                                  child: Text(message),
                                ))
                            .toList(),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            onSubmitted: (_) => _send(setSheetState),
                            decoration: const InputDecoration(
                              hintText: 'Escribe tu pregunta',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _send(setSheetState),
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      icon: const Icon(Icons.forum_outlined),
      label: const Text('¿Te ayudo?'),
    );
  }
}

class _AdminShell extends StatelessWidget {
  const _AdminShell({
    required this.section,
    required this.products,
    required this.sales,
    required this.orders,
    required this.events,
    required this.cloudConnected,
    required this.onSection,
    required this.onAddProduct,
    required this.onDeleteProduct,
    required this.onUpdateOrder,
    required this.onExit,
    required this.onProductsChanged,
  });

  final _Section section;
  final List<Product> products;
  final List<Sale> sales;
  final List<StoreOrder> orders;
  final List<StoreEvent> events;
  final bool cloudConnected;
  final ValueChanged<_Section> onSection;
  final VoidCallback onAddProduct;
  final ValueChanged<Product> onDeleteProduct;
  final void Function(StoreOrder, String) onUpdateOrder;
  final VoidCallback onExit;
  final VoidCallback onProductsChanged;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 760;
    final selectedIndex = _sections.indexWhere((item) => item.$1 == section);
    final content = switch (section) {
      _Section.dashboard => _Dashboard(
          products: products,
          sales: sales,
          orders: orders,
          onSection: onSection,
        ),
      _Section.inventory => _InventoryPage(
          products: products,
          onAdd: onAddProduct,
          onChanged: onProductsChanged,
          onDelete: onDeleteProduct,
        ),
      _Section.sales => _SalesPage(sales: sales),
      _Section.orders => _OrdersPage(orders: orders, onUpdate: onUpdateOrder),
      _Section.reports => _ReportsPage(sales: sales, products: products),
    };

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (!isMobile)
              _AdminSidebar(
                selected: selectedIndex,
                cloudConnected: cloudConnected,
                onSelect: (index) => onSection(_sections[index].$1),
                onExit: onExit,
              ),
            Expanded(
              child: Column(
                children: [
                  _AdminTopbar(
                    title: _sections[selectedIndex].$2,
                    isMobile: isMobile,
                    events: events,
                    onExit: onExit,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isMobile ? 16 : 30),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1250),
                          child: content,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isMobile
          ? NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) => onSection(_sections[index].$1),
              destinations: _sections
                  .map((item) => NavigationDestination(
                        icon: Icon(item.$3),
                        label: item.$2,
                      ))
                  .toList(),
            )
          : null,
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.selected,
    required this.cloudConnected,
    required this.onSelect,
    required this.onExit,
  });
  final int selected;
  final bool cloudConnected;
  final ValueChanged<int> onSelect;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 242,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFEFEAE6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 25, 16, 29),
            child: Row(
              children: [
                Icon(Icons.flare_rounded, color: _accent, size: 28),
                SizedBox(width: 8),
                Text('SevenRoses',
                    style: TextStyle(
                        letterSpacing: 3, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 24, bottom: 12),
            child: Text('MENÚ PRINCIPAL',
                style:
                    TextStyle(fontSize: 10, letterSpacing: 1.4, color: _muted)),
          ),
          ...List.generate(_sections.length, (index) {
            final item = _sections[index];
            final active = selected == index;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Material(
                color: Colors.white,
                child: ListTile(
                  selected: active,
                  selectedTileColor: const Color(0xFFF5EEEA),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  leading:
                      Icon(item.$3, color: active ? _accent : _muted, size: 21),
                  title: Text(
                    item.$2,
                    style: TextStyle(
                      color: active ? _accent : _ink,
                      fontSize: 14,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  onTap: () => onSelect(index),
                ),
              ),
            );
          }),
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _paper,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  cloudConnected
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: cloudConnected ? Color(0xFF628C73) : Color(0xFFB97443),
                ),
                SizedBox(height: 8),
                Text(cloudConnected ? 'Sincronización activa' : 'Modo local',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    cloudConnected
                        ? 'Firebase en tiempo real'
                        : 'Firebase no configurado',
                    style: TextStyle(fontSize: 11, color: _muted)),
              ],
            ),
          ),
          Material(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Volver a la tienda'),
              onTap: onExit,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _AdminTopbar extends StatelessWidget {
  const _AdminTopbar({
    required this.title,
    required this.isMobile,
    required this.events,
    required this.onExit,
  });
  final String title;
  final bool isMobile;
  final List<StoreEvent> events;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEFEAE6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ),
          if (!isMobile)
            const Text('Viernes, 6 de noviembre',
                style: TextStyle(color: _muted, fontSize: 12)),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Notificaciones',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _NotificationsDialog(events: events),
            ),
            icon: Badge(
              isLabelVisible: events.isNotEmpty,
              label: Text('${events.length}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const CircleAvatar(
            radius: 17,
            backgroundColor: Color(0xFFF1E4DB),
            child: Text('M', style: TextStyle(color: _accent)),
          ),
          if (isMobile)
            IconButton(
              tooltip: 'Volver a la tienda',
              onPressed: onExit,
              icon: const Icon(Icons.logout_rounded),
            )
          else
            const Padding(
              padding: EdgeInsets.only(left: 9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mariana',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text('Administradora',
                      style: TextStyle(fontSize: 10, color: _muted)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationsDialog extends StatelessWidget {
  const _NotificationsDialog({required this.events});
  final List<StoreEvent> events;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Notificaciones de SevenRoses'),
        content: SizedBox(
          width: 420,
          child: events.isEmpty
              ? const Text(
                  'Aún no hay eventos recibidos. Las compras y los cambios aparecerán aquí al conectarse el backend AWS.',
                )
              : ListView(
                  shrinkWrap: true,
                  children: events
                      .map((event) => ListTile(
                            leading: const Icon(
                                Icons.notifications_active_outlined,
                                color: _accent),
                            title: Text(event.message),
                            subtitle: Text(
                              '${event.date.day}/${event.date.month} ${event.date.hour.toString().padLeft(2, '0')}:${event.date.minute.toString().padLeft(2, '0')}',
                            ),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      );
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.products,
    required this.sales,
    required this.orders,
    required this.onSection,
  });
  final List<Product> products;
  final List<Sale> sales;
  final List<StoreOrder> orders;
  final ValueChanged<_Section> onSection;

  @override
  Widget build(BuildContext context) {
    final lowStock = products.where((product) => product.stock < 5).toList();
    final todayTotal = sales.fold<double>(
      0,
      (sum, sale) => sum + sale.total,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Buenos días, Mariana ☀️',
                      style:
                          TextStyle(fontSize: 25, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Aquí tienes el resumen de tu tienda.',
                      style: TextStyle(color: _muted)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => onSection(_Section.sales),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Ver ventas'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth > 900
              ? 4
              : constraints.maxWidth > 510
                  ? 2
                  : 1;
          final cards = [
            _StatCard(
              title: 'Ventas de hoy',
              value: _money(todayTotal),
              detail: '↑ 12.8% vs. ayer',
              icon: Icons.trending_up_rounded,
              color: const Color(0xFF658B70),
            ),
            _StatCard(
              title: 'Pedidos activos',
              value:
                  '${orders.where((order) => order.status != 'Entregado').length}',
              detail: '2 requieren atención',
              icon: Icons.shopping_bag_outlined,
              color: const Color(0xFF9B765A),
            ),
            _StatCard(
              title: 'Productos',
              value: '${products.length}',
              detail: '$lowStock con poco stock',
              icon: Icons.inventory_2_outlined,
              color: const Color(0xFF71829A),
            ),
            const _StatCard(
              title: 'Ticket promedio',
              value: 'Q1,240.00',
              detail: '↑ 8.2% este mes',
              icon: Icons.payments_outlined,
              color: Color(0xFF9C7E9F),
            ),
          ];
          return GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 13,
            mainAxisSpacing: 13,
            childAspectRatio: columns == 1 ? 2.2 : 1.85,
            children: cards,
          );
        }),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final stack = constraints.maxWidth < 750;
          final chart = _Panel(
            title: 'Resumen de ventas',
            trailing: const Text('Últimos 7 días',
                style: TextStyle(fontSize: 12, color: _muted)),
            child: SizedBox(
              height: 220,
              child: CustomPaint(
                painter: _SalesChartPainter(),
                child: const SizedBox.expand(),
              ),
            ),
          );
          final activity = _Panel(
            title: 'Actividad reciente',
            trailing: TextButton(
              onPressed: () => onSection(_Section.sales),
              child: const Text('Ver todo'),
            ),
            child: Column(
              children: sales.take(4).map((sale) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFF4ECE7),
                    child: const Icon(Icons.shopping_bag_outlined,
                        color: _accent, size: 19),
                  ),
                  title: Text(sale.product,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${sale.quantity} pza. · ${sale.payment}'),
                  trailing: Text(
                    '${sale.date.hour.toString().padLeft(2, '0')}:${sale.date.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                );
              }).toList(),
            ),
          );
          return stack
              ? Column(children: [chart, const SizedBox(height: 14), activity])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: chart),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: activity),
                  ],
                );
        }),
        const SizedBox(height: 15),
        _Panel(
          title: 'Inventario por revisar',
          trailing: TextButton(
            onPressed: () => onSection(_Section.inventory),
            child: const Text('Ir al inventario'),
          ),
          child: lowStock.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Todo el inventario está en niveles saludables.'),
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: lowStock
                      .map((product) => Chip(
                            avatar: const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFB97443), size: 17),
                            label: Text(
                                '${product.name} · ${product.stock} pzas.'),
                            backgroundColor: const Color(0xFFFFF6E8),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });
  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEFEAE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(color: _muted, fontSize: 12))),
              Icon(icon, color: color, size: 20),
            ],
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 25, fontWeight: FontWeight.w700, color: _ink)),
          Text(detail, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEFEAE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SalesChartPainter extends CustomPainter {
  const _SalesChartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const values = [0.38, 0.54, 0.48, 0.76, 0.62, 0.84, 0.91];
    final grid = Paint()
      ..color = const Color(0xFFF0ECE8)
      ..strokeWidth = 1;
    for (var index = 0; index < 4; index++) {
      final y = size.height * (index + 1) / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      points.add(Offset(
        size.width * index / (values.length - 1),
        size.height * (1 - values[index]) * .84 + 12,
      ));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final middle = (previous.dx + current.dx) / 2;
      path.cubicTo(
          middle, previous.dy, middle, current.dy, current.dx, current.dy);
    }
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x339B6251), Color(0x009B6251)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _accent
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final point in points) {
      canvas.drawCircle(point, 4, Paint()..color = _accent);
      canvas.drawCircle(point, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InventoryPage extends StatefulWidget {
  const _InventoryPage({
    required this.products,
    required this.onAdd,
    required this.onChanged,
    required this.onDelete,
  });
  final List<Product> products;
  final VoidCallback onAdd;
  final VoidCallback onChanged;
  final ValueChanged<Product> onDelete;

  @override
  State<_InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<_InventoryPage> {
  String _query = '';
  String _filter = 'Todos';

  @override
  Widget build(BuildContext context) {
    final matches = widget.products.where((product) {
      final queryMatch = '${product.name} ${product.sku}'
          .toLowerCase()
          .contains(_query.toLowerCase());
      final filterMatch = _filter == 'Todos' ||
          (_filter == 'Poco stock' && product.stock > 0 && product.stock < 5) ||
          (_filter == 'Agotados' && product.stock == 0);
      return queryMatch && filterMatch;
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          title: 'Inventario',
          subtitle: 'Administra tus productos y niveles de existencias.',
          action: FilledButton.icon(
            onPressed: widget.onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Agregar producto'),
          ),
        ),
        const SizedBox(height: 18),
        _Panel(
          title: '${widget.products.length} productos',
          child: Column(
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        hintText: 'Buscar por nombre o SKU',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  DropdownButton<String>(
                    value: _filter,
                    items: ['Todos', 'Poco stock', 'Agotados']
                        .map((item) =>
                            DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _filter = value ?? 'Todos'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth < 570) {
                  return Column(
                    children: matches
                        .map((product) => _InventoryTile(
                              product: product,
                              onChanged: () => setState(() {}),
                              onDelete: () => widget.onDelete(product),
                            ))
                        .toList(),
                  );
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 25,
                    columns: const [
                      DataColumn(label: Text('PRODUCTO')),
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('CATEGORÍA')),
                      DataColumn(label: Text('PRECIO')),
                      DataColumn(label: Text('EXISTENCIAS')),
                      DataColumn(label: Text('')),
                    ],
                    rows: matches.map((product) {
                      final status = product.stock == 0
                          ? 'Agotado'
                          : product.stock < 5
                              ? 'Poco stock'
                              : 'Disponible';
                      return DataRow(cells: [
                        DataCell(SizedBox(
                          width: 155,
                          child: Row(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: _ProductPhoto(
                                  product: product,
                                  width: 34,
                                  height: 38,
                                  fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(product.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        )),
                        DataCell(Text(product.sku)),
                        DataCell(Text(product.category)),
                        DataCell(Text(_money(product.price))),
                        DataCell(
                            _StockChip(stock: product.stock, status: status)),
                        DataCell(IconButton(
                          tooltip: 'Eliminar producto',
                          onPressed: () => widget.onDelete(product),
                          icon: const Icon(Icons.delete_outline, size: 19),
                        )),
                      ]);
                    }).toList(),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _InventoryTile extends StatelessWidget {
  const _InventoryTile({
    required this.product,
    required this.onChanged,
    required this.onDelete,
  });
  final Product product;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final status = product.stock == 0
        ? 'Agotado'
        : product.stock < 5
            ? 'Poco stock'
            : 'Disponible';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _ProductPhoto(
            product: product, width: 42, height: 48, fit: BoxFit.cover),
      ),
      title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${product.sku} · ${_money(product.price)}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StockChip(stock: product.stock, status: status),
          SizedBox(
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockChip extends StatelessWidget {
  const _StockChip({required this.stock, required this.status});
  final int stock;
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = status == 'Disponible'
        ? const Color(0xFF4F8160)
        : status == 'Agotado'
            ? const Color(0xFFB6524B)
            : const Color(0xFFB97443);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$stock · $status',
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({
    required this.onCapture,
    required this.onRecognize,
    required this.onScanBarcode,
  });
  final Future<Uint8List?> Function(ImageSource) onCapture;
  final Future<List<String>> Function(Uint8List) onRecognize;
  final Future<String?> Function() onScanBarcode;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  String _category = 'Ropa';
  Uint8List? _photo;
  bool _recognizing = false;
  String? _recognition;

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _capture(ImageSource source) async {
    final photo = await widget.onCapture(source);
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  Future<void> _recognize() async {
    if (_photo == null) return;
    setState(() => _recognizing = true);
    try {
      final labels = await widget.onRecognize(_photo!);
      if (!mounted) return;
      final searchable = labels.join(' ').toLowerCase();
      final category = searchable.contains('shoe') ||
              searchable.contains('footwear')
          ? 'Zapatos'
          : searchable.contains('bag') || searchable.contains('jewelry')
              ? 'Accesorios'
              : searchable.contains('cosmetic') || searchable.contains('makeup')
                  ? 'Cosméticos'
                  : 'Ropa';
      setState(() {
        _category = category;
        _recognition = labels.take(5).join(', ');
      });
    } catch (error) {
      if (mounted) setState(() => _recognition = '$error');
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  Future<void> _scan() async {
    final barcode = await widget.onScanBarcode();
    if (barcode != null && mounted) {
      setState(() {
        _sku.text = barcode;
        _recognition = 'Código leído: $barcode';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar producto'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                if (_photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_photo!,
                        height: 150, width: double.infinity, fit: BoxFit.cover),
                  )
                else
                  Container(
                    height: 110,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: _paper,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEFEAE6)),
                    ),
                    child: const Icon(Icons.add_a_photo_outlined,
                        color: _muted, size: 32),
                  ),
                Wrap(
                  spacing: 6,
                  children: [
                    TextButton.icon(
                      onPressed: () => _capture(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Cámara'),
                    ),
                    TextButton.icon(
                      onPressed: () => _capture(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Galería'),
                    ),
                    TextButton.icon(
                      onPressed: _recognizing ? null : _recognize,
                      icon: _recognizing
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Categorizar con AWS'),
                    ),
                  ],
                ),
                if (_recognition != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_recognition!,
                          style: const TextStyle(fontSize: 12, color: _muted)),
                    ),
                  ),
                TextFormField(
                  controller: _name,
                  decoration:
                      const InputDecoration(labelText: 'Nombre del producto'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Escribe un nombre.'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _sku,
                  decoration: InputDecoration(
                    labelText: 'Código de barras / SKU',
                    suffixIcon: IconButton(
                      tooltip: 'Leer código con cámara',
                      onPressed: _scan,
                      icon: const Icon(Icons.document_scanner_outlined),
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Escribe un SKU.'
                      : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    'Ropa',
                    'Zapatos',
                    'Accesorios',
                    'Cosméticos',
                    'Otros'
                  ]
                      .map((item) =>
                          DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _category = value ?? 'Ropa'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(labelText: 'Precio'),
                        validator: (value) =>
                            double.tryParse(value ?? '') == null
                                ? 'Precio inválido.'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Existencias'),
                        validator: (value) => int.tryParse(value ?? '') == null
                            ? 'Cantidad inválida.'
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              Product(
                name: _name.text.trim(),
                category: _category,
                sku: _sku.text.trim(),
                price: double.parse(_price.text),
                stock: int.parse(_stock.text),
                photo: _photo,
                image: _photo == null
                    ? 'https://images.unsplash.com/photo-1483985988355-763728e1935b?w=700&q=85'
                    : '',
              ),
            );
          },
          child: const Text('Guardar producto'),
        ),
      ],
    );
  }
}

class _BarcodeScannerDialog extends StatelessWidget {
  const _BarcodeScannerDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Escanear código de barras'),
        content: SizedBox(
          width: 380,
          height: 300,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: MobileScanner(
              onDetect: (capture) {
                final value = capture.barcodes
                    .map((barcode) => barcode.rawValue)
                    .whereType<String>()
                    .firstOrNull;
                if (value != null && context.mounted) {
                  Navigator.pop(context, value);
                }
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      );
}

class _SalesPage extends StatelessWidget {
  const _SalesPage({required this.sales});
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          title: 'Ventas',
          subtitle: 'Compras web registradas automáticamente.',
        ),
        const SizedBox(height: 18),
        _Panel(
          title: '${sales.length} ventas',
          child: Column(
            children: sales.isEmpty
                ? const [
                    ListTile(
                      leading: Icon(Icons.info_outline, color: _muted),
                      title: Text('Aún no hay compras.'),
                      subtitle: Text(
                          'Las compras confirmadas desde la web aparecerán aquí.'),
                    ),
                  ]
                : sales
                    .map((sale) => ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFF5EEEA),
                            child: Icon(Icons.receipt_long_outlined,
                                color: _accent),
                          ),
                          title: Text('${sale.code} · ${sale.product}'),
                          subtitle: Text(
                            '${sale.customer} · ${sale.quantity} unidad(es) · ${sale.payment} · ${sale.date.day}/${sale.date.month}/${sale.date.year}',
                          ),
                          trailing: Text(_money(sale.total)),
                        ))
                    .toList(),
          ),
        ),
      ],
    );
  }
}

class _OrdersPage extends StatelessWidget {
  const _OrdersPage({required this.orders, required this.onUpdate});
  final List<StoreOrder> orders;
  final void Function(StoreOrder, String) onUpdate;

  @override
  Widget build(BuildContext context) {
    const statuses = [
      'Pedido recibido',
      'En preparación',
      'Empacado',
      'En ruta',
      'Entregado',
      'Cancelado',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageHeading(
          title: 'Pedidos y envíos',
          subtitle: 'Consulta pedidos y mantén al cliente al tanto del envío.',
        ),
        const SizedBox(height: 18),
        _Panel(
          title: '${orders.length} pedidos recientes',
          child: Column(
            children: orders
                .map((order) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 5),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFF5EEEA),
                        child:
                            Icon(Icons.local_shipping_outlined, color: _accent),
                      ),
                      title: Text('${order.code} · ${order.customer}'),
                      subtitle:
                          Text('${_money(order.total)} · Seguimiento de envío'),
                      trailing: SizedBox(
                        width: 160,
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: statuses.contains(order.status)
                              ? order.status
                              : statuses.first,
                          items: statuses
                              .map((status) => DropdownMenuItem(
                                  value: status, child: Text(status)))
                              .toList(),
                          onChanged: (status) {
                            if (status != null) onUpdate(order, status);
                          },
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 14),
        _Panel(
          title: 'Mapa de seguimiento',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 300, child: _OrderMap(orders: orders)),
              const SizedBox(height: 8),
              const Text(
                'Mapa libre OpenStreetMap. Las ubicaciones de esta demostración son ilustrativas, no GPS en vivo.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderMap extends StatelessWidget {
  const _OrderMap({required this.orders});
  final List<StoreOrder> orders;

  static const _store = LatLng(14.6349, -90.5069);
  static const _stops = [
    LatLng(14.6349, -90.5069),
    LatLng(14.6411, -90.5145),
    LatLng(14.6468, -90.5222),
  ];

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: FlutterMap(
          options: const MapOptions(initialCenter: _store, initialZoom: 13),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sevenroses.store',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _stops,
                  strokeWidth: 4,
                  color: _accent,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _store,
                  width: 42,
                  height: 48,
                  child: const Icon(Icons.store_rounded, color: _ink, size: 32),
                ),
                ...List.generate(
                  orders.isEmpty
                      ? 1
                      : orders.length.clamp(1, _stops.length - 1).toInt(),
                  (index) => Marker(
                    point: _stops[index + 1],
                    width: 44,
                    height: 52,
                    child: Tooltip(
                      message: orders.isEmpty
                          ? 'Ruta de demostración'
                          : orders[index].code,
                      child: const Icon(Icons.location_on,
                          color: _accent, size: 38),
                    ),
                  ),
                ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
      );
}

class _ReportsPage extends StatelessWidget {
  const _ReportsPage({required this.sales, required this.products});
  final List<Sale> sales;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final units = sales.fold<int>(0, (sum, sale) => sum + sale.quantity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageHeading(
          title: 'Reportes',
          subtitle: 'Una vista sencilla del rendimiento de tu negocio.',
        ),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final count = constraints.maxWidth > 720 ? 3 : 1;
          return GridView.count(
            crossAxisCount: count,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: count == 1 ? 3.2 : 1.7,
            children: [
              _StatCard(
                title: 'Ventas registradas',
                value: '${sales.length}',
                detail: 'Movimientos de muestra',
                icon: Icons.receipt_long_outlined,
                color: const Color(0xFF658B70),
              ),
              _StatCard(
                title: 'Unidades vendidas',
                value: '$units',
                detail: 'En las operaciones visibles',
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFF71829A),
              ),
              _StatCard(
                title: 'Valor inventario',
                value: _money(products.fold<double>(
                    0, (sum, item) => sum + item.price * item.stock)),
                detail: 'A precio de venta',
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFF9C7E9F),
              ),
            ],
          );
        }),
        const SizedBox(height: 14),
        const _Panel(
          title: 'Tendencia semanal',
          child: SizedBox(
            height: 230,
            child: CustomPaint(
              painter: _SalesChartPainter(),
              child: SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Panel(
          title: 'Exportación y respaldos',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El panel está preparado para conectar exportaciones Excel/PDF automáticas. '
                'Configura el backend para generar respaldos y archivar reportes pesados.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Conecta el servicio de reportes para exportar Excel o PDF.'),
                  ),
                ),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Preparar exportación'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading(
      {required this.title, required this.subtitle, this.action});
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 12,
      children: [
        SizedBox(
          width: MediaQuery.sizeOf(context).width < 550 ? 280 : 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: _muted)),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}
