import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/load_state.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/view/account_menu.dart';
import '../../products/data/products_repository.dart';
import '../../products/view/product_list.dart';
import '../bloc/transfer_actions_cubit.dart';
import '../data/transfers_repository.dart';
import 'recipient_picker.dart';

/// Supplier: Incoming / In custody. Retailer: Incoming / In stock.
class TransfersDashboard extends StatefulWidget {
  const TransfersDashboard({super.key, required this.role});
  final UserRole role;

  @override
  State<TransfersDashboard> createState() => _TransfersDashboardState();
}

class _TransfersDashboardState extends State<TransfersDashboard> {
  late final LoadCubit<List<Product>> _incoming;
  late final LoadCubit<List<Product>> _custody;
  late final TransferActionsCubit _actions;

  @override
  void initState() {
    super.initState();
    final transfers = context.read<TransfersRepository>();
    _incoming = LoadCubit<List<Product>>(transfers.incoming)..load();
    _custody = LoadCubit<List<Product>>(transfers.custody)..load();
    _actions = TransferActionsCubit(
      transfers: transfers,
      products: context.read<ProductsRepository>(),
      onChanged: () => Future.wait([_incoming.load(), _custody.load()]),
    );
  }

  @override
  void dispose() {
    _incoming.close();
    _custody.close();
    _actions.close();
    super.dispose();
  }

  bool get _isRetailer => widget.role == UserRole.retailer;

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    return BlocProvider.value(
      value: _actions,
      child: BlocListener<TransferActionsCubit, TransferActionsState>(
        listenWhen: (a, b) => a.feedback != b.feedback && b.feedback != null,
        listener: (context, s) => showMessage(context, s.feedback!.message, error: s.feedback!.isError),
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.displayName ?? widget.role.label),
                Text(widget.role.label, style: Theme.of(context).textTheme.bodySmall),
              ]),
              actions: dashboardActions(context),
              bottom: TabBar(tabs: [
                Tab(icon: const Icon(Icons.move_to_inbox_outlined), child: _CountLabel(cubit: _incoming, label: 'Incoming')),
                Tab(
                  icon: Icon(_isRetailer ? Icons.storefront_outlined : Icons.inventory_2_outlined),
                  child: _CountLabel(cubit: _custody, label: _isRetailer ? 'In stock' : 'In custody'),
                ),
              ]),
            ),
            body: TabBarView(children: [
              BlocProvider.value(
                value: _incoming,
                child: ProductListView(
                  emptyIcon: Icons.move_to_inbox_outlined,
                  emptyTitle: 'Nothing incoming',
                  emptyMessage: 'Products sent to you appear here until you confirm receipt.',
                  tileBuilder: (context, p) => _IncomingTile(product: p),
                ),
              ),
              BlocProvider.value(
                value: _custody,
                child: ProductListView(
                  emptyIcon: _isRetailer ? Icons.storefront_outlined : Icons.inventory_2_outlined,
                  emptyTitle: _isRetailer ? 'No stock' : 'Nothing in custody',
                  emptyMessage: 'Products you have confirmed appear here.',
                  tileBuilder: (context, p) => _CustodyTile(product: p, retailer: _isRetailer),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CountLabel extends StatelessWidget {
  const _CountLabel({required this.cubit, required this.label});
  final LoadCubit<List<Product>> cubit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoadCubit<List<Product>>, LoadState<List<Product>>>(
      bloc: cubit,
      builder: (context, s) => Text(s.data == null ? label : '$label (${s.data!.length})'),
    );
  }
}

Widget _busyIcon(IconData icon, bool busy) =>
    busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon);

class _IncomingTile extends StatelessWidget {
  const _IncomingTile({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final busy = context.select((TransferActionsCubit c) => c.state.busy.contains(product.productId));
    return ProductTile(
      product: product,
      subtitle: 'From ${product.currentHolder?.name ?? 'unknown'}',
      actions: [
        FilledButton.icon(
          onPressed: busy ? null : () => context.read<TransferActionsCubit>().confirm(product),
          icon: _busyIcon(Icons.check, busy),
          label: Text(busy ? 'Confirming…' : 'Confirm receipt'),
        ),
      ],
    );
  }
}

class _CustodyTile extends StatelessWidget {
  const _CustodyTile({required this.product, required this.retailer});
  final Product product;
  final bool retailer;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TransferActionsCubit>();
    final busy = context.select((TransferActionsCubit c) => c.state.busy.contains(product.productId));
    final List<Widget> actions;
    if (product.hasPendingTransfer) {
      actions = [
        OutlinedButton.icon(
          onPressed: busy ? null : () => cubit.cancel(product),
          icon: _busyIcon(Icons.undo, busy),
          label: const Text('Cancel transfer'),
        ),
      ];
    } else if (retailer) {
      actions = [
        FilledButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final ok = await confirmDialog(context,
                      title: 'Mark as sold?',
                      message: '${product.displayName} (${product.productId}) will be recorded as sold on the blockchain. This cannot be undone.',
                      confirmLabel: 'Mark sold');
                  if (ok) await cubit.sell(product);
                },
          icon: _busyIcon(Icons.point_of_sale, busy),
          label: Text(busy ? 'Recording…' : 'Mark as sold'),
        ),
      ];
    } else {
      actions = [
        FilledButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final to = await pickRecipient(context, product: product);
                  if (to != null) await cubit.initiate(product, to);
                },
          icon: _busyIcon(Icons.local_shipping, busy),
          label: Text(busy ? 'Sending…' : 'Transfer'),
        ),
      ];
    }
    return ProductTile(product: product, subtitle: productHolderLine(product), actions: actions);
  }
}
