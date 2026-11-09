import 'package:intl/intl.dart';

/// Formato Bs con separador de miles y 2 decimales (es-VE).
String fmtBs(double value) =>
    NumberFormat('#,##0.00', 'es_VE').format(value);

/// Formato USD con 2 decimales.
String fmtUsd(double value) =>
    NumberFormat('#,##0.00', 'es_VE').format(value);

/// Formato de tasa con 4 decimales (ej. 897,5383).
String fmtRate(double value) =>
    NumberFormat('#,##0.0000', 'es_VE').format(value);
