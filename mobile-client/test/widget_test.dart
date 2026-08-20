import 'package:flutter_test/flutter_test.dart';
import 'package:patchpilot_mobile/main.dart';

void main() {
  testWidgets('RecTraceApp initializes and renders app structure', (WidgetTester tester) async {
    await tester.pumpWidget(const RecTraceApp());
    expect(find.byType(RecTraceApp), findsOneWidget);
  });
}
