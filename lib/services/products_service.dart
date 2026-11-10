import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product_item.dart';
import 'auth_service.dart';

/// Servicio de gestión del Catálogo de Productos con arquitectura Local-First
/// (`SharedPreferences`) + sincronización automática en `Cloud Firestore`
/// cuando el usuario ha iniciado sesión (`users/{uid}/products/{productId}`).
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

  /// Obtiene la lista de productos local y, si hay sesión activa, sincroniza con Firestore.
  Future<List<ProductItem>> getProducts({bool syncRemote = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final localList = List<ProductItem>.from(
      ProductItem.listFromJson(prefs.getString(_localKey)),
    );

    final col = _userProductsCol;
    if (!syncRemote || col == null) {
      return localList;
    }

    try {
      final snap = await col.get();
      final byId = <String, ProductItem>{
        for (final p in localList) p.id: p,
      };

      for (final doc in snap.docs) {
        final remoteProd = ProductItem.fromJson(doc.data());
        if (remoteProd.isValid) {
          final existing = byId[remoteProd.id];
          if (existing == null ||
              remoteProd.updatedAt.isAfter(existing.updatedAt)) {
            byId[remoteProd.id] = remoteProd;
          }
        }
      }

      // Subir a la nube los productos locales que aún no estén en Firestore
      final remoteIds = snap.docs.map((d) => d.id).toSet();
      for (final localProd in localList) {
        if (!remoteIds.contains(localProd.id)) {
          await col.doc(localProd.id).set(localProd.toJson());
        }
      }

      final merged = byId.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      await _saveLocalList(prefs, merged);
      return merged;
    } catch (_) {
      return localList;
    }
  }

  /// Guarda o actualiza un producto localmente y en Firestore (si hay sesión).
  Future<void> saveProduct(ProductItem product) async {
    if (!product.isValid) return;
    final prefs = await SharedPreferences.getInstance();
    final current = List<ProductItem>.from(
      ProductItem.listFromJson(prefs.getString(_localKey)),
    );

    final idx = current.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      current[idx] = product;
    } else {
      current.insert(0, product);
    }

    await _saveLocalList(prefs, current);

    final col = _userProductsCol;
    if (col != null) {
      try {
        await col.doc(product.id).set(product.toJson());
      } catch (_) {}
    }
  }

  /// Elimina un producto por su [id] tanto localmente como en Firestore.
  Future<void> deleteProduct(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = List<ProductItem>.from(
      ProductItem.listFromJson(prefs.getString(_localKey)),
    )..removeWhere((p) => p.id == id);

    await _saveLocalList(prefs, current);

    final col = _userProductsCol;
    if (col != null) {
      try {
        await col.doc(id).delete();
      } catch (_) {}
    }
  }

  Future<void> clearAllProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final current = List<ProductItem>.from(
      ProductItem.listFromJson(prefs.getString(_localKey)),
    );
    await prefs.remove(_localKey);

    final col = _userProductsCol;
    if (col != null) {
      try {
        for (final item in current) {
          await col.doc(item.id).delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _saveLocalList(
    SharedPreferences prefs,
    List<ProductItem> items,
  ) async {
    final encoded = jsonEncode(items.map((p) => p.toJson()).toList());
    await prefs.setString(_localKey, encoded);
  }
}

