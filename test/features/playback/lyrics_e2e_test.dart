import 'package:flutter_test/flutter_test.dart';

import '../../lyrics_e2e/tier1_feature_test.dart' as tier1;
import '../../lyrics_e2e/tier2_boundary_test.dart' as tier2;
import '../../lyrics_e2e/tier3_cross_feature_test.dart' as tier3;
import '../../lyrics_e2e/tier4_real_world_test.dart' as tier4;

/// Master Acceptance Test Runner for Tachyon Lyrics Subsystem.
///
/// Executes all 4 Tiers of the Opaque-Box E2E Test Suite:
/// - Tier 1: Isolated Feature Verification (Features F1 - F18, 90 tests)
/// - Tier 2: Boundary, Corner Cases & Error-Prone Inputs (Features F1 - F18, 90 tests)
/// - Tier 3: Cross-Feature Interaction Verification (18 tests)
/// - Tier 4: Real-World Application Scenarios (10 scenarios)
///
/// Total: 208 comprehensive tests covering 100% of user requirements R1, R2, R3.
void main() {
  group('Tachyon Lyrics Subsystem: Master E2E Acceptance Test Suite', () {
    tier1.main();
    tier2.main();
    tier3.main();
    tier4.main();
  });
}
