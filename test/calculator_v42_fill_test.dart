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

  Future<void> pumpAtSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const CalculatorScreen()),
    );
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(360, 800), Size(360, 880)]) {
    testWidgets(
      'v4.2 llena la pantalla ${size.height.toInt()} px sin scroll y con etiquetas completas',
      (tester) async {
        await pumpAtSize(tester, size);

        // Sin errores de layout (overflow) en pantallas altas.
        expect(tester.takeException(), isNull);

        // Sin scroll vertical ni horizontal: ni el body ni las tasas.
        expect(find.byType(SingleChildScrollView), findsNothing);
        expect(find.byType(ListView), findsNothing);
        expect(find.byType(Scrollbar), findsNothing);
        final scrollables = tester.widgetList<Scrollable>(
          find.byType(Scrollable),
        );
        final verticalScrollables = scrollables.where(
          (s) =>
              s.axisDirection == AxisDirection.down ||
              s.axisDirection == AxisDirection.up,
        );
        expect(verticalScrollables, isEmpty);

        // Las 4 tarjetas de tasa siguen en una fila, dentro de 360 px y con
        // altura de teléfono alto (72-80 px).
        final rects = <RateSource, Rect>{};
        for (final source in RateSource.values) {
          final finder = find.byKey(Key('rate_card_${source.name}'));
          expect(finder, findsOneWidget);
          final rect = tester.getRect(finder);
          rects[source] = rect;
          expect(rect.left, greaterThanOrEqualTo(0.0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.height, inInclusiveRange(72.0, 80.0));
        }
        final ordered = RateSource.values.map((s) => rects[s]!).toList();
        expect(
          ordered.map((r) => r.top).toSet().length,
          1,
          reason: 'Las 4 tasas comparten fila',
        );
        for (var i = 1; i < ordered.length; i++) {
          expect(ordered[i].left - ordered[i - 1].right, closeTo(6.0, 0.01));
        }

        // "Binance USDT" y "Personalizada" se leen completas: el texto vive
        // dentro de un FittedBox y su caja queda dentro de la tarjeta.
        for (final label in ['Binance USDT', 'Personalizada']) {
          final text = find.text(label);
          expect(text, findsOneWidget);
          expect(
            find.ancestor(of: text, matching: find.byType(FittedBox)),
            findsWidgets,
          );
          final textRect = tester.getRect(text);
          final cardRect = label == 'Binance USDT'
              ? rects[RateSource.binanceUsdt]!
              : rects[RateSource.custom]!;
          expect(textRect.left, greaterThanOrEqualTo(cardRect.left));
          expect(textRect.right, lessThanOrEqualTo(cardRect.right));
          expect(textRect.width, greaterThan(45.0));
        }

        // Inputs altos y secciones que crecen para llenar la pantalla.
        final costField = find.ancestor(
          of: find.text('Costo del producto (\$)'),
          matching: find.byType(TextField),
        );
        expect(tester.getSize(costField).height, greaterThanOrEqualTo(54.0));

        // El botón "Calcular precio" queda visible y pegado al contenido:
        // el hueco sobre él es pequeño (no un Spacer gigante).
        final submit = find.byKey(const Key('calc_submit_button'));
        expect(submit, findsOneWidget);
        final submitRect = tester.getRect(submit);
        expect(submitRect.bottom, lessThanOrEqualTo(size.height));
        expect(submitRect.bottom, greaterThanOrEqualTo(size.height - 20.0));

        final commissions = tester.getRect(
          find.byKey(const Key('commissions_section')),
        );
        final gap = submitRect.top - commissions.bottom;
        expect(gap, greaterThanOrEqualTo(0.0));
        expect(gap, lessThanOrEqualTo(24.0));

        // Las tres secciones ocupan el alto disponible.
        final rateSection = tester.getRect(
          find.byKey(const Key('rate_section')),
        );
        final marginSection = tester.getRect(
          find.byKey(const Key('margin_section')),
        );
        expect(rateSection.top, greaterThanOrEqualTo(0.0));
        expect(marginSection.top, greaterThan(rateSection.top));
        expect(commissions.top, greaterThan(marginSection.top));

        expect(tester.takeException(), isNull);
      },
    );
  }
}
