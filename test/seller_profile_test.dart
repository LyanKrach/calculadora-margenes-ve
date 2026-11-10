import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calculadora_margenes_ve/models/seller_profile.dart';
import 'package:calculadora_margenes_ve/screens/seller_profile_screen.dart';
import 'package:calculadora_margenes_ve/services/seller_profile_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SellerProfile serialización y plantilla de mensaje', () {
    test('round-trip toJson / fromJson incluye "v": 1 y conserva datos', () {
      const profile = SellerProfile(
        businessName: 'Inversiones Gamer C.A.',
        idDocument: 'J-12345678-0',
        phone: '0414-1234567',
        bank: 'Banco de Venezuela (0102)',
        paymentNotes: 'Enviar captura de transferencia.',
      );

      final json = profile.toJson();
      expect(json['v'], 1);

      final restored = SellerProfile.fromJson(json);
      expect(restored.hasPagoMovil, isTrue);
      expect(restored.businessName, 'Inversiones Gamer C.A.');
      expect(restored.idDocument, 'J-12345678-0');
      expect(restored.phone, '0414-1234567');
      expect(restored.bank, 'Banco de Venezuela (0102)');
      expect(restored.paymentNotes, 'Enviar captura de transferencia.');
    });

    test('buildClientMessage genera bloque Pago Móvil si está configurado y soporta Uri.encodeComponent', () {
      const profile = SellerProfile(
        businessName: 'Tienda 100% Gamer',
        idDocument: 'V-12345678',
        phone: '0412-9876543',
        bank: 'Banesco (0134)',
        paymentNotes: 'Reportar el 100% del pago.',
      );

      final msg = profile.buildClientMessage(
        finalPriceBs: 11510.0,
        rateLabel: 'BCV Dólar',
        rateValue: 897.5383,
      );

      expect(msg, contains('*Tienda 100% Gamer*'));
      expect(msg, contains('*Datos de Pago Móvil:*'));
      expect(msg, contains('• Banco: Banesco (0134)'));
      expect(msg, contains('• Teléfono: 0412-9876543'));
      expect(msg, contains('• Cédula / RIF: V-12345678'));
      expect(msg, contains('Nota: Reportar el 100% del pago.'));

      // Verificar codificación segura para wa.me con saltos de línea y %
      final waUri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
      expect(waUri.queryParameters['text'], msg);
    });

    test('SellerProfileService guarda, recupera y limpia en SharedPreferences', () async {
      final service = SellerProfileService();
      expect((await service.getProfile()).isEmpty, isTrue);

      const profile = SellerProfile(
        businessName: 'Mi Tienda',
        idDocument: 'V-11111111',
        phone: '0414-0000000',
        bank: 'Bancamiga (0172)',
      );
      await service.saveProfile(profile);

      final loaded = await service.getProfile();
      expect(loaded.hasPagoMovil, isTrue);
      expect(loaded.bank, 'Bancamiga (0172)');

      await service.clearProfile();
      expect((await service.getProfile()).isEmpty, isTrue);
    });
  });

  group('SellerProfileScreen UI y opción "Otro" en bancos', () {
    testWidgets('permite elegir "Otro" banco con texto libre y guardar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SellerProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Abrir dropdown de bancos y elegir "Otro"
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Otro').last,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otro').last);
      await tester.pumpAndSettle();

      // Debe aparecer el campo de texto libre para el banco
      final otherBankField = find.ancestor(
        of: find.text('Nombre y código del banco'),
        matching: find.byType(TextField),
      );
      expect(otherBankField, findsOneWidget);

      await tester.enterText(otherBankField, 'Mi Banco (0169)');
      await tester.enterText(
        find.ancestor(
          of: find.text('Teléfono afiliado a Pago Móvil'),
          matching: find.byType(TextField),
        ),
        '0424-5556677',
      );
      await tester.enterText(
        find.ancestor(
          of: find.text('Cédula o RIF'),
          matching: find.byType(TextField),
        ),
        'V-20304050',
      );
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      final saveBtn = find.text('Guardar perfil');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      final saved = await SellerProfileService().getProfile();
      expect(saved.bank, 'Mi Banco (0169)');
      expect(saved.phone, '0424-5556677');
      expect(saved.idDocument, 'V-20304050');
    });
  });
}
