import 'dart:io';

import 'package:calculadora_margenes_ve/models/rate.dart';
import 'package:calculadora_margenes_ve/screens/calculator_screen.dart';
import 'package:calculadora_margenes_ve/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> pumpAtPhoneSize(
    WidgetTester tester, {
    Size size = const Size(360, 640),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const CalculatorScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Las 4 tarjetas de tasa caben en una fila a 360px sin scroll horizontal',
    (tester) async {
      await pumpAtPhoneSize(tester);

      // Sin carrusel ni listas horizontales de tasas.
      expect(find.byType(ListView), findsNothing);

      final rects = <RateSource, Rect>{};
      for (final source in RateSource.values) {
        final finder = find.byKey(Key('rate_card_${source.name}'));
        expect(
          finder,
          findsOneWidget,
          reason: 'Tarjeta ${source.name} visible',
        );
        final rect = tester.getRect(finder);
        rects[source] = rect;

        // Toda la tarjeta queda dentro del ancho de 360 px.
        expect(rect.left, greaterThanOrEqualTo(0.0));
        expect(rect.right, lessThanOrEqualTo(360.0));
      }

      // Las 4 tarjetas comparten fila (mismo top) y van en orden con gap de 6 px.
      final ordered = RateSource.values.map((s) => rects[s]!).toList();
      final tops = ordered.map((r) => r.top).toSet();
      expect(tops.length, 1, reason: 'Las 4 tarjetas están en la misma fila');
      for (var i = 1; i < ordered.length; i++) {
        expect(
          ordered[i].left - ordered[i - 1].right,
          closeTo(6.0, 0.01),
          reason: 'Separación de 6 px entre tarjetas',
        );
      }

      // La tasa personalizada larga se lee completa (FittedBox, sin recorte).
      await tester.tap(find.text('Personalizada'));
      await tester.pumpAndSettle();
      final customField = find.ancestor(
        of: find.text('Tasa personalizada (Bs/\$)'),
        matching: find.byType(TextField),
      );
      expect(customField, findsOneWidget);
      await tester.enterText(customField, '918,77');
      await tester.pumpAndSettle();

      expect(find.text('918,77 Bs/\$'), findsOneWidget);
      final valueRect = tester.getRect(
        find.byKey(Key('rate_card_${RateSource.custom.name}')),
      );
      expect(valueRect.right, lessThanOrEqualTo(360.0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'La Calculadora sigue sin scroll vertical a 360px y el botón Calcular queda visible',
    (tester) async {
      await pumpAtPhoneSize(tester);

      expect(find.byType(SingleChildScrollView), findsNothing);

      final scrollables = tester.widgetList<Scrollable>(
        find.byType(Scrollable),
      );
      final verticalScrollables = scrollables.where(
        (s) =>
            s.axisDirection == AxisDirection.down ||
            s.axisDirection == AxisDirection.up,
      );
      expect(verticalScrollables, isEmpty);

      final submit = find.byKey(const Key('calc_submit_button'));
      expect(submit, findsOneWidget);
      final submitRect = tester.getRect(submit);
      expect(submitRect.top, greaterThanOrEqualTo(0.0));
      expect(submitRect.bottom, lessThanOrEqualTo(640.0));

      for (final source in RateSource.values) {
        final rect = tester.getRect(
          find.byKey(Key('rate_card_${source.name}')),
        );
        expect(rect.bottom, lessThanOrEqualTo(640.0));
      }

      expect(tester.takeException(), isNull);
    },
  );
}
