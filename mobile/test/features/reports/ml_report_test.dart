import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veritrace/core/widgets/product_widgets.dart';
import 'package:veritrace/features/reports/data/reports_repository.dart';

void main() {
  test('report summary parses the ML section', () {
    final s = ReportSummary.fromJson({
      'scans': {'total': 3, 'byStatus': {'Genuine': 2, 'Flagged': 1}},
      'products': {'total': 1, 'byStage': {}},
      'users': {'byRole': {}},
      'recentAlerts': [
        {'status': 'Flagged', 'productId': 'VT-1', 'flags': ['ML_ANOMALY'], 'ml': {'anomalyScore': 0.64, 'isAnomaly': true}},
      ],
      'ml': {
        'configured': true,
        'ok': true,
        'modelVersion': 'iforest-1',
        'threshold': 0.56,
        'metrics': {'holdoutFalsePositiveRate': 0.01, 'overallRecall': 0.92},
        'scansScored': 3,
        'flaggedByMl': 1,
      },
    });
    expect(s.ml!.online, isTrue);
    expect(s.ml!.flaggedByMl, 1);
    expect(s.ml!.overallRecall, 0.92);
    expect(s.recentAlerts.single.mlScore, 0.64);
    expect(s.recentAlerts.single.mlAnomaly, isTrue);
    expect(ReportSummary.fromJson({'ml': {'configured': true, 'ok': false}}).ml!.online, isFalse);
  });

  Future<void> pumpTechnical(WidgetTester tester, Map<String, dynamic> technical) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TechnicalDetails(technical: technical)))));
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
  }

  testWidgets('technical details show the ML verdict', (tester) async {
    await pumpTechnical(tester, {
      'ml': {'anomalyScore': 0.52, 'threshold': 0.56, 'isAnomaly': false, 'modelVersion': 'iforest-1'},
    });
    expect(find.textContaining('score 0.520 (threshold 0.560): normal'), findsOneWidget);
  });

  testWidgets('technical details say when ML was offline', (tester) async {
    await pumpTechnical(tester, {'ml': null});
    expect(find.textContaining('ML service offline'), findsOneWidget);
  });
}
