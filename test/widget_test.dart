import 'package:flutter_test/flutter_test.dart';

import 'package:quran_app/main.dart';

void main() {
  testWidgets('QuranApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const QuranApp());

    // Verify that some home screen text is present.
    expect(find.text('القرآن الكريم'), findsOneWidget);
    expect(find.text('البنود'), findsOneWidget);
  });
}
