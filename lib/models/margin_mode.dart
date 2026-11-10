/// Modo de cálculo del margen de ganancia.
enum MarginMode {
  /// Recargo sobre el costo (Markup):
  ///
  /// Precio = (Costo en Bs × (1 + Margen) + Gasto fijo) ÷ (1 − Comisiones)
  ///
  /// La ganancia se calcula como porcentaje directo del costo de compra.
  /// Es la fórmula estándar de recargo comercial.
  /// Ejemplo: Costo $0,66 con 30 % de margen -> $0,66 × 1,30 = $0,858 (≈ $0,86).
  onCost,

  /// Margen sobre el precio final de venta (Margen comercial / financiero):
  ///
  /// Precio = (Costo en Bs + Gasto fijo) ÷ (1 − Comisiones − Margen)
  ///
  /// El margen representa qué porcentaje del precio final cobrado al cliente
  /// es ganancia líquida después de reponer mercancía y pagar comisiones.
  /// Ejemplo: Costo $0,66 con 30 % de margen -> $0,66 ÷ 0,70 = $0,9428.
  onSale;

  String get label => switch (this) {
        MarginMode.onCost => 'Sobre costo (Markup)',
        MarginMode.onSale => 'Sobre venta (Margen)',
      };

  String get shortLabel => switch (this) {
        MarginMode.onCost => 'Sobre costo',
        MarginMode.onSale => 'Sobre venta',
      };

  String get formulaSummary => switch (this) {
        MarginMode.onCost => 'Precio = Costo × (1 + Margen) ÷ (1 − Comisiones)',
        MarginMode.onSale => 'Precio = Costo ÷ (1 − Comisiones − Margen)',
      };

  static MarginMode fromName(String? name) {
    if (name == null) return MarginMode.onCost;
    for (final mode in MarginMode.values) {
      if (mode.name == name) return mode;
    }
    return MarginMode.onCost;
  }
}

