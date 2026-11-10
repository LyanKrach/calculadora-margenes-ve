import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/history_service.dart';
import '../services/products_service.dart';

/// Pantalla de Autenticación y Cuenta en la Nube (Firebase Auth + Cloud Firestore).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _authService = AuthService();
  final _productsService = ProductsService();
  final _historyService = HistoryService();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitEmailAuth() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMsg = 'Ingresa tu correo y contraseña.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      if (_isRegisterMode) {
        await _authService.registerWithEmail(
          email: email,
          password: password,
          displayName: _nameCtrl.text.trim(),
        );
      } else {
        await _authService.signInWithEmail(
          email: email,
          password: password,
        );
      }

      // Sincronizar productos e historial locales con Firestore al autenticar
      await _productsService.getProducts(syncRemote: true);
      await _historyService.getHistory(syncRemote: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isRegisterMode
                ? 'Cuenta creada y datos sincronizados con la nube'
                : 'Sesión iniciada y catálogo sincronizado',
          ),
        ),
      );
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = AuthService.friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      await _authService.signInWithGoogle();
      await _productsService.getProducts(syncRemote: true);
      await _historyService.getHistory(syncRemote: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesión iniciada con Google y catálogo sincronizado'),
        ),
      );
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = AuthService.friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _signInAnonymous() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      await _authService.signInAnonymously();
      await _productsService.getProducts(syncRemote: true);
      await _historyService.getHistory(syncRemote: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión de invitado activada en la nube')),
      );
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = AuthService.friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _resetPassword() async {
    final emailPromptCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final confirmedEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_reset, color: Color(0xFF22C55E)),
            SizedBox(width: 8),
            Text('Restablecer contraseña'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa tu correo electrónico registrado y te enviaremos un enlace para que crees una nueva contraseña de forma segura:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailPromptCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(emailPromptCtrl.text.trim()),
            child: const Text('Enviar enlace'),
          ),
        ],
      ),
    );

    if (confirmedEmail == null || confirmedEmail.isEmpty) return;

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      await _authService.sendPasswordReset(confirmedEmail);
      if (!mounted) return;
      setState(() => _loading = false);
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Color(0xFF22C55E)),
              SizedBox(width: 8),
              Text('Enlace enviado'),
            ],
          ),
          content: Text(
            'Se ha enviado un correo a $confirmedEmail con las instrucciones para restablecer tu contraseña. Revisa también tu carpeta de spam.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = AuthService.friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    String? dialogError;
    bool dialogLoading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.password, color: Color(0xFF22C55E)),
              SizedBox(width: 8),
              Text('Cambiar contraseña'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ingresa tu contraseña actual y define tu nueva contraseña segura (mínimo 6 caracteres).',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: currentPassCtrl,
                  obscureText: obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Contraseña actual',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscureCurrent ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    prefixIcon: const Icon(Icons.lock_reset),
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPassCtrl,
                  obscureText: obscureNew,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar nueva contraseña',
                    prefixIcon: Icon(Icons.check_circle_outline),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    dialogError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: dialogLoading ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: dialogLoading
                  ? null
                  : () async {
                      final currentPass = currentPassCtrl.text;
                      final newPass = newPassCtrl.text;
                      final confirmPass = confirmPassCtrl.text;

                      if (currentPass.isEmpty) {
                        setDialogState(() => dialogError = 'Ingresa tu contraseña actual.');
                        return;
                      }
                      if (newPass.length < 6) {
                        setDialogState(() => dialogError = 'La nueva contraseña debe tener al menos 6 caracteres.');
                        return;
                      }
                      if (newPass != confirmPass) {
                        setDialogState(() => dialogError = 'Las contraseñas no coinciden.');
                        return;
                      }

                      setDialogState(() {
                        dialogLoading = true;
                        dialogError = null;
                      });

                      final navigator = Navigator.of(ctx);
                      final messenger = ScaffoldMessenger.of(context);

                      try {
                        await _authService.updatePassword(
                          currentPassword: currentPass,
                          newPassword: newPass,
                        );
                        if (!mounted) return;
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Contraseña actualizada con éxito.')),
                        );
                      } catch (e) {
                        setDialogState(() {
                          dialogLoading = false;
                          dialogError = AuthService.friendlyErrorMessage(e);
                        });
                      }
                    },
              child: dialogLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Actualizar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncNow() async {
    setState(() => _loading = true);
    await _productsService.getProducts(syncRemote: true);
    await _historyService.getHistory(syncRemote: true);
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Catálogo e historial sincronizados con Firestore')),
    );
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sesión cerrada. Tus datos locales siguen disponibles en este teléfono.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuenta y Sincronización'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user != null)
            _buildSignedInView(user)
          else
            _buildSignInForm(),
        ],
      ),
    );
  }

  Widget _buildSignedInView(User user) {
    final isAnon = user.isAnonymous;
    final hasPassword =
        user.providerData.any((p) => p.providerId == 'password') ||
            (user.email != null && !isAnon);
    final isGoogle =
        user.providerData.any((p) => p.providerId == 'google.com');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        isAnon ? Icons.person_outline : Icons.verified_user_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAnon
                                ? 'Cuenta de Invitado (Nube)'
                                : (user.displayName?.isNotEmpty == true
                                    ? user.displayName!
                                    : 'Usuario Autenticado'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            user.email ?? 'ID: ${user.uid.substring(0, 8)}...',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tu catálogo de productos e historial de cálculos se respaldan '
                  'automáticamente en Cloud Firestore y también quedan guardados '
                  'en tu teléfono para funcionar sin internet.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _syncNow,
                        icon: const Icon(Icons.cloud_sync_outlined),
                        label: const Text('Sincronizar ahora'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Salir'),
                    ),
                  ],
                ),
                if (hasPassword && !isGoogle) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showChangePasswordDialog,
                      icon: const Icon(Icons.lock_reset, size: 18),
                      label: const Text('Cambiar contraseña'),
                    ),
                  ),
                ],
                if (isGoogle) ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF22C55E)),
                      SizedBox(width: 6),
                      Text(
                        'Autenticado mediante cuenta de Google',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignInForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/icon/app_logo.png',
              width: 76,
              height: 76,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.cloud_done_outlined),
            title: Text('Respalda tus productos y precios en la nube'),
            subtitle: Text(
              'Inicia sesión o crea una cuenta para respaldar tu catálogo de productos '
              'y tu historial de cálculos en Firebase Firestore. Si prefieres no usar cuenta, '
              'todo sigue funcionando localmente en tu dispositivo.',
            ),
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Iniciar sesión')),
            ButtonSegment(value: true, label: Text('Crear cuenta')),
          ],
          selected: {_isRegisterMode},
          onSelectionChanged: (s) => setState(() {
            _isRegisterMode = s.first;
            _errorMsg = null;
          }),
        ),
        const SizedBox(height: 16),
        if (_isRegisterMode) ...[
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre o negocio (opcional)',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo electrónico',
            hintText: 'tucorreo@ejemplo.com',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        if (_errorMsg != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMsg!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          FilledButton.icon(
            onPressed: _submitEmailAuth,
            icon: Icon(_isRegisterMode ? Icons.person_add : Icons.login),
            label: Text(_isRegisterMode ? 'Registrarme' : 'Entrar con correo'),
          ),
          if (!_isRegisterMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _resetPassword,
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
            ),
          const Divider(height: 24),
          FilledButton.tonalIcon(
            onPressed: _signInWithGoogle,
            icon: const Icon(Icons.account_circle_outlined),
            label: const Text('Continuar con Google'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _signInAnonymous,
            icon: const Icon(Icons.person_outline),
            label: const Text('Activar respaldo rápido como Invitado'),
          ),
        ],
      ],
    );
  }
}

