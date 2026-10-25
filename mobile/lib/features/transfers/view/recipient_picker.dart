import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/state_views.dart';
import '../data/transfers_repository.dart';

/// Bottom sheet to choose who receives a product. All business roles are listed on
/// purpose: the smart contract (not the UI) decides which transfers are valid.
Future<Recipient?> pickRecipient(BuildContext context, {required Product product}) async {
  final repo = context.read<TransfersRepository>();
  final recipient = await showModalBottomSheet<Recipient>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RecipientSheet(repo: repo),
  );
  if (recipient == null || !context.mounted) return null;
  final ok = await confirmDialog(
    context,
    title: 'Send product?',
    message: 'Send ${product.displayName} (${product.productId}) to ${recipient.displayName} (${recipient.role.label})?\n\n'
        'They must confirm receipt before custody changes on the blockchain.',
    confirmLabel: 'Send',
  );
  return ok ? recipient : null;
}

class _RecipientSheet extends StatefulWidget {
  const _RecipientSheet({required this.repo});
  final TransfersRepository repo;

  @override
  State<_RecipientSheet> createState() => _RecipientSheetState();
}

class _RecipientSheetState extends State<_RecipientSheet> {
  UserRole _role = UserRole.supplier;
  late Future<List<Recipient>> _future = widget.repo.recipients(_role);

  void _select(UserRole role) => setState(() {
        _role = role;
        _future = widget.repo.recipients(role);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Choose recipient', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Allowed: manufacturer → supplier, supplier → supplier or retailer. '
              'The smart contract rejects any other transfer.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<UserRole>(
              segments: const [
                ButtonSegment(value: UserRole.supplier, label: Text('Supplier'), icon: Icon(Icons.local_shipping_outlined)),
                ButtonSegment(value: UserRole.retailer, label: Text('Retailer'), icon: Icon(Icons.storefront_outlined)),
                ButtonSegment(value: UserRole.manufacturer, label: Text('Maker'), icon: Icon(Icons.factory_outlined)),
              ],
              selected: {_role},
              onSelectionChanged: (s) => _select(s.first),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<Recipient>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const LoadingView();
                  if (snap.hasError) return ErrorView(message: errorMessage(snap.error!), onRetry: () => _select(_role));
                  final list = snap.data ?? const [];
                  if (list.isEmpty) {
                    return EmptyView(icon: Icons.person_search, title: 'No ${_role.label.toLowerCase()} accounts', message: 'Ask an admin to create one.');
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => ListTile(
                      leading: CircleAvatar(child: Text(list[i].displayName.isEmpty ? '?' : list[i].displayName[0])),
                      title: Text(list[i].displayName),
                      subtitle: Text(list[i].role.label),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, list[i]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
