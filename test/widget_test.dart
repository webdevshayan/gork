import 'package:flutter_test/flutter_test.dart';
import 'package:gork/main.dart';

void main() {
  testWidgets('app builds and shows its name and purpose', (tester) async {
    await tester.pumpWidget(const GorkApp());

    expect(find.text('gork'), findsOneWidget);
    expect(find.text('gork: your personal AI assistant'), findsOneWidget);
  });
}
