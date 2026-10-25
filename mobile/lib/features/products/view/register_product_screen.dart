import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../bloc/register_product_cubit.dart';
import '../data/products_repository.dart';

/// Manufacturer form: registers the product on-chain and stores its details.
class RegisterProductScreen extends StatelessWidget {
  const RegisterProductScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => RegisterProductCubit(ctx.read<ProductsRepository>()),
      child: BlocListener<RegisterProductCubit, RegisterProductState>(
        listenWhen: (a, b) => b.createdId != null && a.createdId != b.createdId,
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${state.createdId} registered on the blockchain')));
          context.pushReplacement('/products/${Uri.encodeComponent(state.createdId!)}');
        },
        child: Scaffold(appBar: AppBar(title: const Text('Register product')), body: const _RegisterForm()),
      ),
    );
  }
}

class _RegisterForm extends StatefulWidget {
  const _RegisterForm();

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _batch = TextEditingController();
  final _serial = TextEditingController();
  final _mrp = TextEditingController();
  final _country = TextEditingController(text: 'India');
  final _description = TextEditingController();
  String? _category;
  DateTime? _mfgDate;
  DateTime? _expiryDate;
  static final _fmt = DateFormat('yyyy-MM-dd');
  static final _display = DateFormat('d MMM yyyy');

  @override
  void dispose() {
    for (final c in [_name, _brand, _batch, _serial, _mrp, _country, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool expiry}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: expiry ? (_expiryDate ?? (_mfgDate ?? now).add(const Duration(days: 365))) : (_mfgDate ?? now),
      firstDate: expiry ? (_mfgDate ?? DateTime(2000)).add(const Duration(days: 1)) : DateTime(2000),
      lastDate: expiry ? DateTime(now.year + 30) : now,
      helpText: expiry ? 'Expiry date' : 'Manufacture date',
    );
    if (picked == null) return;
    setState(() {
      if (expiry) {
        _expiryDate = picked;
      } else {
        _mfgDate = picked;
        if (_expiryDate != null && !_expiryDate!.isAfter(picked)) _expiryDate = null;
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    context.read<RegisterProductCubit>().submit({
      'name': _name.text.trim(),
      'brand': _brand.text.trim(),
      'category': _category,
      'batchNumber': _batch.text.trim(),
      'serialNumber': opt(_serial),
      'manufactureDate': _fmt.format(_mfgDate!),
      'expiryDate': _expiryDate == null ? null : _fmt.format(_expiryDate!),
      'mrp': opt(_mrp) == null ? null : num.parse(_mrp.text.trim()),
      'countryOfOrigin': _country.text.trim(),
      'description': opt(_description),
    });
  }

  String? _required(String? v, String label) => (v == null || v.trim().isEmpty) ? '$label is required' : null;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RegisterProductCubit>().state;
    final busy = state.submitting;
    final theme = Theme.of(context);
    const gap = SizedBox(height: 14);
    return AbsorbPointer(
      absorbing: busy,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Identity fields (*) are fingerprinted with SHA-256 and anchored on the blockchain. They cannot be changed later.',
                style: theme.textTheme.bodySmall),
            gap,
            TextFormField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Product name *'),
              validator: (v) => _required(v, 'Name'),
            ),
            TextFormField(controller: _brand, maxLength: 80, decoration: const InputDecoration(labelText: 'Brand *'), validator: (v) => _required(v, 'Brand')),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category *'),
              items: [for (final c in productCategories) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _category = v),
              validator: (v) => v == null ? 'Choose a category' : null,
            ),
            gap,
            TextFormField(controller: _batch, maxLength: 60, decoration: const InputDecoration(labelText: 'Batch number *'), validator: (v) => _required(v, 'Batch number')),
            TextFormField(controller: _serial, maxLength: 80, decoration: const InputDecoration(labelText: 'Serial number (optional)')),
            _DateField(
              label: 'Manufacture date *',
              value: _mfgDate == null ? null : _display.format(_mfgDate!),
              onTap: () => _pickDate(expiry: false),
              validator: () => _mfgDate == null ? 'Choose the manufacture date' : null,
            ),
            gap,
            _DateField(
              label: 'Expiry date (optional)',
              value: _expiryDate == null ? null : _display.format(_expiryDate!),
              onTap: () => _pickDate(expiry: true),
              onClear: _expiryDate == null ? null : () => setState(() => _expiryDate = null),
              validator: () => _expiryDate != null && _mfgDate != null && !_expiryDate!.isAfter(_mfgDate!) ? 'Expiry must be after the manufacture date' : null,
            ),
            gap,
            TextFormField(
              controller: _mrp,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'MRP (₹, optional)', prefixText: '₹ '),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = num.tryParse(v.trim());
                return n == null || n < 0 ? 'Enter a valid amount' : null;
              },
            ),
            gap,
            TextFormField(controller: _country, maxLength: 60, decoration: const InputDecoration(labelText: 'Country of origin *'), validator: (v) => _required(v, 'Country')),
            TextFormField(controller: _description, maxLength: 1000, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')),
            if (state.error != null) ...[
              gap,
              Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            gap,
            FilledButton.icon(
              onPressed: busy ? null : _submit,
              icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.verified_outlined),
              label: Text(busy ? 'Registering on blockchain…' : 'Register product'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _DateField extends FormField<String> {
  _DateField({required String label, required String? value, required VoidCallback onTap, required String? Function() validator, VoidCallback? onClear})
      : super(
          validator: (_) => validator(),
          builder: (field) => InkWell(
            onTap: onTap,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                errorText: field.errorText,
                suffixIcon: onClear != null
                    ? IconButton(tooltip: 'Clear', icon: const Icon(Icons.clear), onPressed: onClear)
                    : const Icon(Icons.calendar_today_outlined),
              ),
              isEmpty: value == null,
              child: Text(value ?? ''),
            ),
          ),
        );
}
