import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' hide VerificationResult;
import 'package:veritrace/core/errors/api_exception.dart';
import 'package:veritrace/core/theme/status_style.dart';
import 'package:veritrace/features/verify/bloc/verify_bloc.dart';
import 'package:veritrace/features/verify/data/verification_result.dart';
import 'package:veritrace/features/verify/data/verify_repository.dart';

class MockVerifyRepository extends Mock implements VerifyRepository {}

void main() {
  late MockVerifyRepository repo;
  const payload = 'veritrace://verify?id=VT-2026-000001&h=abcd';

  final genuine = VerificationResult.fromJson({
    'status': 'Genuine',
    'reasons': [
      {'code': 'QR_HASH_MATCH', 'severity': 'ok', 'message': 'QR fingerprint matches the blockchain record.'},
    ],
    'product': {'productId': 'VT-2026-000001', 'name': 'Aurora X1 Smartphone', 'stage': 'Sold', 'onChain': true},
    'journey': [
      {
        'eventType': 'Registered',
        'label': 'Registered on blockchain',
        'stageAfter': 'Manufactured',
        'timestamp': '2026-10-24T10:00:00Z',
        'txHash': '0x1',
        'blockNumber': 3,
      },
    ],
    'technical': {'contractAddress': '0xC', 'chainId': 31337},
  });

  setUp(() => repo = MockVerifyRepository());

  test('parses statuses, reasons, journey and technical details', () {
    expect(genuine.status, VerificationStatus.genuine);
    expect(genuine.reasons.single.severity, ReasonSeverity.ok);
    expect(genuine.product!.name, 'Aurora X1 Smartphone');
    expect(genuine.journey.single.blockNumber, 3);
    expect(genuine.technical['chainId'], 31337);
    expect(VerificationResult.fromJson({'status': 'Suspect', 'reasons': <Object>[]}).status, VerificationStatus.suspect);
    expect(VerificationResult.fromJson({'status': 'weird'}).status, VerificationStatus.unverified);
  });

  blocTest<VerifyBloc, VerifyState>(
    'scanned payload -> loading -> success',
    setUp: () => when(() => repo.verify(payload: payload, productId: null)).thenAnswer((_) async => genuine),
    build: () => VerifyBloc(repository: repo),
    act: (b) => b.add(const VerifyRequested(payload: payload)),
    expect: () => [const VerifyLoading(), VerifySuccess(genuine)],
  );

  blocTest<VerifyBloc, VerifyState>(
    'manual product ID is trimmed and passed through',
    setUp: () => when(() => repo.verify(payload: null, productId: 'VT-2026-000001')).thenAnswer((_) async => genuine),
    build: () => VerifyBloc(repository: repo),
    act: (b) => b.add(const VerifyRequested(productId: ' VT-2026-000001 ')),
    expect: () => [const VerifyLoading(), VerifySuccess(genuine)],
  );

  blocTest<VerifyBloc, VerifyState>(
    'network error -> failure with a readable message',
    setUp: () => when(() => repo.verify(payload: any(named: 'payload'), productId: any(named: 'productId')))
        .thenThrow(const ApiException(code: 'NETWORK', message: 'Cannot reach the VeriTrace server.')),
    build: () => VerifyBloc(repository: repo),
    act: (b) => b.add(const VerifyRequested(payload: payload)),
    expect: () => [const VerifyLoading(), const VerifyFailure('Cannot reach the VeriTrace server.')],
  );

  blocTest<VerifyBloc, VerifyState>(
    'empty input fails without calling the backend',
    build: () => VerifyBloc(repository: repo),
    act: (b) => b.add(const VerifyRequested(payload: '  ')),
    expect: () => [const VerifyFailure('Scan a QR code or enter a product ID.')],
    verify: (_) => verifyNever(() => repo.verify(payload: any(named: 'payload'), productId: any(named: 'productId'))),
  );

  blocTest<VerifyBloc, VerifyState>(
    'retry re-runs the last request',
    setUp: () {
      var calls = 0;
      when(() => repo.verify(payload: payload, productId: null)).thenAnswer((_) async {
        if (calls++ == 0) throw const ApiException(code: 'TIMEOUT', message: 'Timed out');
        return genuine;
      });
    },
    build: () => VerifyBloc(repository: repo),
    act: (b) async {
      b.add(const VerifyRequested(payload: payload));
      await Future<void>.delayed(Duration.zero);
      b.add(const VerifyRetried());
    },
    expect: () => [const VerifyLoading(), const VerifyFailure('Timed out'), const VerifyLoading(), VerifySuccess(genuine)],
  );
}
