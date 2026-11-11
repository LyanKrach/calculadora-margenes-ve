import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription_state.dart';
import 'auth_service.dart';

/// Excepción lanzada cuando un usuario en plan Gratis alcanza el tope de 10 productos.
class FreeLimitReachedException implements Exception {
  final String message;
  const FreeLimitReachedException(this.message);

  @override
  String toString() => message;
}

class ProPaymentException implements Exception {
  final String code;
  final String message;
  final bool fallbackManual;

  const ProPaymentException({
    required this.code,
    required this.message,
    this.fallbackManual = false,
  });

  @override
  String toString() => message;
}

/// Servicio central de suscripciones Pro, verificación automática con Pabilo
/// y aplicación de límites del plan Gratis vs Pro.
class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._();

  factory SubscriptionService() => instance;

  SubscriptionService._({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  })  : _client = client ?? http.Client(),
        _tokenProvider = tokenProvider;

  @visibleForTesting
  SubscriptionService.forTest({
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  })  : _client = client ?? http.Client(),
        _tokenProvider = tokenProvider;

  static const configEndpointUrl =
      'https://getpropaymentconfig-yqgkyclg5a-uc.a.run.app';
  static const checkoutEndpointUrl =
      'https://createprocheckout-yqgkyclg5a-uc.a.run.app';
  static const verifyEndpointUrl =
      'https://verifypropayment-yqgkyclg5a-uc.a.run.app';

  static const _subCachePrefix = 'pro_subscription_cache_v1_';

  final http.Client _client;
  final Future<String?> Function()? _tokenProvider;

  final ValueNotifier<SubscriptionState> stateNotifier =
      ValueNotifier<SubscriptionState>(const SubscriptionState.free());
  final ValueNotifier<Map<String, dynamic>?> pendingNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);

  bool _started = false;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _curSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _pendSub;

  SubscriptionState get currentState {
    final evaluated = stateNotifier.value.evaluateAt(DateTime.now());
    if (evaluated.status != stateNotifier.value.status ||
        evaluated.daysLeft != stateNotifier.value.daysLeft) {
      stateNotifier.value = evaluated;
    }
    return evaluated;
  }

  bool get isPro => currentState.isPro;

  void ensureStarted() {
    if (_started) return;
    _started = true;
    if (!AuthService.isFirebaseInitialized) return;
    _attachForUser(FirebaseAuth.instance.currentUser);
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_attachForUser);
  }

  void _attachForUser(User? user) {
    _curSub?.cancel();
    _pendSub?.cancel();
    _curSub = null;
    _pendSub = null;

    if (user == null || user.isAnonymous) {
      stateNotifier.value = const SubscriptionState.free();
      pendingNotifier.value = null;
      return;
    }

    _loadCachedSubscription(user.uid);
    final subCol = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('subscription');

    _curSub = subCol.doc('current').snapshots().listen(
      (snap) {
        final data = snap.exists ? snap.data() : null;
        final next = SubscriptionState.fromJson(data);
        stateNotifier.value = next;
        _saveCachedSubscription(user.uid, data);
      },
      onError: (_) {},
    );

    _pendSub = subCol.doc('pending').snapshots().listen(
      (snap) {
        pendingNotifier.value = snap.exists ? snap.data() : null;
      },
      onError: (_) {},
    );
  }

  Future<void> _loadCachedSubscription(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_subCachePrefix$uid');
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      stateNotifier.value = SubscriptionState.fromJson(map);
    } catch (_) {}
  }

  Future<void> _saveCachedSubscription(
    String uid,
    Map<String, dynamic>? data,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_subCachePrefix$uid';
      if (data == null || data.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(data));
      }
    } catch (_) {}
  }

  Future<SubscriptionState> refreshSubscription() async {
    if (!AuthService.isFirebaseInitialized) return currentState;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      stateNotifier.value = const SubscriptionState.free();
      pendingNotifier.value = null;
      return const SubscriptionState.free();
    }
    try {
      final subCol = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('subscription');
      final results = await Future.wait([
        subCol.doc('current').get().timeout(const Duration(seconds: 8)),
        subCol.doc('pending').get().timeout(const Duration(seconds: 8)),
      ]);
      final curData = results[0].exists ? results[0].data() : null;
      final pendData = results[1].exists ? results[1].data() : null;
      final next = SubscriptionState.fromJson(curData);
      stateNotifier.value = next;
      pendingNotifier.value = pendData;
      await _saveCachedSubscription(user.uid, curData);
      return next;
    } catch (_) {
      return currentState;
    }
  }

  Future<String> _requireIdToken() async {
    if (_tokenProvider != null) {
      final custom = await _tokenProvider();
      if (custom != null && custom.isNotEmpty) return custom;
      throw const ProPaymentException(
        code: 'UNAUTHORIZED',
        message: 'Debes iniciar sesión con tu cuenta para continuar.',
      );
    }
    if (!AuthService.isFirebaseInitialized) {
      throw const ProPaymentException(
        code: 'FIREBASE_UNAVAILABLE',
        message: 'Firebase no está inicializado en este entorno.',
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const ProPaymentException(
        code: 'UNAUTHORIZED',
        message:
            'Inicia sesión con tu correo o Google para asociar el plan Pro a tu cuenta.',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const ProPaymentException(
        code: 'INVALID_TOKEN',
        message: 'Tu sesión expiró. Vuelve a iniciar sesión.',
      );
    }
    return token;
  }

  /// Obtiene planes, tasa BCV oficial y datos públicos de Pago Móvil / USDT desde el backend.
  Future<ProPaymentConfig> fetchPaymentConfig() async {
    final res = await _client
        .get(Uri.parse(configEndpointUrl))
        .timeout(const Duration(seconds: 15));
    final body = _decodeJsonMap(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300 && body['ok'] == true) {
      return ProPaymentConfig.fromJson(body);
    }
    throw ProPaymentException(
      code: body['code']?.toString() ?? 'CONFIG_ERROR',
      message: body['message']?.toString() ??
          'No pudimos cargar los métodos de pago en este momento.',
    );
  }

  /// Crea una orden con tasa BCV y monto exacto congelados por 30 minutos.
  Future<ProCheckoutOrder> createCheckout({
    required ProPlanId plan,
    required ProPaymentMethod method,
  }) async {
    final token = await _requireIdToken();
    final res = await _client
        .post(
          Uri.parse(checkoutEndpointUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'plan': plan.id,
            'method': method.id,
          }),
        )
        .timeout(const Duration(seconds: 25));

    final body = _decodeJsonMap(res.body);
    if (res.statusCode >= 200 &&
        res.statusCode < 300 &&
        body['ok'] == true &&
        body['order'] is Map<String, dynamic>) {
      return ProCheckoutOrder.fromJson(body['order'] as Map<String, dynamic>);
    }

    throw ProPaymentException(
      code: body['code']?.toString() ?? 'CHECKOUT_ERROR',
      message: body['message']?.toString() ??
          'No pudimos iniciar la orden de pago.',
    );
  }

  /// Consulta Pabilo Betaserio (hasta 55s de espera por picos BDV) y activa Pro automáticamente.
  Future<PabiloVerifyResult> verifyPayment({
    required String orderId,
    required String reference,
  }) async {
    final token = await _requireIdToken();
    final res = await _client
        .post(
          Uri.parse(verifyEndpointUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'orderId': orderId,
            'reference': reference.trim(),
          }),
        )
        .timeout(const Duration(seconds: 55));

    final body = _decodeJsonMap(res.body);
    if (body.isEmpty) {
      throw const ProPaymentException(
        code: 'INVALID_RESPONSE',
        message: 'Respuesta inválida del servidor al verificar el pago.',
      );
    }

    final result = PabiloVerifyResult.fromJson(body, fallbackOrderId: orderId);
    if (result.isActivated && result.subscription != null) {
      stateNotifier.value = result.subscription!;
      pendingNotifier.value = null;
      final uid = AuthService.isFirebaseInitialized
          ? FirebaseAuth.instance.currentUser?.uid
          : null;
      if (uid != null && uid.isNotEmpty) {
        await _saveCachedSubscription(uid, result.subscription!.toJson());
      }
    }
    return result;
  }

  /// Respaldo manual cuando el método elegido aún no tenga Pabilo automático activo.
  Future<void> submitManualFallback({
    required ProPlanId plan,
    required ProPaymentMethod method,
    required String reference,
    required double amountUsd,
    double? amountBs,
    double? rateBs,
  }) async {
    if (!AuthService.isFirebaseInitialized) {
      throw StateError('Firebase no está inicializado.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const ProPaymentException(
        code: 'UNAUTHORIZED',
        message: 'Inicia sesión con tu correo o Google para enviar la referencia.',
      );
    }
    final cleanRef = reference.trim();
    if (cleanRef.length < 4 || cleanRef.length > 80) {
      throw const ProPaymentException(
        code: 'INVALID_REFERENCE',
        message: 'Ingresa una referencia válida entre 4 y 80 caracteres.',
      );
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final docData = <String, dynamic>{
      'v': 1,
      'plan': plan.id,
      'method': method.id,
      'reference': cleanRef,
      'amountUsd': amountUsd,
      if (amountBs != null && amountBs > 0) 'amountBs': amountBs,
      if (rateBs != null && rateBs > 0) 'rateBs': rateBs,
      'status': 'pending',
      'provider': 'manual',
      'requestedAt': nowIso,
    };
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('subscription')
        .doc('pending')
        .set(docData)
        .timeout(const Duration(seconds: 10));
    pendingNotifier.value = docData;
  }

  /// Limpia una referencia normalizada igual que el backend.
  static String normalizeReference(String raw, {required bool allowLetters}) {
    final trimmed = raw.trim();
    return allowLetters
        ? trimmed.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '')
        : trimmed.replaceAll(RegExp(r'\D'), '');
  }

  static Map<String, dynamic> _decodeJsonMap(String raw) {
    if (raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  void dispose() {
    _curSub?.cancel();
    _pendSub?.cancel();
    _authSub?.cancel();
  }
}

