import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/models.dart';
import '../data/auth_repository.dart';

// ------------------------------------------------------------------ events
sealed class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class AuthLoginRequested extends AuthEvent {
  const AuthLoginRequested(this.email, this.password);
  final String email;
  final String password;
  @override
  List<Object?> get props => [email, password];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

// ------------------------------------------------------------------- state
enum AuthStatus { unknown, unauthenticated, authenticating, authenticated }

class AuthState extends Equatable {
  const AuthState._(this.status, {this.user, this.error});

  const AuthState.unknown() : this._(AuthStatus.unknown);
  const AuthState.unauthenticated({String? error}) : this._(AuthStatus.unauthenticated, error: error);
  const AuthState.authenticating() : this._(AuthStatus.authenticating);
  const AuthState.authenticated(UserProfile user) : this._(AuthStatus.authenticated, user: user);

  final AuthStatus status;
  final UserProfile? user;
  final String? error;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  @override
  List<Object?> get props => [status, user, error];
}

// -------------------------------------------------------------------- bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository repository})
      : _repo = repository,
        super(const AuthState.unknown()) {
    on<AuthStarted>(_onStarted);
    on<AuthLoginRequested>(_onLogin);
    on<AuthLogoutRequested>(_onLogout);
  }

  final AuthRepository _repo;

  AuthRepository get repository => _repo;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    try {
      final user = await _repo.restoreSession();
      emit(user == null ? const AuthState.unauthenticated() : AuthState.authenticated(user));
    } catch (e) {
      emit(AuthState.unauthenticated(error: errorMessage(e)));
    }
  }

  Future<void> _onLogin(AuthLoginRequested event, Emitter<AuthState> emit) async {
    if (event.email.trim().isEmpty || event.password.isEmpty) {
      emit(const AuthState.unauthenticated(error: 'Enter your email and password.'));
      return;
    }
    emit(const AuthState.authenticating());
    try {
      final user = await _repo.signIn(event.email, event.password);
      emit(AuthState.authenticated(user));
    } catch (e) {
      emit(AuthState.unauthenticated(error: errorMessage(e)));
    }
  }

  Future<void> _onLogout(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    await _repo.signOut();
    emit(const AuthState.unauthenticated());
  }
}
