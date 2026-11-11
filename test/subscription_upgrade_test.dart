import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    SubscriptionService.instance.stateNotifier.value =
        const SubscriptionState.free();
  });

  tearDown(() {
    SubscriptionService.instance.stateNotifier.value =
        const SubscriptionState.free();
  });

  group('PlanUpgradeInfo & tierRank', () {
    test('bloquea plan actual/inferior y calcula acumulación de días en planes superiores', () {
      expect(ProPlanId.monthly.tierRank, 1);
      expect(ProPlanId.quarterly.tierRank, 2);
      expect(ProPlanId.semiannual.tierRank, 3);
      expect(ProPlanId.annual.tierRank, 4);

      final now = DateTime.utc(2026, 11, 11, 16, 0);
      final activeMonthly = SubscriptionState.fromJson(
        {
          'v': 1,
          'plan': 'monthly',
          'status': 'active',
          'startDate': now.toIso8601String(),
          'endDate': now.add(const Duration(days: 30)).toIso8601String(),
        },
        now: now,
      );

      final same = activeMonthly.upgradeInfoFor(ProPlanId.monthly, now: now);
      expect(same.isCurrentPlan, isTrue);
      expect(same.isLowerPlan, isFalse);
      expect(same.isUpgrade, isFalse);
      expect(same.canPurchase, isFalse);
      expect(same.remainingDays, 30);

      final upQ = activeMonthly.upgradeInfoFor(ProPlanId.quarterly, now: now);
      expect(upQ.isUpgrade, isTrue);
      expect(upQ.canPurchase, isTrue);
      expect(upQ.remainingDays, 30);
      expect(upQ.addedDays, 90);
      expect(upQ.totalDaysAfter, 120);
      expect(upQ.projectedEndDate, now.add(const Duration(days: 120)));

      expect(
        activeMonthly.firstAvailableUpgradePlan(now: now),
        ProPlanId.quarterly,
      );

      final activeSemi = SubscriptionState.fromJson(
        {
          'v': 1,
          'plan': 'semiannual',
          'status': 'active',
          'startDate': now.toIso8601String(),
          'endDate': now.add(const Duration(days: 180)).toIso8601String(),
        },
        now: now,
      );
      final lower = activeSemi.upgradeInfoFor(ProPlanId.quarterly, now: now);
      expect(lower.isLowerPlan, isTrue);
      expect(lower.canPurchase, isFalse);

      final activeAnnual = SubscriptionState.fromJson(
        {
          'v': 1,
          'plan': 'annual',
          'status': 'active',
          'startDate': now.toIso8601String(),
          'endDate': now.add(const Duration(days: 365)).toIso8601String(),
        },
        now: now,
      );
      expect(activeAnnual.firstAvailableUpgradePlan(now: now), isNull);
    });
  });

  group('ProPlansScreen bloqueo de plan actual y texto Verificando pago', () {
    test('pro_plans_screen.dart no contiene "Verificando con Pabilo"', () {
      final src = File('lib/screens/pro_plans_screen.dart').readAsStringSync();
      expect(src.contains('Verificando con Pabilo'), isFalse);
      expect(src.contains('Verificando pago…'), isTrue);
    });

    testWidgets(
      'muestra plan mensual bloqueado, ajuste de acumulación en superiores y aviso de máximo en anual',
      (tester) async {
        final now = DateTime.now().toUtc();
        SubscriptionService.instance.stateNotifier.value =
            SubscriptionState.fromJson(
          {
            'v': 1,
            'plan': 'monthly',
            'status': 'active',
            'provider': 'pabilo_bdv',
            'startDate': now.toIso8601String(),
            'endDate': now.add(const Duration(days: 30)).toIso8601String(),
          },
          now: now,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: ProPlansScreen(initialPlan: ProPlanId.monthly),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Plan actual'), findsOneWidget);
        expect(find.textContaining('Plan actual activo'), findsWidgets);
        expect(
          find.textContaining('Ajuste de acumulación de días'),
          findsWidgets,
        );
        // Normalizó _selectedPlan desde monthly (bloqueado) hacia quarterly
        await tester.scrollUntilVisible(
          find.text('Mejora a Pro Trimestral'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Mejora a Pro Trimestral'), findsOneWidget);
        expect(
          find.textContaining('Ajuste de acumulación: incluye +30 días actuales = 120 días totales'),
          findsOneWidget,
        );

        // Cambiamos a plan anual activo (máximo) -> bloquea compras
        SubscriptionService.instance.stateNotifier.value =
            SubscriptionState.fromJson(
          {
            'v': 1,
            'plan': 'annual',
            'status': 'active',
            'provider': 'pabilo_bdv',
            'startDate': now.toIso8601String(),
            'endDate': now.add(const Duration(days: 365)).toIso8601String(),
          },
          now: now,
        );
        await tester.pumpAndSettle();

        if (find.textContaining('Ya cuentas con el plan máximo').evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            find.textContaining('Ya cuentas con el plan máximo'),
            -250,
            scrollable: find.byType(Scrollable).first,
          );
        }
        expect(
          find.textContaining('Ya cuentas con el plan máximo'),
          findsOneWidget,
        );
        expect(find.text('Verificar pago y activar Pro'), findsNothing);
      },
    );
  });
}
