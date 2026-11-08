import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseBackend {
  FirebaseBackend._();
  static bool _googleInitialized = false;

  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _defaultAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _androidAppId =
      String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get configured =>
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _projectId.isNotEmpty &&
      _senderId.isNotEmpty;
  static String get _appId {
    final platformAppId = switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidAppId,
      TargetPlatform.iOS => _iosAppId,
      _ => _webAppId,
    };
    return platformAppId.isNotEmpty ? platformAppId : _defaultAppId;
  }

  static bool get available => Firebase.apps.isNotEmpty;
  static FirebaseFirestore get database => FirebaseFirestore.instance;
  static FirebaseAuth get auth => FirebaseAuth.instance;

  static Future<void> initialize() async {
    if (!configured) return;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: _apiKey,
        appId: _appId,
        projectId: _projectId,
        messagingSenderId: _senderId,
        authDomain: _authDomain.isEmpty ? null : _authDomain,
      ),
    );
  }

  static Future<User?> signInAdminWithGoogle() async {
    if (!available) {
      throw StateError('Configura primero el proyecto Firebase.');
    }

    final google = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize(
        serverClientId:
            googleServerClientId.isEmpty ? null : googleServerClientId,
      );
      _googleInitialized = true;
    }
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google no devolvió un token de autenticación.');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result = await auth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) throw StateError('Firebase no devolvió una cuenta.');

    final admin = await database.collection('admins').doc(user.uid).get();
    if (!admin.exists) {
      await auth.signOut();
      await google.signOut();
      throw StateError(
        'Esta cuenta Google no está autorizada como administradora. '
        'Agrega su UID a la colección admins de Firebase.',
      );
    }
    return user;
  }

  static Stream<List<Map<String, dynamic>>> watchProducts() => database
      .collection('products')
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((document) => {'id': document.id, ...document.data()})
          .toList());

  static Stream<List<Map<String, dynamic>>> watchOrders() => database
      .collection('orders')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((document) => {'id': document.id, ...document.data()})
          .toList());

  static Future<void> saveProduct(
    String id,
    Map<String, Object?> data,
  ) async {
    await database.collection('products').doc(id).set(data);
  }

  static Future<void> deleteProduct(String id) async {
    await database.collection('products').doc(id).delete();
  }

  static Future<String> createOrder({
    required List<Map<String, Object?>> products,
    required String customer,
    required String payment,
  }) async {
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    final customerUid = auth.currentUser?.uid;
    if (customerUid == null) {
      throw StateError('No se pudo crear una sesión de compra anónima.');
    }
    final order = database.collection('orders').doc();
    final grouped = <String, int>{};
    final items = <Map<String, Object?>>[];
    var total = 0.0;
    for (final product in products) {
      final id = product['id'] as String;
      grouped.update(id, (quantity) => quantity + 1, ifAbsent: () => 1);
      total += (product['price'] as num).toDouble();
      final existing = items.where((item) => item['productId'] == id);
      if (existing.isEmpty) {
        items.add({
          'productId': id,
          'name': product['name'],
          'sku': product['sku'],
          'price': product['price'],
          'quantity': 1,
        });
      } else {
        existing.first['quantity'] = (existing.first['quantity'] as int) + 1;
      }
    }
    final stockChanges = <String, int>{};
    final refs = grouped.keys
        .map((id) => database.collection('products').doc(id))
        .toList();

    await database.runTransaction((transaction) async {
      final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final ref in refs) {
        snapshots.add(await transaction.get(ref));
      }
      for (var index = 0; index < refs.length; index++) {
        final snapshot = snapshots[index];
        final id = refs[index].id;
        final data = snapshot.data();
        final quantity = grouped[id]!;
        if (data == null || (data['stock'] as num? ?? 0) < quantity) {
          throw StateError('Ya no hay existencias suficientes del producto.');
        }
        stockChanges[id] = quantity;
      }
      transaction.set(order, {
        'code': '#SR-${order.id}',
        'customer': customer,
        'customerUid': customerUid,
        'payment': payment,
        'total': total,
        'status': 'Pedido recibido',
        'items': items,
        'stockChanges': stockChanges,
        'createdAt': FieldValue.serverTimestamp(),
      });
      for (var index = 0; index < refs.length; index++) {
        final id = refs[index].id;
        final data = snapshots[index].data()!;
        transaction.update(refs[index], {
          'stock': (data['stock'] as num).toInt() - grouped[id]!,
          'lastOrderId': order.id,
        });
      }
    });
    return '#SR-${order.id}';
  }

  static Future<void> updateOrderStatus(String id, String status) async {
    await database.collection('orders').doc(id).update({'status': status});
  }

  static Future<void> signOut() async {
    await auth.signOut();
    if (!kIsWeb) await GoogleSignIn.instance.signOut();
  }
}
