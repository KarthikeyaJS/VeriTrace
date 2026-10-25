import 'package:equatable/equatable.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/status_style.dart';

class VerificationReason extends Equatable {
  const VerificationReason({required this.code, required this.severity, required this.message});
  final String code;
  final ReasonSeverity severity;
  final String message;

  factory VerificationReason.fromJson(Json j) => VerificationReason(
        code: j['code'].toString(),
        severity: ReasonSeverity.parse(j['severity']),
        message: j['message']?.toString() ?? '',
      );

  @override
  List<Object?> get props => [code, severity, message];
}

class VerificationResult extends Equatable {
  const VerificationResult({
    required this.status,
    required this.reasons,
    this.product,
    this.journey = const [],
    this.technical = const {},
  });

  final VerificationStatus status;
  final List<VerificationReason> reasons;
  final Product? product;
  final List<JourneyEvent> journey;
  final Json technical;

  factory VerificationResult.fromJson(Json j) {
    final productJson = j['product'];
    return VerificationResult(
      status: VerificationStatus.parse(j['status']),
      reasons: (j['reasons'] as List? ?? const [])
          .whereType<Map>()
          .map((r) => VerificationReason.fromJson(Map<String, dynamic>.from(r)))
          .toList(),
      product: productJson is Map && productJson['productId'] != null ? Product.fromJson(Map<String, dynamic>.from(productJson)) : null,
      journey: parseJourney(j['journey']),
      technical: j['technical'] is Map ? Map<String, dynamic>.from(j['technical'] as Map) : const {},
    );
  }

  @override
  List<Object?> get props => [status, reasons, product, journey, technical];
}
