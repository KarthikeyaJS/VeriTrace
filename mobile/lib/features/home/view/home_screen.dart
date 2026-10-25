import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../scan/data/qr_input.dart';

/// Public landing page: scan, enter an ID, or go to business login.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _enterId(BuildContext context) async {
    final id = await showDialog<String>(context: context, builder: (_) => const _ManualIdDialog());
    if (id != null && context.mounted) {
      context.push(Uri(path: '/verify', queryParameters: {'id': id}).toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            const Spacer(flex: 2),
            Image.asset('assets/icon/icon_foreground.png', width: 120, height: 120, semanticLabel: 'VeriTrace logo'),
            Text('VeriTrace', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Scan. Verify. Trust.', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Text(
              'Check that a product is genuine and see its journey from the manufacturer — no account needed.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: FilledButton.icon(
                onPressed: () => context.push('/scan'),
                icon: const Icon(Icons.qr_code_scanner, size: 28),
                label: const Text('Scan a product', style: TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _enterId(context),
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter product ID'),
              ),
            ),
            const Spacer(flex: 2),
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) => state.isAuthenticated
                  ? TextButton.icon(
                      onPressed: () => context.go('/dashboard'),
                      icon: const Icon(Icons.dashboard_outlined),
                      label: Text('Open ${state.user!.role.label.toLowerCase()} dashboard'),
                    )
                  : TextButton.icon(
                      onPressed: () => context.push('/login'),
                      icon: const Icon(Icons.business_outlined),
                      label: const Text('Business login'),
                    ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}

class _ManualIdDialog extends StatefulWidget {
  const _ManualIdDialog();

  @override
  State<_ManualIdDialog> createState() => _ManualIdDialogState();
}

class _ManualIdDialogState extends State<_ManualIdDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final id = QrInput.normalizeId(_controller.text);
    if (!QrInput.idPattern.hasMatch(id)) {
      setState(() => _error = 'Enter an ID like VT-2026-000042');
      return;
    }
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter product ID'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(hintText: 'VT-2026-000042', errorText: _error, labelText: 'Product ID'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Verify')),
      ],
    );
  }
}
