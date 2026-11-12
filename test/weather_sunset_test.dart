import 'package:flutter_test/flutter_test.dart';
import 'package:gork/services/weather_service.dart';

void main() {
  test('sunsetFor computes a plausible Sehwan sunset (UTC math)', () {
    // Sehwan Sharif: 26.4195 N, 67.8622 E — reference screenshot shows
    // 5:40 PM local (PKT = UTC+5) on Nov 12.
    final utc = DateTime.utc(2026, 11, 12, 6); // any time that day
    final sunsetUtc = sunsetFor(26.4195, 67.8622, utc);
    final pkt = sunsetUtc.toUtc().add(const Duration(hours: 5));
    expect(pkt.hour, inInclusiveRange(17, 18));
    expect(pkt.minute, inInclusiveRange(20, 59));
  });

  test('sunsetFor is pure: same input, same output', () {
    final a = sunsetFor(51.5, -0.12, DateTime.utc(2026, 6, 21));
    final b = sunsetFor(51.5, -0.12, DateTime.utc(2026, 6, 21));
    expect(a, b);
  });
}
