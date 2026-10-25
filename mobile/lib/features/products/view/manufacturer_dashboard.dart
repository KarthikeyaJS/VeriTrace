import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_state.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/view/account_menu.dart';
import '../data/products_repository.dart';
import 'product_list.dart';
import 'qr_actions.dart';

class ManufacturerDashboard extends StatelessWidget {
  const ManufacturerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => LoadCubit<List<Product>>(ctx.read<ProductsRepository>().mine)..load(),
      child: const _ManufacturerView(),
    );
  }
}

class _ManufacturerView extends StatelessWidget {
  const _ManufacturerView();

  Future<void> _printAll(BuildContext context) async {
    final products = context.read<LoadCubit<List<Product>>>().state.data ?? const [];
    final labels = [
      for (final p in products)
        if (p.productHash != null && p.onChain) QrLabel(productId: p.productId, payload: buildQrPayload(p.productId, p.productHash!), name: p.name),
    ];
    if (labels.isEmpty) {
      showMessage(context, 'No registered products to print yet.');
      return;
    }
    try {
      await printLabelSheet(labels, name: 'VeriTrace labels');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Could not print: ${errorMessage(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user?.displayName ?? 'Manufacturer'),
          Text('Manufacturer · My products', style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          IconButton(tooltip: 'Print label sheet for all products', icon: const Icon(Icons.print_outlined), onPressed: () => _printAll(context)),
          ...dashboardActions(context),
        ],
      ),
      body: ProductListView(
        emptyTitle: 'No products yet',
        emptyMessage: 'Register your first product to generate its blockchain fingerprint and QR code.',
        tileBuilder: (context, p) => ProductTile(product: p, subtitle: productHolderLine(p)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/manufacturer/register');
          if (context.mounted) context.read<LoadCubit<List<Product>>>().load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Register product'),
      ),
    );
  }
}
