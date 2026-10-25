import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veritrace/core/theme/status_style.dart';
import 'package:veritrace/core/widgets/product_widgets.dart';
import 'package:veritrace/features/products/data/products_repository.dart';
import 'package:veritrace/features/products/view/register_product_screen.dart';

class MockProductsRepository extends Mock implements ProductsRepository {}

void main() {
  testWidgets('register form shows validation errors and does not submit when empty', (tester) async {
    final repo = MockProductsRepository();
    await tester.binding.setSurfaceSize(const Size(800, 3000)); // build the whole form
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(RepositoryProvider<ProductsRepository>.value(
      value: repo,
      child: const MaterialApp(home: RegisterProductScreen()),
    ));

    await tester.tap(find.widgetWithText(FilledButton, 'Register product'));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Brand is required'), findsOneWidget);
    expect(find.text('Choose a category'), findsOneWidget);
    verifyNever(() => repo.register(any()));
  });

  testWidgets('status badge always shows icon and text, not colour alone', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Column(children: [StatusBadge(status: VerificationStatus.suspect, large: true), StatusBadge(status: VerificationStatus.flagged)])),
    ));
    expect(find.text('SUSPECT'), findsOneWidget);
    expect(find.byIcon(VerificationStatus.suspect.icon), findsOneWidget);
    expect(find.text('Flagged'), findsOneWidget);
    expect(find.byIcon(VerificationStatus.flagged.icon), findsOneWidget);
  });
}
