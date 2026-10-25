import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/bloc/load_state.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/product_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/view/account_menu.dart';
import '../../products/data/products_repository.dart';
import '../../products/view/product_list.dart';
import '../../reports/view/reports_view.dart';
import '../bloc/users_cubit.dart';
import '../data/admin_repository.dart';

/// Admin: Users (create, role, activate) · All products · Reports.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (ctx) => UsersCubit(ctx.read<AdminRepository>())..load()),
        BlocProvider(create: (ctx) => LoadCubit<List<Product>>(ctx.read<ProductsRepository>().all)..load()),
      ],
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user?.displayName ?? 'Admin'),
              Text(['Users', 'All products', 'Reports'][_tab], style: Theme.of(context).textTheme.bodySmall),
            ]),
            actions: dashboardActions(context),
          ),
          body: IndexedStack(index: _tab, children: [
            const _UsersTab(),
            ProductListView(
              emptyTitle: 'No products registered yet',
              tileBuilder: (context, p) => ProductTile(product: p, subtitle: '${p.manufacturerName ?? '—'} · ${productHolderLine(p)}'),
            ),
            if (_tab == 2) const ReportsView() else const SizedBox.shrink(),
          ]),
          floatingActionButton: _tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    final created = await context.push<bool>('/admin/users/new');
                    if (created == true && context.mounted) context.read<UsersCubit>().load();
                  },
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('New account'),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Users'),
              NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Products'),
              NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Reports'),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UsersCubit>();
    return BlocConsumer<UsersCubit, UsersState>(
      listenWhen: (a, b) => a.feedback != b.feedback && b.feedback != null,
      listener: (context, s) => showMessage(context, s.feedback!.message, error: s.feedback!.isError),
      builder: (context, state) {
        final users = state.users;
        return Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              for (final role in <UserRole?>[null, ...UserRole.business])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(role?.label ?? 'All'),
                    selected: state.filter == role,
                    onSelected: (_) => cubit.setFilter(role),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: users == null
                ? (state.status == LoadStatus.failure ? ErrorView(message: state.error!, onRetry: cubit.load) : const LoadingView())
                : RefreshIndicator(
                    onRefresh: cubit.load,
                    child: users.isEmpty
                        ? const RefreshableCenter(child: EmptyView(icon: Icons.people_outline, title: 'No accounts for this filter'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: users.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => _UserTile(user: users[i], busy: state.busyUid == users[i].uid),
                          ),
                  ),
          ),
        ]);
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.busy});
  final UserProfile user;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = context.select((AuthBloc b) => b.state.user?.uid) == user.uid;
    final inSync = user.chainRoleInSync;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${user.displayName}${me ? ' (you)' : ''}',
                  style: theme.textTheme.titleMedium?.copyWith(color: user.active ? null : theme.colorScheme.outline)),
              Text(user.email, style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Chip(label: Text(user.role.label), visualDensity: VisualDensity.compact),
                if (!user.active) Chip(label: const Text('Inactive'), visualDensity: VisualDensity.compact, backgroundColor: theme.colorScheme.errorContainer),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(inSync ? Icons.link : Icons.link_off, size: 14, color: inSync ? const Color(0xFF2E7D32) : theme.colorScheme.error),
                  const SizedBox(width: 2),
                  Text('On-chain: ${user.chainRole?.label ?? '—'}', style: theme.textTheme.bodySmall),
                ]),
              ]),
              if (user.walletAddress != null)
                Text(shortHash(user.walletAddress, head: 8, tail: 6), style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
            ]),
          ),
          if (busy)
            const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))
          else if (!me)
            PopupMenuButton<String>(
              tooltip: 'Manage account',
              onSelected: (v) async {
                final cubit = context.read<UsersCubit>();
                if (v == 'toggle') {
                  final ok = await confirmDialog(
                    context,
                    title: user.active ? 'Deactivate ${user.displayName}?' : 'Activate ${user.displayName}?',
                    message: user.active
                        ? 'They will be signed out of the backend and their on-chain role set to None.'
                        : 'Their on-chain role will be restored to ${user.role.label}.',
                    confirmLabel: user.active ? 'Deactivate' : 'Activate',
                  );
                  if (ok) await cubit.update(user, active: !user.active);
                } else {
                  final role = UserRole.parse(v);
                  if (role != user.role) await cubit.update(user, role: role);
                }
              },
              itemBuilder: (context) => [
                for (final r in UserRole.business)
                  CheckedPopupMenuItem(value: r.name, checked: r == user.role, child: Text('Role: ${r.label}')),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'toggle', child: Text(user.active ? 'Deactivate' : 'Activate')),
              ],
            ),
        ]),
      ),
    );
  }
}
