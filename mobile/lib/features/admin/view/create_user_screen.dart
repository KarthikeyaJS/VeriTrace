import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/state_views.dart';
import '../data/admin_repository.dart';

/// Admin form: creates a Firebase account, a custodial wallet, and assigns the role on-chain.
class CreateUserScreen extends StatefulWidget {
  const CreateUserScreen({super.key});

  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController(text: _generatePassword());
  UserRole _role = UserRole.manufacturer;
  bool _busy = false;
  String? _error;

  static String _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return '${List.generate(10, (_) => chars[r.nextInt(chars.length)]).join()}@7';
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await context.read<AdminRepository>().createUser(
            email: _email.text.trim(),
            password: _password.text,
            displayName: _name.text.trim(),
            role: _role,
          );
      if (!mounted) return;
      showMessage(context, '${user.displayName} created · on-chain role ${user.role.label}');
      context.pop(true);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New business account')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Form(
          key: _formKey,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Business / display name', hintText: 'e.g. Southern Distributors'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a name' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<UserRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [for (final r in UserRole.business) DropdownMenuItem(value: r, child: Text(r.label))],
              onChanged: (r) => setState(() => _role = r ?? _role),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Initial password',
                helperText: 'Share it with the user securely.',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(ClipboardData(text: _password.text)),
                  ),
                  IconButton(
                    tooltip: 'Generate',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(() => _password.text = _generatePassword()),
                  ),
                ]),
              ),
              validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
            ),
            const SizedBox(height: 12),
            Text('A custodial blockchain wallet is created for the account and the role is written to the smart contract.',
                style: theme.textTheme.bodySmall),
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: theme.colorScheme.error))],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.person_add),
              label: Text(_busy ? 'Creating…' : 'Create account'),
            ),
          ]),
        ),
      ),
    );
  }
}
