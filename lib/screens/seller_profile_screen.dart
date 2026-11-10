import 'package:flutter/material.dart';

import '../models/seller_profile.dart';
import '../services/seller_profile_service.dart';

/// Pantalla de configuración del perfil de vendedor (Pago Móvil) para
/// incluir automáticamente los datos de cobro en mensajes de WhatsApp y portapapeles.
class SellerProfileScreen extends StatefulWidget {
  const SellerProfileScreen({super.key});

  @override
  State<SellerProfileScreen> createState() => _SellerProfileScreenState();
}

class _SellerProfileScreenState extends State<SellerProfileScreen> {
  final _service = SellerProfileService();

  final _businessCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otherBankCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _selectedBank = SellerProfile.commonBanks.first;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    for (final c in [
      _businessCtrl,
      _idCtrl,
      _phoneCtrl,
      _otherBankCtrl,
      _notesCtrl,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  Future<void> _load() async {
    final profile = await _service.getProfile();
    if (!mounted) return;
    setState(() {
      _businessCtrl.text = profile.businessName;
      _idCtrl.text = profile.idDocument;
      _phoneCtrl.text = profile.phone;
      _notesCtrl.text = profile.paymentNotes;

      if (profile.bank.isEmpty) {
        _selectedBank = SellerProfile.commonBanks.first;
      } else if (SellerProfile.commonBanks.contains(profile.bank) &&
          profile.bank != 'Otro') {
        _selectedBank = profile.bank;
      } else {
        _selectedBank = 'Otro';
        _otherBankCtrl.text = profile.bank;
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _businessCtrl,
      _idCtrl,
      _phoneCtrl,
      _otherBankCtrl,
      _notesCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  SellerProfile get _currentDraft {
    final effectiveBank =
        _selectedBank == 'Otro' ? _otherBankCtrl.text.trim() : _selectedBank;
    return SellerProfile(
      businessName: _businessCtrl.text.trim(),
      idDocument: _idCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      bank: effectiveBank,
      paymentNotes: _notesCtrl.text.trim(),
    );
  }

  Future<void> _save() async {
    final draft = _currentDraft;
    await _service.saveProfile(draft);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil de vendedor guardado en este dispositivo')),
    );
    Navigator.of(context).maybePop(draft);
  }

  Future<void> _clear() async {
    await _service.clearProfile();
    if (!mounted) return;
    setState(() {
      _businessCtrl.clear();
      _idCtrl.clear();
      _phoneCtrl.clear();
      _otherBankCtrl.clear();
      _notesCtrl.clear();
      _selectedBank = SellerProfile.commonBanks.first;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Datos de perfil eliminados')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _currentDraft;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil de Vendedor (Pago Móvil)'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('100 % Local y Privado'),
                    subtitle: Text(
                      'Tu nombre comercial, cédula/RIF y teléfono se guardan únicamente '
                      'en este teléfono para armar tu mensaje de cobro. Nunca se envían a internet.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _businessCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre comercial o tienda (opcional)',
                    hintText: 'Ej. Inversiones Gamer VE',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedBank,
                  decoration: const InputDecoration(
                    labelText: 'Banco receptor',
                  ),
                  items: SellerProfile.commonBanks
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedBank = val);
                    }
                  },
                ),
                if (_selectedBank == 'Otro') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _otherBankCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre y código del banco',
                      hintText: 'Ej. Mi Banco (0169)',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono afiliado a Pago Móvil',
                    hintText: 'Ej. 0414-1234567',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _idCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cédula o RIF',
                    hintText: 'Ej. V-12345678 o J-12345678-0',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nota adicional (opcional)',
                    hintText: 'Ej. Enviar captura de pago al transferir',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Guardar perfil'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Borrar'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Vista previa del mensaje para el cliente',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      draft.buildClientMessage(
                        finalPriceBs: 11510.0,
                        rateLabel: 'BCV Dólar',
                        rateValue: 897.5383,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

