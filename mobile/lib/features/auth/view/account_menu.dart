import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/product_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../bloc/auth_bloc.dart';

/// App-bar actions shared by all dashboards: scanner shortcut + account menu with sign-out.
List<Widget> dashboardActions(BuildContext context) => [
      IconButton(tooltip: 'Scan a product', icon: const Icon(Icons.qr_code_scanner), onPressed: () => context.push('/scan')),
      const AccountMenu(),
    ];

class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    if (user == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: CircleAvatar(radius: 16, child: Text(user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase())),
      onSelected: (v) async {
        if (v == 'home') {
          context.go('/');
          return;
        }
        final ok = await confirmDialog(context, title: 'Sign out?', message: 'You can still verify products without signing in.', confirmLabel: 'Sign out');
        if (ok && context.mounted) {
          context.read<AuthBloc>().add(const AuthLogoutRequested());
          context.go('/');
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.displayName, style: Theme.of(context).textTheme.titleSmall),
            Text('${user.email} · ${user.role.label}', style: Theme.of(context).textTheme.bodySmall),
            if (user.walletAddress != null)
              Text('Wallet ${shortHash(user.walletAddress, head: 8, tail: 6)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'home', child: ListTile(leading: Icon(Icons.home_outlined), title: Text('Public home'), dense: true)),
        const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'), dense: true)),
      ],
    );
  }
}
