import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calculadora_margenes_ve/models/subscription_state.dart';
import 'package:calculadora_margenes_ve/screens/pro_plans_screen.dart';
import 'package:calculadora_margenes_ve/services/subscription_service.dart';

class _OfflineHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    throw const SocketException('Test offline');
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
}

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

void main() {
  setUpAll(() async {
    HttpOverrides.global = _OfflineHttpOverrides();
    await initializeDateFormatting('es_VE');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SubscriptionState & límites Gratis vs Pro', () {
    test('detecta suscripción Pro activa, días restantes y expiración automática', () {
      final now = DateTime.utc(2026, 11, 11, 12, 0);
      final active = SubscriptionState.fromJson(
        {
          'v': 1,
          'plan': 'annual',
          'status': 'active',
          'provider': 'pabilo_bdv',
          'startDate': '2026-11-11T00:00:00.000Z',
          'endDate': '2026-11-21T12:00:00.000Z',
        },
        now: now,
      );
      expect(active.isPro, isTrue);
      expect(active.status, SubscriptionStatus.active);
      expect(active.daysLeft, 10);

      final expired = SubscriptionState.fromJson(
        {
          'v': 1,
          'plan': 'monthly',
          'status': 'active',
          'provider': 'pabilo_bdv',
          'startDate': '2026-10-01T00:00:00.000Z',
          'endDate': '2026-11-01T00:00:00.000Z',
        },
        now: now,
      );
      expect(expired.isPro, isFalse);
      expect(expired.status, SubscriptionStatus.expired);
      expect(expired.daysLeft, 0);
    });

    test('aplica tope de 10 productos para Gratis y permite ilimitados en Pro', () {
      expect(
        SubscriptionState.canAddProduct(currentCount: 9, isPro: false),
        isTrue,
      );
      expect(
        SubscriptionState.canAddProduct(currentCount: 10, isPro: false),
        isFalse,
      );
      expect(
        SubscriptionState.canAddProduct(currentCount: 50, isPro: true),
        isTrue,
      );
    });
  });

  group('SubscriptionService cliente Pabilo HTTP', () {
    test('createCheckout congela monto y verifyPayment maneja abono parcial y activación', () async {
      var verifyCalls = 0;
      final mockClient = MockClient((req) async {
        if (req.url.toString().contains('getpropaymentconfig')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'bcvRate': {'usd': 901.62, 'source': 'dolarvzla'},
              'methods': {
                'pago_movil': {
                  'bank': 'BDV',
                  'cedulaRif': 'V-00000000',
                  'phone': '04120000000',
                  'holder': 'Comercio',
                  'autoVerify': true,
                },
                'usdt': {'network': 'Binance Pay', 'autoVerify': false},
              },
            }),
            200,
          );
        }

        expect(req.headers['Authorization'], 'Bearer fake-firebase-token');
        if (req.url.toString().contains('createprocheckout')) {
          return http.Response(
            jsonEncode({
              'ok': true,
              'order': {
                'id': 'pro_ord_123',
                'plan': 'monthly',
                'method': 'pago_movil',
                'currency': 'BS',
                'expectedAmountUsd': 1.99,
                'expectedAmountBs': 1794.22,
                'expectedTotal': 1794.22,
                'paidAmount': 0,
                'remainingAmount': 1794.22,
                'rateBs': 901.62,
                'rateSource': 'dolarvzla',
                'autoVerify': true,
                'status': 'awaiting_payment',
                'expiresAt': '2026-11-11T16:30:00.000Z',
              },
            }),
            200,
          );
        }

        if (req.url.toString().contains('verifypropayment')) {
          verifyCalls++;
          if (verifyCalls == 1) {
            return http.Response(
              jsonEncode({
                'ok': false,
                'code': 'PARTIAL_PAYMENT',
                'retryable': true,
                'orderId': 'pro_ord_123',
                'paidAmount': 1000.0,
                'remainingAmount': 794.22,
                'reportedAmount': 1000.0,
                'message': 'Recibimos Bs 1000.00. Faltan Bs 794.22.',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'code': 'ACTIVATED',
              'status': 'paid',
              'orderId': 'pro_ord_123',
              'message': '¡Pago verificado automáticamente!',
              'subscription': {
                'v': 1,
                'plan': 'monthly',
                'status': 'active',
                'provider': 'pabilo_bdv',
                'paymentRef': '99887766',
                'startDate': '2026-11-11T12:00:00.000Z',
                'endDate': '2099-12-11T12:00:00.000Z',
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final service = SubscriptionService.forTest(
        client: mockClient,
        tokenProvider: () async => 'fake-firebase-token',
      );

      final cfg = await service.fetchPaymentConfig();
      expect(cfg.pagoMovil.autoVerify, isTrue);
      expect(cfg.usdt.autoVerify, isFalse);

      final order = await service.createCheckout(
        plan: ProPlanId.monthly,
        method: ProPaymentMethod.pagoMovil,
      );
      expect(order.id, 'pro_ord_123');
      expect(order.expectedAmountBs, 1794.22);

      final partial = await service.verifyPayment(
        orderId: order.id,
        reference: '11223344',
      );
      expect(partial.isPartial, isTrue);
      expect(partial.remainingAmount, 794.22);
      expect(service.isPro, isFalse);

      final activated = await service.verifyPayment(
        orderId: order.id,
        reference: '99887766',
      );
      expect(activated.isActivated, isTrue);
      expect(service.isPro, isTrue);
      expect(service.currentState.provider, 'pabilo_bdv');
    });

    test('normalizeReference limpia dígitos y alfanuméricos correctamente', () {
      expect(
        SubscriptionService.normalizeReference('00-12 3456', allowLetters: false),
        '00123456',
      );
      expect(
        SubscriptionService.normalizeReference('bp-9a8b', allowLetters: true),
        'BP9A8B',
      );
    });

    test('identifica emails administradores propietarios y los 4 planes Pro', () {
      expect(isAdminOwnerEmail('layankrach@gmail.com'), isTrue);
      expect(isAdminOwnerEmail('SOPORTEREFILLSTORE@GMAIL.COM'), isTrue);
      expect(isAdminOwnerEmail('cliente@gmail.com'), isFalse);
      expect(ProPlanId.monthly.priceUsd, 1.99);
      expect(ProPlanId.quarterly.priceUsd, 4.99);
      expect(ProPlanId.semiannual.priceUsd, 7.99);
      expect(ProPlanId.annual.priceUsd, 14.99);
      expect(ProPlanId.annual.savePercent, 37);

      const defCfg = ProPaymentConfig();
      expect(defCfg.pagoMovil.cedulaRif, '31955598');
      expect(defCfg.pagoMovil.phone, '04220336568');
      expect(defCfg.pagoMovil.autoVerify, isTrue);
      expect(defCfg.usdt.network, 'Binance Pay (USDT)');
      expect(defCfg.usdt.binanceId, '916942742');
      expect(defCfg.usdt.autoVerify, isTrue);
    });

    test('SubscriptionService adminOverview, adminActivatePro y adminDeactivatePro funcionan vía HTTP', () async {
      final mockClient = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final action = body['action'];
        if (action == 'overview') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'stats': {'totalUsers': 1, 'activePro': 1, 'pendingManual': 0},
              'users': [
                {
                  'uid': 'u1',
                  'email': 'layankrach@gmail.com',
                  'displayName': 'Layan',
                  'isOwner': true,
                  'isPro': true,
                  'status': 'active',
                  'plan': 'annual',
                  'daysLeft': 3650,
                }
              ],
            }),
            200,
          );
        }
        if (action == 'activate') {
          return http.Response(
            jsonEncode({
              'ok': true,
              'message': 'Pro activado para amigo@gmail.com',
              'user': {
                'uid': 'u2',
                'email': body['email'],
                'displayName': 'Amigo',
                'isOwner': false,
                'isPro': true,
                'status': 'active',
                'plan': body['plan'],
                'daysLeft': body['days'] ?? 30,
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'message': 'Desactivado',
            'user': {
              'uid': 'u2',
              'email': body['email'],
              'displayName': 'Amigo',
              'isOwner': false,
              'isPro': false,
              'status': 'canceled',
              'daysLeft': 0,
            },
          }),
          200,
        );
      });

      final service = SubscriptionService.forTest(
        client: mockClient,
        tokenProvider: () async => 'admin-jwt',
      );
      final ov = await service.fetchAdminOverview();
      expect(ov.totalUsers, 1);
      expect(ov.users.first.isOwner, isTrue);

      final act = await service.adminActivatePro(
        email: 'amigo@gmail.com',
        plan: ProPlanId.quarterly,
        days: 30,
        note: 'Regalo',
      );
      expect(act.user.isPro, isTrue);
      expect(act.user.daysLeft, 30);

      final deact = await service.adminDeactivatePro(email: 'amigo@gmail.com');
      expect(deact.user.isPro, isFalse);
      expect(deact.user.status, 'canceled');
    });
  });

  group('ProPlansScreen widget', () {
    testWidgets('renderiza los 4 Planes Pro, selector Pabilo y términos',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProPlansScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Planes Pro'), findsOneWidget);
      expect(find.text('Pro Anual'), findsOneWidget);
      expect(find.text('Pro 6 Meses'), findsOneWidget);
      expect(find.text('Pro Trimestral'), findsOneWidget);
      expect(find.text('Pro Mensual'), findsOneWidget);
      expect(find.text('RECOMENDADO · Ahorra 37%'), findsOneWidget);
      expect(find.text('\$14,99'), findsOneWidget);
      expect(find.text('\$7,99'), findsOneWidget);
      expect(find.text('\$4,99'), findsOneWidget);
      expect(find.text('\$1,99'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Pago Móvil (BDV)'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Pago Móvil (BDV)'), findsOneWidget);
      expect(find.text('Binance Pay (USDT)'), findsOneWidget);
      expect(find.text('31955598'), findsOneWidget);
      expect(find.text('04220336568'), findsOneWidget);
      expect(find.text('Verificar pago y activar Pro'), findsOneWidget);

      await tester.tap(find.text('Binance Pay (USDT)'));
      await tester.pump();
      expect(find.text('916942742'), findsOneWidget);
      expect(find.text('Pabilo automático'), findsOneWidget);
      expect(find.text('Verificar pago y activar Pro'), findsOneWidget);
    });
  });
}
