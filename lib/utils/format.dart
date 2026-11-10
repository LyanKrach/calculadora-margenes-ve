import 'package:intl/intl.dart';

/// Formato Bs con separador de miles y 2 decimales (es-VE).
String fmtBs(double value) =>
    NumberFormat('#,##0.00', 'es_VE').format(value);

/// Formato USD con 2 decimales.
String fmtUsd(double value) =>
    NumberFormat('#,##0.00', 'es_VE').format(value);

/// Formato de tasa con 2 decimales (ej. 899,27).
String fmtRate(double value) =>
    NumberFormat('#,##0.00', 'es_VE').format(value);

/// Formatea una fecha de vigencia ISO (ej. "2026-11-10") indicando si es de hoy o de mañana.
String formatEffectiveDate(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '';
  try {
    final clean = isoDate.split('T')[0].trim();
    final parts = clean.split('-');
    if (parts.length != 3) return 'Vigente: $isoDate';
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    final target = DateTime(year, month, day);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    const meses = [
      '', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];
    final mesStr = (month >= 1 && month <= 12) ? meses[month] : '$month';
    final fechaTxt = '$day $mesStr';

    if (target == today) {
      return 'Vigente: Hoy ($fechaTxt)';
    } else if (target == tomorrow) {
      return 'Vigente: Mañana ($fechaTxt)';
    } else {
      return 'Vigente: $fechaTxt';
    }
  } catch (_) {
    return 'Vigente: $isoDate';
  }
}
