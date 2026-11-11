import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product_item.dart';
import '../models/subscription_state.dart';
import 'auth_service.dart';
import 'price_list_formatter.dart';
import 'subscription_service.dart';

/// Servicio de gestión del Catálogo de Productos con respaldo por cuenta
/// en `Cloud Firestore` (`users/{uid}/products/{productId}`) y caché
/// local aislada por usuario para funcionamiento sin conexión.
class ProductsService {
  static const String _localKey = 'catalog_products_list';

  FirebaseFirestore? get _firestore =>
      AuthService.isFirebaseInitialized ? FirebaseFirestore.instance : null;

  String? get _currentUid => AuthService().currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _userProductsCol {
    final db = _firestore;
    final uid = _currentUid;
    if (db == null || uid == null || uid.isEmpty) return null;
    return db.collection('users').doc(uid).collection('products');
  }

  String _cacheKeyForUser() {
    final uid = _currentUid;
    return (uid != null && uid.isNotEmpty) ? '${_localKey}_$uid' : _localKey;
  }

  /// Obtiene la lista de productos. En entornos de prueba (sin Firebase inicializado),
  /// usa la persistencia local. En producción, exige sesión de usuario y sincroniza
  /// con Firestore (`users/{uid}/products`).
  Future<List<ProductItem>> getProducts({bool syncRemote = true}) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Entorno de pruebas / sin Firebase inicializado
    if (!AuthService.isFirebaseInitialized) {
      return List<ProductItem>.from(
        ProductItem.listFromJson(prefs.getString(_localKey)),
      );
    }

    // 2. Producción sin sesión activa: no mostrar productos de otras cuentas
    final uid = _currentUid;
    if (uid == null || uid.isEmpty) {
      return const [];
    }

    final userKey = _cacheKeyForUser();
    final cachedList = List<ProductItem>.from(
      ProductItem.listFromJson(prefs.getString(userKey)),
    );

    final col = _userProductsCol;
    if (!syncRemote || col == null) {
      return cachedList;
    }

    // 3. Sincronización con Cloud Firestore como fuente de verdad
    try {
      final snap = await col
          .get()
          .timeout(const Duration(seconds: 8));

      final remoteList = <ProductItem>[];
      for (final doc in snap.docs) {
        final raw = Map<String, dynamic>.from(doc.data());
        if ((raw['id']?.toString() ?? '').trim().isEmpty) {
          raw['id'] = doc.id;
        }
        final item = ProductItem.fromJson(raw);
        if (item.isValid) {
          remoteList.add(item);
        }
      }

      remoteList.sort(
        (a, b) => compareNaturalProductNames(a.name, b.name),
      );

      // Actualizar la caché local exclusiva de este usuario
      await prefs.setString(
        userKey,
        jsonEncode(remoteList.map((p) => p.toJson()).toList()),
      );

      return remoteList;
    } catch (_) {
      // Si no hay conexión o falla la red, devolver la caché del usuario
      return cachedList;
    }
  }

  static void _validateForCloud(ProductItem product) {
    final name = product.name.trim();
    final cat = product.category.trim();
    if (product.id.trim().isEmpty || product.id.length > 120) {
      throw ArgumentError('Identificador de producto inválido.');
    }
    if (name.isEmpty || name.length > 120) {
      throw ArgumentError(
        'El nombre del producto debe tener entre 1 y 120 caracteres.',
      );
    }
    if (cat.length > 80) {
      throw ArgumentError(
        'La categoría no puede superar los 80 caracteres.',
      );
    }
    if (product.costUsd <= 0) {
      throw ArgumentError('El costo en USD debe ser mayor que 0.');
    }
    if (product.marginPercent < 0 || product.marginPercent >= 100) {
      throw ArgumentError('El margen debe estar entre 0 % y 99,9 %.');
    }
    if (product.fixedExpenseBs < 0) {
      throw ArgumentError('El gasto fijo no puede ser negativo.');
    }
    if (product.commissionPlatform < 0 ||
        product.commissionPaymentMethod < 0 ||
        product.commissionOther < 0 ||
        (product.commissionPlatform +
                product.commissionPaymentMethod +
                product.commissionOther) >=
            1.0) {
      throw ArgumentError(
        'Las comisiones deben ser no negativas y sumar menos del 100 %.',
      );
    }
    if (!const [0, 1, 10, 50, 100].contains(product.roundStep)) {
      throw ArgumentError('Paso de redondeo inválido.');
    }
    if (product.customRateValue != null && product.customRateValue! < 0) {
      throw ArgumentError('La tasa personalizada no puede ser negativa.');
    }
  }

  /// Guarda o actualiza un producto directamente en Firestore (`users/{uid}/products/{id}`)
  /// y actualiza la caché local del usuario autenticado.
  Future<void> saveProduct(ProductItem product) async {
    _validateForCloud(product);

    final prefs = await SharedPreferences.getInstance();

    // Entorno de pruebas sin Firebase
    if (!AuthService.isFirebaseInitialized) {
      final current = List<ProductItem>.from(
        ProductItem.listFromJson(prefs.getString(_localKey)),
      );
      final idx = current.indexWhere((p) => p.id == product.id);
      if (idx >= 0) {
        current[idx] = product;
      } else {
        current.insert(0, product);
      }
      await prefs.setString(
        _localKey,
        jsonEncode(current.map((p) => p.toJson()).toList()),
      );
      return;
    }

    final col = _userProductsCol;
    final uid = _currentUid;
    if (col == null || uid == null || uid.isEmpty) {
      throw StateError(
        'Debes iniciar sesión con tu cuenta de Google o correo para guardar productos en la nube.',
      );
    }

    // Límite del Plan Gratis: hasta 10 productos nuevos en la nube (Pro ilimitado).
    // Nunca bloquea editar productos existentes.
    if (!SubscriptionService.instance.isPro) {
      final existingSnap =
          await col.doc(product.id).get().timeout(const Duration(seconds: 8));
      if (!existingSnap.exists) {
        final countSnap = await col
            .limit(SubscriptionState.freeMaxProducts)
            .get()
            .timeout(const Duration(seconds: 8));
        if (countSnap.docs.length >= SubscriptionState.freeMaxProducts) {
          throw const FreeLimitReachedException(
            'Alcanzaste el límite de 10 productos del Plan Gratis. Activa Pro para guardar productos ilimitados.',
          );
        }
      }
    }

    // Guarda en Cloud Firestore con verificación (no se traga excepciones)
    await col
        .doc(product.id)
        .set(product.toJson())
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException(
            'Tiempo de espera agotado al conectar con Firebase. Revisa tu conexión a internet.',
          ),
        );

    // Actualiza la caché local del usuario
    final userKey = _cacheKeyForUser();
    final current = List<ProductItem>.from(
      ProductItem.listFromJson(prefs.getString(userKey)),
    );

    final idx = current.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      current[idx] = product;
    } else {
      current.insert(0, product);
    }

    await prefs.setString(
      userKey,
      jsonEncode(current.map((p) => p.toJson()).toList()),
    );
  }

  /// Transmite la lista de productos de Firestore en tiempo real cuando hay sesión.
  Stream<List<ProductItem>> streamProducts() {
    if (!AuthService.isFirebaseInitialized) {
      return Stream.fromFuture(getProducts(syncRemote: false));
    }

    final col = _userProductsCol;
    final uid = _currentUid;
    if (col == null || uid == null || uid.isEmpty) {
      return const Stream.empty();
    }

    final userKey = _cacheKeyForUser();
    return col.snapshots().map((snap) {
      final list = <ProductItem>[];
      for (final doc in snap.docs) {
        final raw = Map<String, dynamic>.from(doc.data());
        if ((raw['id']?.toString() ?? '').trim().isEmpty) {
          raw['id'] = doc.id;
        }
        final p = ProductItem.fromJson(raw);
        if (p.isValid) list.add(p);
      }
      list.sort((a, b) => compareNaturalProductNames(a.name, b.name));
      SharedPreferences.getInstance().then((prefs) async {
        try {
          await prefs.setString(
            userKey,
            jsonEncode(list.map((p) => p.toJson()).toList()),
          );
        } catch (_) {}
      });
      return list;
    });
  }

  /// Elimina un producto por su [id] tanto en Firestore como en la caché local.
  Future<void> deleteProduct(String id) async {
    final prefs = await SharedPreferences.getInstance();

    if (!AuthService.isFirebaseInitialized) {
      final current = List<ProductItem>.from(
        ProductItem.listFromJson(prefs.getString(_localKey)),
      )..removeWhere((p) => p.id == id);
      await prefs.setString(
        _localKey,
        jsonEncode(current.map((p) => p.toJson()).toList()),
      );
      return;
    }

    final userKey = _cacheKeyForUser();
    final current = List<ProductItem>.from(
      ProductItem.listFromJson(prefs.getString(userKey)),
    )..removeWhere((p) => p.id == id);
    await prefs.setString(
      userKey,
      jsonEncode(current.map((p) => p.toJson()).toList()),
    );

    final col = _userProductsCol;
    if (col != null) {
      await col
          .doc(id)
          .delete()
          .timeout(const Duration(seconds: 8));
    }
  }

  /// Limpia todos los productos del usuario actual.
  Future<void> clearAllProducts() async {
    final prefs = await SharedPreferences.getInstance();
    if (!AuthService.isFirebaseInitialized) {
      await prefs.remove(_localKey);
      return;
    }

    final userKey = _cacheKeyForUser();
    await prefs.remove(userKey);

    final col = _userProductsCol;
    if (col != null) {
      final snap = await col.get().timeout(const Duration(seconds: 8));
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
    }
  }
}
