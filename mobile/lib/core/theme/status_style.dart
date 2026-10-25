import 'package:flutter/material.dart';

import '../models/models.dart';

/// Verification outcome. Every status has a colour, an icon AND a text label (never colour alone).
enum VerificationStatus {
  genuine('Genuine', 'Authentic product with a clean blockchain record', Icons.verified, Color(0xFF2E7D32), Color(0xFFE8F5E9)),
  flagged('Flagged', 'Registered, but something needs your attention', Icons.warning_amber_rounded, Color(0xFFB26A00), Color(0xFFFFF4DC)),
  suspect('Suspect', 'Possible counterfeit — do not trust this product', Icons.gpp_bad, Color(0xFFC62828), Color(0xFFFDECEA)),
  unverified('Unverified', 'No blockchain record — cannot be verified', Icons.help_outline, Color(0xFF616161), Color(0xFFF1F1F1));

  const VerificationStatus(this.label, this.description, this.icon, this.color, this.background);
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final Color background;

  static VerificationStatus parse(Object? v) =>
      VerificationStatus.values.firstWhere((s) => s.label == v?.toString(), orElse: () => VerificationStatus.unverified);
}

/// Severity of a single verification reason.
enum ReasonSeverity {
  critical(Icons.cancel, Color(0xFFC62828)),
  warning(Icons.error_outline, Color(0xFFB26A00)),
  info(Icons.info_outline, Color(0xFF546E7A)),
  ok(Icons.check_circle_outline, Color(0xFF2E7D32));

  const ReasonSeverity(this.icon, this.color);
  final IconData icon;
  final Color color;

  static ReasonSeverity parse(Object? v) =>
      ReasonSeverity.values.firstWhere((s) => s.name == v?.toString(), orElse: () => ReasonSeverity.info);
}

extension StageStyle on ProductStage {
  IconData get icon => switch (this) {
        ProductStage.manufactured => Icons.factory_outlined,
        ProductStage.atSupplier => Icons.local_shipping_outlined,
        ProductStage.atRetailer => Icons.storefront_outlined,
        ProductStage.sold => Icons.shopping_bag_outlined,
        ProductStage.unknown => Icons.help_outline,
      };

  Color get color => switch (this) {
        ProductStage.manufactured => const Color(0xFF3949AB),
        ProductStage.atSupplier => const Color(0xFF00796B),
        ProductStage.atRetailer => const Color(0xFF6A1B9A),
        ProductStage.sold => const Color(0xFF37474F),
        ProductStage.unknown => const Color(0xFF757575),
      };
}
