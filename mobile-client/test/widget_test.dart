import 'package:flutter_test/flutter_test.dart';
import 'package:patchpilot_mobile/main.dart';

void main() {
  testWidgets('PatchPilotApp initializes and renders app structure', (WidgetTester tester) async {
    await tester.pumpWidget(const PatchPilotApp());
    expect(find.byType(PatchPilotApp), findsOneWidget);
  });
}
