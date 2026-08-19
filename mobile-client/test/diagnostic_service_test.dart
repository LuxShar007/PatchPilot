import 'package:flutter_test/flutter_test.dart';
import 'package:patchpilot_mobile/services/diagnostic_service.dart';
import 'package:patchpilot_mobile/services/ocr_service.dart';

void main() {
  group('Module A - Strict JSON Integration Contract Tests', () {
    test('DiagnosticResult matches the exact required JSON specification', () {
      final sample = DiagnosticResult.sampleKeyError();
      final jsonMap = sample.toJson();

      // Check all 5 mandatory keys exist
      expect(jsonMap.containsKey('root_cause'), isTrue);
      expect(jsonMap.containsKey('target_file'), isTrue);
      expect(jsonMap.containsKey('explanation'), isTrue);
      expect(jsonMap.containsKey('patch_diff'), isTrue);
      expect(jsonMap.containsKey('test_command'), isTrue);

      // Validate exact expected values
      expect(jsonMap['root_cause'], "KeyError: 'role' missing in input dictionary");
      expect(jsonMap['target_file'], "app.py");
      expect(jsonMap['explanation'], "Added fallback handling for missing user role key.");
      expect(jsonMap['patch_diff'], contains("--- a/app.py\n+++ b/app.py"));
      expect(jsonMap['patch_diff'], contains("+    role = user_dict.get('role', 'user')"));
      expect(jsonMap['test_command'], "pytest");
    });

    test('DiagnosticService parses raw JSON string into valid DiagnosticResult', () {
      final service = DiagnosticService();
      const rawJson = '''
      {
        "root_cause": "KeyError: 'role' missing in input dictionary",
        "target_file": "app.py",
        "explanation": "Added fallback handling for missing user role key.",
        "patch_diff": "--- a/app.py\\n+++ b/app.py\\n@@ -1,7 +1,8 @@\\n def process_user_data(user_dict):\\n-    return {'name': user_dict['name'], 'role': user_dict['role'].upper(), 'status': 'active'}\\n+    role = user_dict.get('role', 'user')\\n+    return {'name': user_dict['name'], 'role': role.upper(), 'status': 'active'}\\n",
        "test_command": "pytest"
      }
      ''';

      final result = service.parseJsonResponse(rawJson);
      expect(result.rootCause, "KeyError: 'role' missing in input dictionary");
      expect(result.targetFile, "app.py");
      expect(result.testCommand, "pytest");
      expect(result.patchDiff, contains("--- a/app.py"));
    });

    test('OcrService correctly extracts Python stack trace and KeyError signature', () {
      final ocrService = OcrService();
      final terminalText = OcrService.sampleKeyErrorTerminalOutput();
      final payload = ocrService.parseRawTextString(terminalText);

      expect(payload.detectedErrorType, contains('KeyError'));
      expect(payload.detectedTargetFile, 'app.py');
      expect(payload.detectedLineNumber, 2);
      expect(payload.stackTraceLines.isNotEmpty, isTrue);
    });

    test('DiagnosticService analyze handles KeyError payload with valid unified diff', () async {
      final diagnosticService = DiagnosticService();
      final ocrService = OcrService();
      final terminalText = OcrService.sampleKeyErrorTerminalOutput();
      final payload = ocrService.parseRawTextString(terminalText);

      final result = await diagnosticService.analyze(
        scannedText: payload.rawText,
        userCommand: "Fix missing role key with fallback default",
      );

      expect(result.rootCause, contains("KeyError"));
      expect(result.targetFile, "app.py");
      expect(result.patchDiff, contains("--- a/app.py"));
      expect(result.patchDiff, contains("+++ b/app.py"));
      expect(result.patchDiff, contains("role = user_dict.get"));
      expect(result.testCommand, "pytest");
    });

    test('DiagnosticService analyze produces ZeroDivisionError patch with proper hunk headers', () async {
      final diagnosticService = DiagnosticService();
      const zeroDivText = '''
Traceback (most recent call last):
  File "metrics_service.py", line 4, in compute_latency_stats
    "avg": sum(latencies_ms) / len(latencies_ms),
ZeroDivisionError: division by zero
''';

      final result = await diagnosticService.analyze(
        scannedText: zeroDivText,
        userCommand: "Prevent division by zero",
      );

      expect(result.rootCause, contains("ZeroDivisionError"));
      expect(result.targetFile, "metrics_service.py");
      expect(result.explanation, contains("zero stats"));
      expect(result.patchDiff, contains("--- a/metrics_service.py"));
      expect(result.patchDiff, contains("+++ b/metrics_service.py"));
      expect(result.patchDiff, contains("@@ -1,5 +1,8 @@"));
      expect(result.testCommand, contains("pytest"));
    });

    test('DiagnosticService analyze produces TypeError null-check patch for cart_service / React', () async {
      final diagnosticService = DiagnosticService();
      const typeErrorText = '''
TypeError: unsupported operand type(s) for /: 'NoneType' and 'float'
  File "cart_service.py", line 3, in calculate_cart_total
''';

      final result = await diagnosticService.analyze(
        scannedText: typeErrorText,
        userCommand: "Handle optional discount",
      );

      expect(result.rootCause, contains("TypeError"));
      expect(result.targetFile, "cart_service.py");
      expect(result.patchDiff, contains("--- a/cart_service.py"));
      expect(result.patchDiff, contains("+++ b/cart_service.py"));
      expect(result.patchDiff, contains("@@ -1,4 +1,5 @@"));
      expect(result.testCommand, contains("pytest"));
    });
  });
}
