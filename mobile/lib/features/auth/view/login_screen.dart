import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../bloc/auth_bloc.dart';

/// Email/password login for business accounts. The tune icon opens the (hidden) server setting.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    context.read<AuthBloc>().add(AuthLoginRequested(_email.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.read<AuthBloc>().repository;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business login'),
        actions: [
          IconButton(
            tooltip: 'Server settings',
            icon: const Icon(Icons.tune),
            onPressed: () => showDialog<void>(context: context, builder: (_) => const ServerSettingsDialog()),
          ),
        ],
      ),
      // /login is usually pushed on top of '/', so the router's redirect does not re-run for it:
      // navigate explicitly once signed in.
      body: BlocConsumer<AuthBloc, AuthState>(
        listenWhen: (a, b) => !a.isAuthenticated && b.isAuthenticated,
        listener: (context, state) => context.go(homeForRole(state.user!.role)),
        builder: (context, state) {
          final busy = state.status == AuthStatus.authenticating;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('For manufacturers, suppliers, retailers and admins.', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text('Consumers can verify products without an account.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              if (!repo.isAvailable)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(repo.unavailableReason ?? 'Business login is not available in this build.'),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                enabled: !busy,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => busy ? null : _submit(),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 16),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(state.error!, style: TextStyle(color: theme.colorScheme.error))),
                ]),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy || !repo.isAvailable ? null : _submit,
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 16),
              Text('There is no public sign-up. Ask your VeriTrace admin for an account.',
                  textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            ],
          );
        },
      ),
    );
  }
}

/// Lets the tester point the app at another backend URL without rebuilding (persisted).
class ServerSettingsDialog extends StatefulWidget {
  const ServerSettingsDialog({super.key});

  @override
  State<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  late final TextEditingController _url;
  String? _status;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: context.read<AppConfig>().apiBaseUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final config = context.read<AppConfig>();
    final api = context.read<ApiClient>();
    final hadOverride = config.hasOverride;
    final previous = config.apiBaseUrl;
    setState(() {
      _testing = true;
      _status = null;
    });
    await config.setApiBaseUrl(_url.text);
    try {
      final health = await api.get('/health');
      final chain = health['chain'] as Map? ?? {};
      setState(() => _status = '✓ Connected — ${health['status']} (chain ${chain['connected'] == true ? 'up' : 'down'}, '
          'firestore ${(health['firestore'] as Map?)?['ok'] == true ? 'up' : 'down'})');
    } catch (e) {
      setState(() => _status = '✗ ${errorMessage(e)}');
    } finally {
      await config.setApiBaseUrl(hadOverride ? previous : null); // testing must not save
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.read<AppConfig>();
    return AlertDialog(
      title: const Text('Server settings'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Backend URL', hintText: 'http://192.168.1.12:3000'),
        ),
        const SizedBox(height: 8),
        Text('Build default: ${config.defaultApiBaseUrl}', style: Theme.of(context).textTheme.bodySmall),
        if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
      ]),
      actions: [
        TextButton(
          onPressed: () async {
            await config.setApiBaseUrl(null);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Reset'),
        ),
        TextButton(onPressed: _testing ? null : _test, child: Text(_testing ? 'Testing…' : 'Test')),
        FilledButton(
          onPressed: () async {
            await config.setApiBaseUrl(_url.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
