import 'package:flutter/material.dart';

import '../models/seller_profile.dart';
import '../models/subscription_state.dart';
import '../services/auth_service.dart';
import '../services/seller_profile_service.dart';
import '../services/subscription_service.dart';
import '../services/theme_service.dart';
import 'auth_screen.dart';
import 'pro_plans_screen.dart';
import 'seller_profile_screen.dart';

/// Ajustes: Sincronización en la nube, Apariencia (Tema claro/oscuro),
/// Perfil de cobro (Pago Móvil) e información de la aplicación.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _profileService = SellerProfileService();
  final _authService = AuthService();
  final _subService = SubscriptionService.instance;
  SellerProfile _profile = const SellerProfile.empty();
  SubscriptionState _subState = const SubscriptionState.free();

  @override
  void initState() {
    super.initState();
    _subService.ensureStarted();
    _subState = _subService.currentState;
    _subService.stateNotifier.addListener(_onSubChanged);
    _loadData();
  }

  @override
  void dispose() {
    _subService.stateNotifier.removeListener(_onSubChanged);
    super.dispose();
  }

  void _onSubChanged() {
    if (!mounted) return;
    setState(() => _subState = _subService.currentState);
  }

  Future<void> _loadData() async {
    final profile = await _profileService.getProfile();
    await _subService.refreshSubscription();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _subState = _subService.currentState;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Suscripción y Planes Pro',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(
                _subState.isPro ? Icons.workspace_premium : Icons.diamond_outlined,
                color: _subState.isPro
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(
                _subState.isPro
                    ? 'Plan Pro Activo (${ProPlanId.tryParse(_subState.plan)?.shortName ?? 'Pro'})'
                    : 'Plan Gratis · Pasar a Pro',
              ),
              subtitle: Text(
                _subState.isPro
                    ? 'Vence en ${_subState.daysLeft} días · Productos y reportes ilimitados'
                    : 'Desde \$1,99/mes · \$4,99/3m · \$7,99/6m · \$14,99/año (-37%)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProPlansScreen()),
                );
                await _loadData();
              },
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Cuenta y Sincronización (Firebase)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(
                _authService.isSignedIn
                    ? Icons.cloud_done
                    : Icons.person_outline,
              ),
              title: Text(
                _authService.isSignedIn
                    ? (_authService.currentUser?.isAnonymous == true
                        ? 'Sesión de Invitado Activa'
                        : (_authService.currentUser?.email ??
                            'Cuenta Sincronizada'))
                    : 'Iniciar sesión o crear cuenta',
              ),
              subtitle: Text(
                _authService.isSignedIn
                    ? 'Tus productos e historial están sincronizados en Cloud Firestore.'
                    : 'Respalda tus productos e historial en la nube o úsala en modo local.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AuthScreen(),
                  ),
                );
                await _loadData();
              },
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Apariencia (Fondo Claro y Oscuro)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeService.instance.themeModeNotifier,
            builder: (context, currentMode, _) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selecciona el tema visual de la aplicación:',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined),
                            label: Text('Oscuro'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined),
                            label: Text('Claro'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_outlined),
                            label: Text('Sistema'),
                          ),
                        ],
                        selected: {currentMode},
                        onSelectionChanged: (modes) {
                          ThemeService.instance.setThemeMode(modes.first);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Datos de Cobro',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Perfil de Vendedor (Pago Móvil)'),
              subtitle: Text(
                _profile.hasPagoMovil
                    ? '${_profile.bank} · ${_profile.phone} · ${_profile.idDocument}'
                    : 'Configura tu banco, teléfono y cédula/RIF para adjuntarlos al mensaje del cliente.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SellerProfileScreen(),
                  ),
                );
                await _loadData();
              },
            ),
          ),
          const SizedBox(height: 24),
          const Text('Acerca de', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/icon/app_logo.png',
                      width: 54,
                      height: 54,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calculadora de Márgenes VE',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Versión 1.0.0+1\n'
                          'Para comerciantes en Venezuela: precios en bolívares calculados al instante con tasas BCV, Binance P2P y Euro oficial.\n\n'
                          'Soporta cálculo Sobre Costo (Markup directo) y Sobre Venta (Margen financiero limpio).',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
