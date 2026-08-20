# RecTrace - Mobile Client (Module A)
### Cross-Device Code & Error Precision Fixing Studio (iQOO Hackathon)

The **RecTrace Mobile Client** is an on-device diagnostic studio engineered for the loaner iQOO phone. It pairs dual-deck error & code editing, computer vision (real-time OCR), developer voice commands, and Small Language Model (SLM) prompt formatting to inspect terminal stack traces and emit production-grade git patches.

---

## 📁 Directory Structure

```
mobile-client/
├── pubspec.yaml                       # Dependencies (ML Kit, Speech-to-Text, Camera, Path Provider)
├── analysis_options.yaml              # Dart analyzer configuration
├── android/
│   └── app/src/main/AndroidManifest.xml # Permissions (Camera, Audio, Storage, Internet)
├── lib/
│   ├── main.dart                      # App entrypoint, Dark IDE Theme, navigation routing
│   ├── models/
│   │   ├── diagnostic_result.dart     # Strict JSON Contract data model & serialization
│   │   └── ocr_box.dart               # ML Kit OCR bounding boxes & error metadata
│   ├── screens/
│   │   ├── studio_screen.dart         # Primary dual-deck fixing studio with laptop workspace sync
│   │   ├── scanner_screen.dart        # Camera viewfinder with OCR overlay & pulsing mic button
│   │   └── patch_inspector_screen.dart# Unified diff viewer, root cause summary, Copy Diff & Push to Bridge
│   ├── services/
│   │   ├── ocr_service.dart           # Google ML Kit OCR text recognition & stack trace parser
│   │   ├── voice_service.dart         # Speech-to-text handler for developer voice commands
│   │   ├── diagnostic_service.dart    # Gemma-2B/Phi-3/Groq prompt builder & fallback patch generator
│   │   └── bridge_service.dart        # File exporter to inbox_patches/fix.patch & Office Kit clipboard sync
│   └── widgets/
│       ├── diff_viewer.dart           # Formatted unified diff viewer (+ additions, - deletions)
│       ├── ocr_overlay_painter.dart   # Live viewfinder visual bounding box renderer
│       └── pulse_mic_button.dart      # Animated mic button with audio wave visualizer
└── test/
    └── diagnostic_service_test.dart   # Contract verification tests
```

---

## ⚡ Output Contract (Strict JSON Integration)

When **"Analyze & Generate Patch"** is tapped or voice is processed, `DiagnosticService` produces the exact contract required by RecTrace:

```json
{
  "root_cause": "KeyError: 'role' missing in input dictionary",
  "target_file": "app.py",
  "explanation": "Added fallback handling for missing user role key.",
  "patch_diff": "--- a/app.py\n+++ b/app.py\n@@ -1,7 +1,8 @@\n def process_user_data(user_dict):\n-    return {'name': user_dict['name'], 'role': user_dict['role'].upper(), 'status': 'active'}\n+    role = user_dict.get('role', 'user')\n+    return {'name': user_dict['name'], 'role': role.upper(), 'status': 'active'}\n",
  "test_command": "pytest"
}
```

---

## 🛠️ Exported Interfaces & Services

### 1. `OcrService` (`lib/services/ocr_service.dart`)
- `Future<OcrAnalysisPayload> processImage(InputImage inputImage)`: Real-time ML Kit image processing.
- `OcrAnalysisPayload parseRecognizedText(RecognizedText recognizedText)`: Extracts stack traces, file paths, line numbers, and error classifications (`KeyError`, `NullPointerException`, `TypeError`, etc.).
- `OcrAnalysisPayload parseRawTextString(String text)`: Text-level parsing for emulator/manual inputs.

### 2. `VoiceService` (`lib/services/voice_service.dart`)
- `Future<bool> initialize()`: Initializes speech engine with error fallback.
- `Future<void> startListening({Function(String result)? onResult})`: Listens for live developer speech.
- `Future<void> stopListening()`: Stops speech capture.
- `static const List<String> presetCommands`: Quick-touch chips ("Fix null pointer and run tests", "Handle missing 'role' key", etc.).

### 3. `DiagnosticService` (`lib/services/diagnostic_service.dart`)
- `InferenceBackend activeBackend`: Supports `onDeviceGemma2B`, `onDevicePhi3Mini`, `cloudGroqLlama3`, `cloudGeminiFlash`.
- `String buildPrompt(...)`: Formats SLM prompts using standard turns (`<start_of_turn>user ... <end_of_turn>`).
- `Future<DiagnosticResult> analyze(...)`: Executes inference with fallback engine.
- `DiagnosticResult parseJsonResponse(String rawResponse)`: Validates and parses raw JSON strings.

### 4. `BridgeService` (`lib/services/bridge_service.dart`)
- `static Future<bool> copyDiffToClipboard(String patchDiff)`: Copies patch diff to system clipboard (scored via Office Kit shared clipboard).
- `static Future<FilePushResult> pushToBridge(String patchDiff, {String filename = "fix.patch"})`: Saves patch file into `inbox_patches/` shared transfer folder.

---

## 🚀 Key Actions on Inspector Screen

1. **"Copy Diff"**: Copies `patch_diff` directly to the system clipboard for immediate desktop pasting or Office Kit shared clipboard sync.
2. **"Push to Bridge"**: Writes the unified patch to `inbox_patches/fix.patch` for automated pickup by desktop runners or bridge sidecars.
3. **"View JSON"**: Displays the raw, unadulterated JSON payload matching the contract.

---

## 🧪 Testing & Execution

To run unit tests:
```bash
cd mobile-client
flutter test
```
