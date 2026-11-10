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
