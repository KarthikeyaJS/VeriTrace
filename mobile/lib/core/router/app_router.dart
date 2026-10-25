import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/view/admin_dashboard.dart';
import '../../features/admin/view/create_user_screen.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/view/login_screen.dart';
import '../../features/home/view/home_screen.dart';
import '../../features/products/view/journey_screen.dart';
import '../../features/products/view/manufacturer_dashboard.dart';
import '../../features/products/view/product_detail_screen.dart';
import '../../features/products/view/register_product_screen.dart';
import '../../features/scan/view/scanner_screen.dart';
import '../../features/transfers/view/transfers_dashboard.dart';
import '../../features/verify/view/verify_screen.dart';
import '../models/models.dart';

String homeForRole(UserRole role) => switch (role) {
      UserRole.admin => '/admin',
      UserRole.manufacturer => '/manufacturer',
      UserRole.supplier => '/supplier',
      UserRole.retailer => '/retailer',
      UserRole.none => '/',
    };

const _roleAreas = {
  '/admin': UserRole.admin,
  '/manufacturer': UserRole.manufacturer,
  '/supplier': UserRole.supplier,
  '/retailer': UserRole.retailer,
};

bool _isPublic(String loc) => loc == '/' || loc == '/scan' || loc == '/verify' || loc == '/login';

/// Route guard: public pages are open; dashboards need login and the matching role.
/// (The backend enforces roles again — this is only navigation.)
String? authRedirect(AuthState auth, String location) {
  if (auth.status == AuthStatus.unknown) return _isPublic(location) ? null : '/';
  final user = auth.user;
  if (!auth.isAuthenticated || user == null) {
    return _isPublic(location) ? null : '/login';
  }
  if (location == '/login' || location == '/dashboard') return homeForRole(user.role);
  for (final entry in _roleAreas.entries) {
    if (location.startsWith(entry.key) && user.role != entry.value) return homeForRole(user.role);
  }
  return null;
}

GoRouter buildRouter(AuthBloc authBloc) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _StreamListenable(authBloc.stream),
    redirect: (context, state) => authRedirect(authBloc.state, state.matchedLocation),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/scan', builder: (_, _) => const ScannerScreen()),
      GoRoute(
        path: '/verify',
        builder: (_, state) => VerifyScreen(payload: state.uri.queryParameters['payload'], productId: state.uri.queryParameters['id']),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/dashboard', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: '/manufacturer',
        builder: (_, _) => const ManufacturerDashboard(),
        routes: [GoRoute(path: 'register', builder: (_, _) => const RegisterProductScreen())],
      ),
      GoRoute(path: '/supplier', builder: (_, _) => const TransfersDashboard(role: UserRole.supplier)),
      GoRoute(path: '/retailer', builder: (_, _) => const TransfersDashboard(role: UserRole.retailer)),
      GoRoute(
        path: '/admin',
        builder: (_, _) => const AdminDashboard(),
        routes: [GoRoute(path: 'users/new', builder: (_, _) => const CreateUserScreen())],
      ),
      GoRoute(
        path: '/products/:id',
        builder: (_, state) => ProductDetailScreen(productId: state.pathParameters['id']!),
        routes: [GoRoute(path: 'journey', builder: (_, state) => JourneyScreen(productId: state.pathParameters['id']!))],
      ),
    ],
  );
}

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
