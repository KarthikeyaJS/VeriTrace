import 'package:flutter_test/flutter_test.dart';
import 'package:veritrace/core/models/models.dart';
import 'package:veritrace/core/router/app_router.dart';
import 'package:veritrace/features/auth/bloc/auth_bloc.dart';
import 'package:veritrace/features/products/data/products_repository.dart';
import 'package:veritrace/features/scan/data/qr_input.dart';

void main() {
  group('QrInput', () {
    test('accepts VeriTrace payloads and bare IDs', () {
      expect(QrInput.isVeriTrace('veritrace://verify?id=VT-2026-000042&h=${'ab' * 32}'), isTrue);
      expect(QrInput.isVeriTrace('https://veritrace.example/verify?id=VT-2026-000042'), isTrue);
      expect(QrInput.isVeriTrace('vt-2026-000042'), isTrue);
    });

    test('rejects other QR codes', () {
      expect(QrInput.isVeriTrace(''), isFalse);
      expect(QrInput.isVeriTrace('https://example.com'), isFalse);
      expect(QrInput.isVeriTrace('WIFI:S:home;T:WPA;P:secret;;'), isFalse);
      expect(QrInput.isVeriTrace('veritrace://verify?h=abc'), isFalse);
      expect(QrInput.isVeriTrace('hello world'), isFalse);
    });

    test('client payload builder matches the backend format', () {
      expect(buildQrPayload('VT-2026-000001', '0xABCD'), 'veritrace://verify?id=VT-2026-000001&h=abcd');
    });
  });

  group('route guard', () {
    const supplier = UserProfile(uid: 's', email: 's@x', displayName: 'S', role: UserRole.supplier);

    test('public pages are open to everyone', () {
      for (final loc in ['/', '/scan', '/verify', '/login']) {
        expect(authRedirect(const AuthState.unauthenticated(), loc), isNull);
      }
    });

    test('dashboards require login', () {
      expect(authRedirect(const AuthState.unauthenticated(), '/manufacturer'), '/login');
      expect(authRedirect(const AuthState.unauthenticated(), '/products/VT-1'), '/login');
    });

    test('logged-in users are sent to their own dashboard', () {
      const auth = AuthState.authenticated(supplier);
      expect(authRedirect(auth, '/login'), '/supplier');
      expect(authRedirect(auth, '/dashboard'), '/supplier');
      expect(authRedirect(auth, '/admin'), '/supplier');
      expect(authRedirect(auth, '/manufacturer/register'), '/supplier');
      expect(authRedirect(auth, '/supplier'), isNull);
      expect(authRedirect(auth, '/products/VT-1'), isNull);
    });
  });

  test('Product.fromJson reads chain state', () {
    final p = Product.fromJson({
      'productId': 'VT-2026-000004',
      'name': 'Aurora PowerBank 20000',
      'stage': 'AtSupplier',
      'onChain': true,
      'expiryDate': '2020-01-01',
      'chain': {
        'productHash': '0xabc',
        'registeredAt': '2026-10-24T10:00:00Z',
        'currentHolder': {'address': '0x1', 'name': 'Metro Wholesale', 'role': 'supplier', 'uid': 'u2'},
        'pendingRecipient': {'address': '0x2', 'name': 'CityMart Bengaluru', 'role': 'retailer'},
      },
    });
    expect(p.stage, ProductStage.atSupplier);
    expect(p.hasPendingTransfer, isTrue);
    expect(p.currentHolder!.role, UserRole.supplier);
    expect(p.productHash, '0xabc');
    expect(p.isExpired, isTrue);
  });
}
