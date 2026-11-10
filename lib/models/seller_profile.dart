import '../utils/format.dart';

/// Modelo inmutable con los datos de cobro (Pago Móvil) del vendedor.
///
/// Se almacena exclusivamente en `SharedPreferences` del dispositivo (`"v": 1`).
class SellerProfile {
  const SellerProfile({
    required this.businessName,
    required this.idDocument,
    required this.phone,
    required this.bank,
    this.paymentNotes = '',
    this.version = currentVersion,
  });

  static const int currentVersion = 1;

  /// Los ~10 bancos más utilizados en Venezuela + opción "Otro" con texto libre.
  static const List<String> commonBanks = [
    'Banco de Venezuela (0102)',
    'Banesco (0134)',
    'Banco Mercantil (0105)',
    'BBVA Provincial (0108)',
    'Bancamiga (0172)',
    'BNC - Banco Nacional de Crédito (0191)',
    'Banplus (0174)',
    'Bancaribe (0114)',
    'Banco Exterior (0115)',
    'Banco Bicentenario (0175)',
    'Otro',
  ];

  final String businessName;
  final String idDocument;
  final String phone;
  final String bank;
  final String paymentNotes;
  final int version;

  /// Indica si el perfil tiene los datos mínimos para cobrar por Pago Móvil.
  bool get hasPagoMovil =>
      idDocument.trim().isNotEmpty &&
      phone.trim().isNotEmpty &&
      bank.trim().isNotEmpty;

  bool get isEmpty =>
      businessName.trim().isEmpty &&
      idDocument.trim().isEmpty &&
      phone.trim().isEmpty &&
      bank.trim().isEmpty &&
      paymentNotes.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'v': version,
        'businessName': businessName,
        'idDocument': idDocument,
        'phone': phone,
        'bank': bank,
        'paymentNotes': paymentNotes,
      };

  /// Deserializa con `try/catch` y fallback seguro a estado vacío.
  factory SellerProfile.fromJson(Map<String, dynamic> json) {
    try {
      final v = (json['v'] as num?)?.toInt() ?? 1;
      return SellerProfile(
        version: v,
        businessName: json['businessName']?.toString().trim() ?? '',
        idDocument: json['idDocument']?.toString().trim() ?? '',
        phone: json['phone']?.toString().trim() ?? '',
        bank: json['bank']?.toString().trim() ?? '',
        paymentNotes: json['paymentNotes']?.toString().trim() ?? '',
      );
    } catch (_) {
      return const SellerProfile.empty();
    }
  }

  const SellerProfile.empty()
      : businessName = '',
        idDocument = '',
        phone = '',
        bank = '',
        paymentNotes = '',
        version = currentVersion;

  /// Genera el mensaje de cobro para copiar o compartir por WhatsApp.
  String buildClientMessage({
    required double finalPriceBs,
    required String rateLabel,
    required double rateValue,
  }) {
    final buffer = StringBuffer();
    if (businessName.trim().isNotEmpty) {
      buffer.writeln('*${businessName.trim()}*');
    }
    buffer.writeln(
      'Precio: *${fmtBs(finalPriceBs)} Bs* (tasa $rateLabel ${fmtRate(rateValue)} Bs/\$).',
    );

    if (hasPagoMovil) {
      buffer.writeln();
      buffer.writeln('*Datos de Pago Móvil:*');
      buffer.writeln('• Banco: ${bank.trim()}');
      buffer.writeln('• Teléfono: ${phone.trim()}');
      buffer.writeln('• Cédula / RIF: ${idDocument.trim()}');
      buffer.writeln('• Monto: ${fmtBs(finalPriceBs)} Bs');
      if (paymentNotes.trim().isNotEmpty) {
        buffer.writeln();
        buffer.writeln('Nota: ${paymentNotes.trim()}');
      }
    }

    return buffer.toString().trim();
  }
}

