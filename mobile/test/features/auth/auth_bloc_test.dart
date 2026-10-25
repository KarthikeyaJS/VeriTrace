import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veritrace/core/errors/api_exception.dart';
import 'package:veritrace/core/models/models.dart';
import 'package:veritrace/features/auth/bloc/auth_bloc.dart';
import 'package:veritrace/features/auth/data/auth_repository.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repo;
  const maker = UserProfile(uid: 'u1', email: 'maker@veritrace.demo', displayName: 'Aurora Electronics', role: UserRole.manufacturer);

  setUp(() => repo = MockAuthRepository());

  test('initial state is unknown', () {
    expect(AuthBloc(repository: repo).state, const AuthState.unknown());
  });

  group('AuthStarted', () {
    blocTest<AuthBloc, AuthState>(
      'restores an existing session',
      setUp: () => when(() => repo.restoreSession()).thenAnswer((_) async => maker),
      build: () => AuthBloc(repository: repo),
      act: (b) => b.add(const AuthStarted()),
      expect: () => [const AuthState.authenticated(maker)],
    );

    blocTest<AuthBloc, AuthState>(
      'is unauthenticated when there is no session',
      setUp: () => when(() => repo.restoreSession()).thenAnswer((_) async => null),
      build: () => AuthBloc(repository: repo),
      act: (b) => b.add(const AuthStarted()),
      expect: () => [const AuthState.unauthenticated()],
    );

    blocTest<AuthBloc, AuthState>(
      'surfaces a deactivated account as an error',
      setUp: () => when(() => repo.restoreSession())
          .thenThrow(const ApiException(code: 'ACCOUNT_DISABLED', message: 'This account has been deactivated.', statusCode: 403)),
      build: () => AuthBloc(repository: repo),
      act: (b) => b.add(const AuthStarted()),
      expect: () => [const AuthState.unauthenticated(error: 'This account has been deactivated.')],
    );
  });

  group('AuthLoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits authenticating then authenticated with the role from /me',
      setUp: () => when(() => repo.signIn('maker@veritrace.demo', 'Demo@1234')).thenAnswer((_) async => maker),
      build: () => AuthBloc(repository: repo),
      act: (b) => b.add(const AuthLoginRequested('maker@veritrace.demo', 'Demo@1234')),
      expect: () => [const AuthState.authenticating(), const AuthState.authenticated(maker)],
      verify: (b) => expect(b.state.user!.role, UserRole.manufacturer),
    );

    blocTest<AuthBloc, AuthState>(
      'emits the error message on wrong password',
      setUp: () => when(() => repo.signIn(any(), any()))
          .thenThrow(const ApiException(code: 'invalid-credential', message: 'Incorrect email or password.')),
      build: () => AuthBloc(repository: repo),
      act: (b) => b.add(const AuthLoginRequested('maker@veritrace.demo', 'nope')),
      expect: () => [const AuthState.authenticating(), const AuthState.unauthenticated(error: 'Incorrect email or password.')],
    );

    blocTest<AuthBloc, AuthState>(
      'validates empty input without calling the repository',
      build: () => AuthBloc(repository: repo),
      act: (b) => b.add(const AuthLoginRequested('  ', '')),
      expect: () => [const AuthState.unauthenticated(error: 'Enter your email and password.')],
      verify: (_) => verifyNever(() => repo.signIn(any(), any())),
    );
  });

  blocTest<AuthBloc, AuthState>(
    'logout signs out and becomes unauthenticated',
    setUp: () => when(() => repo.signOut()).thenAnswer((_) async {}),
    build: () => AuthBloc(repository: repo),
    seed: () => const AuthState.authenticated(maker),
    act: (b) => b.add(const AuthLogoutRequested()),
    expect: () => [const AuthState.unauthenticated()],
    verify: (_) => verify(() => repo.signOut()).called(1),
  );
}
