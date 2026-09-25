import 'package:flutter_test/flutter_test.dart';
import 'package:speakcards/features/laya/laya_protocol.dart';
import 'package:speakcards/features/srs/srs_service.dart';
import 'package:speakcards/features/srs/drill_service.dart';

void main() {
  test('invalid action falls back to schedule_review', () {
    final d = LayaDecision.fromJson({'next_action': 'dance'}, 'perro');
    expect(d.nextAction, 'schedule_review');
  });

  test('srs bands match spec', () {
    final t = DateTime(2026, 1, 1);
    expect(SrsService.nextDueMs(50, now: t), t.millisecondsSinceEpoch);
    expect(SrsService.nextDueMs(70, now: t),
        greaterThan(t.millisecondsSinceEpoch),);
    expect(
        SrsService.nextDueMs(85, now: t) - t.millisecondsSinceEpoch,
        greaterThanOrEqualTo(
            SrsService.nextDueMs(70, now: t) - t.millisecondsSinceEpoch,),);
  });

  test('drill triggers after 3 sub-70', () {
    expect(DrillService().shouldTrigger([58, 64, 61]), isTrue);
    expect(DrillService().shouldTrigger([90, 92, 91]), isFalse);
    expect(DrillService().shouldTrigger([50]), isFalse);
  });
}
