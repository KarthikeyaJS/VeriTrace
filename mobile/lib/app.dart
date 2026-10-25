import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/api/api_client.dart';
import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/data/admin_repository.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/products/data/products_repository.dart';
import 'features/reports/data/reports_repository.dart';
import 'features/transfers/data/transfers_repository.dart';
import 'features/verify/data/verify_repository.dart';

class VeriTraceApp extends StatefulWidget {
  const VeriTraceApp({super.key, required this.config, required this.api, required this.authRepository, required this.deviceId});

  final AppConfig config;
  final ApiClient api;
  final AuthRepository authRepository;
  final String deviceId;

  @override
  State<VeriTraceApp> createState() => _VeriTraceAppState();
}

class _VeriTraceAppState extends State<VeriTraceApp> {
  late final AuthBloc _authBloc = AuthBloc(repository: widget.authRepository)..add(const AuthStarted());
  late final GoRouter _router = buildRouter(_authBloc);

  @override
  void dispose() {
    _router.dispose();
    _authBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: widget.config),
        RepositoryProvider.value(value: api),
        RepositoryProvider(create: (_) => VerifyRepository(api: api, deviceId: widget.deviceId)),
        RepositoryProvider(create: (_) => ProductsRepository(api)),
        RepositoryProvider(create: (_) => TransfersRepository(api)),
        RepositoryProvider(create: (_) => AdminRepository(api)),
        RepositoryProvider(create: (_) => ReportsRepository(api)),
      ],
      child: BlocProvider.value(
        value: _authBloc,
        child: MaterialApp.router(
          title: 'VeriTrace',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          themeMode: ThemeMode.light,
          routerConfig: _router,
        ),
      ),
    );
  }
}
