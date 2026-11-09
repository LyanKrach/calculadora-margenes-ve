import 'package:flutter/material.dart';

import '../services/rates_service.dart';

/// Ajustes: API key opcional de DolarVzla, información de la app y
/// enlaces a la política de privacidad.
///
/// SEGURIDAD: la key se guarda SOLO en SharedPreferences del teléfono.
/// Nunca se hardcodea en el código, nunca se sube a Git, nunca se envía
/// a ningún servidor propio: solo se usa como header `x-dolarvzla-key`
/// contra la API de DolarVzla si el usuario decide pegarla.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = RatesService();
  final _keyCtrl = TextEditingController();
  bool _showKey = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _service.getDolarVzlaKey().then((key) {
      _keyCtrl.text = key ?? '';
      setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _service.setDolarVzlaKey(_keyCtrl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key guardada en este teléfono')),
    );
  }

  Future<void> _delete() async {
    await _service.setDolarVzlaKey('');
    _keyCtrl.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key eliminada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'API key opcional — DolarVzla',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Opcional. Las 3 tasas principales (BCV, Binance, Euro) funcionan '
            'sin key. Si pegas tu key gratuita de DolarVzla, queda guardada '
            'solo en este teléfono (SharedPreferences) y se usa como respaldo '
            'adicional. Nunca se comparte ni se sube a ningún lado.',
          ),
          const SizedBox(height: 12),
          if (!_loaded)
            const LinearProgressIndicator()
          else
            TextField(
              controller: _keyCtrl,
              obscureText: !_showKey,
              decoration: InputDecoration(
                labelText: 'API key DolarVzla (x-dolarvzla-key)',
                hintText: 'Pégala aquí',
                suffixIcon: IconButton(
                  icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton(onPressed: _save, child: const Text('Guardar key')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _delete, child: const Text('Eliminar')),
          ]),
          const SizedBox(height: 24),
          const Text('Acerca de', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              title: Text('Calculadora de Márgenes VE'),
              subtitle: Text(
                'Versión 1.0.0+1\n'
                'Para vendedores en Venezuela: costo en USD, tasa del día, '
                'comisiones y margen → precio en bolívares sin perder dinero.\n\n'
                'Fuentes de tasas: DolarApi (BCV dólar y Euro BCV) y Binance P2P (USDT).\n'
                'La app no recolecta cuentas ni datos personales. '
                'Solo consulta tasas públicas. Ver PRIVACY_POLICY.md.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
