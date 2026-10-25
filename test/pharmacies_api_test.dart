import 'package:fidelia_admin/core/accounts/pharmacies_api.dart';
import 'package:fidelia_admin/features/duties_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a duty without a zone is read as Abidjan time (UTC)', () {
    final duty = PharmacyDuty.fromJson({'id': 1, 'starts_at': '2030-01-05T08:00:00', 'ends_at': '2030-01-12T08:00:00'});
    expect(duty.startsAt, DateTime.utc(2030, 1, 5, 8));
    expect(dutyMoment(duty.startsAt), 'sam 05/01 08:00');
  });
}
