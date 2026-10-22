import 'package:fidelia_admin/features/relative_age.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22, 12);
  String age(Duration d) => relativeAge(now.subtract(d), now);

  test('under a minute is « à l\'instant »', () {
    expect(age(Duration.zero), "à l'instant");
    expect(age(const Duration(seconds: 59)), "à l'instant");
    expect(age(const Duration(seconds: -30)), "à l'instant");
  });
  test('minutes, hours, days', () {
    expect(age(const Duration(minutes: 1)), 'il y a 1 min');
    expect(age(const Duration(minutes: 5, seconds: 40)), 'il y a 5 min');
    expect(age(const Duration(minutes: 59)), 'il y a 59 min');
    expect(age(const Duration(hours: 1)), 'il y a 1 h');
    expect(age(const Duration(hours: 3, minutes: 50)), 'il y a 3 h');
    expect(age(const Duration(hours: 23, minutes: 59)), 'il y a 23 h');
    expect(age(const Duration(days: 1)), 'il y a 1 j');
    expect(age(const Duration(days: 2, hours: 5)), 'il y a 2 j');
  });
}
