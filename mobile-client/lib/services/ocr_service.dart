import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/ocr_box.dart';

/// Service responsible for real-time OCR text recognition and parsing
/// stack traces, line numbers, target files, and error types from camera frames.
class OcrService {
  TextRecognizer? _textRecognizer;
  bool _isProcessing = false;

  OcrService() {
    _initRecognizer();
  }

  void _initRecognizer() {
    try {
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    } catch (e) {
      debugPrint('Warning: Google ML Kit TextRecognizer init failed: $e');
    }
  }

  bool get isProcessing => _isProcessing;

  /// Processes an ML Kit InputImage from the live camera stream
  Future<OcrAnalysisPayload> processImage(InputImage inputImage) async {
    if (_isProcessing) {
      return const OcrAnalysisPayload(rawText: '', boxes: []);
    }
    _isProcessing = true;

    try {
      if (_textRecognizer == null) {
        _initRecognizer();
      }

      final recognizedText = await _textRecognizer?.processImage(inputImage);
      if (recognizedText == null || recognizedText.text.isEmpty) {
        return const OcrAnalysisPayload(rawText: '', boxes: []);
      }

      return parseRecognizedText(recognizedText);
    } catch (e) {
      debugPrint('Error during OCR processing: $e');
      return const OcrAnalysisPayload(rawText: '', boxes: []);
    } finally {
      _isProcessing = false;
    }
  }

  /// Parses ML Kit RecognizedText into structured OcrAnalysisPayload with error metadata
  OcrAnalysisPayload parseRecognizedText(RecognizedText recognizedText) {
    final rawText = recognizedText.text;
    final List<OcrBoundingBox> boxes = [];

    String? detectedError;
    String? detectedFile;
    int? detectedLine;
    final List<String> stackLines = [];

    // Regex patterns for stack traces across Python, JS/TS, Java, Go, Rust
    final pythonFileRegex = RegExp(r'File\s+"([^"]+)",\s+line\s+(\d+)', caseSensitive: false);
    final jsStackRegex = RegExp(r'(?:at\s+(?:.*?\s+\()?(.*?):(\d+):\d+\)?)', caseSensitive: false);
    final javaStackRegex = RegExp(r'at\s+[a-zA-Z0-9_$.]+\(([a-zA-Z0-9_]+\.java):(\d+)\)', caseSensitive: false);
    final genericFileRegex = RegExp(r'([\w\/\.\-]+\.(?:py|js|ts|tsx|jsx|java|kt|go|rs|c|cpp)):(\d+)', caseSensitive: false);
    
    // Error classification regex
    final errorPatternRegex = RegExp(
      r'((?:KeyError|NullPointerException|TypeError|AttributeError|IndexError|ValueError|'
      r'SyntaxError|NameError|ZeroDivisionError|RuntimeError|ReferenceError|'
      r'UnhandledPromiseRejection|AssertionError|Exception)):?\s*(.*)',
      caseSensitive: false,
    );

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final lineText = line.text.trim();
        bool isError = false;
        bool isStack = false;

        // Check for error header
        final errorMatch = errorPatternRegex.firstMatch(lineText);
        if (errorMatch != null) {
          isError = true;
          detectedError ??= '${errorMatch.group(1)}: ${errorMatch.group(2) ?? ''}'.trim();
        }

        // Check for Python stack trace
        final pyMatch = pythonFileRegex.firstMatch(lineText);
        if (pyMatch != null) {
          isStack = true;
          detectedFile ??= pyMatch.group(1);
          detectedLine ??= int.tryParse(pyMatch.group(2) ?? '');
          stackLines.add(lineText);
        }

        // Check for JS stack trace
        final jsMatch = jsStackRegex.firstMatch(lineText);
        if (jsMatch != null && !isStack) {
          isStack = true;
          detectedFile ??= jsMatch.group(1);
          detectedLine ??= int.tryParse(jsMatch.group(2) ?? '');
          stackLines.add(lineText);
        }

        // Check for Java stack trace
        final javaMatch = javaStackRegex.firstMatch(lineText);
        if (javaMatch != null && !isStack) {
          isStack = true;
          detectedFile ??= javaMatch.group(1);
          detectedLine ??= int.tryParse(javaMatch.group(2) ?? '');
          stackLines.add(lineText);
        }

        // Check generic file:line pattern
        final genericMatch = genericFileRegex.firstMatch(lineText);
        if (genericMatch != null && !isStack) {
          isStack = true;
          detectedFile ??= genericMatch.group(1);
          detectedLine ??= int.tryParse(genericMatch.group(2) ?? '');
          stackLines.add(lineText);
        }

        boxes.add(
          OcrBoundingBox(
            text: lineText,
            boundingBox: line.boundingBox,
            cornerPoints: line.cornerPoints,
            isErrorSignature: isError,
            isStackTrace: isStack,
          ),
        );
      }
    }

    return OcrAnalysisPayload(
      rawText: rawText,
      boxes: boxes,
      detectedErrorType: detectedError,
      detectedTargetFile: detectedFile,
      detectedLineNumber: detectedLine,
      stackTraceLines: stackLines,
    );
  }

  /// Parses raw text string directly (useful for testing or fallback manual scans)
  OcrAnalysisPayload parseRawTextString(String text) {
    final lines = text.split('\n');
    String? detectedError;
    String? detectedFile;
    int? detectedLine;
    final List<String> stackLines = [];
    final List<OcrBoundingBox> boxes = [];

    final pythonFileRegex = RegExp(r'File\s+"([^"]+)",\s+line\s+(\d+)', caseSensitive: false);
    final errorPatternRegex = RegExp(
      r'((?:KeyError|NullPointerException|TypeError|AttributeError|IndexError|ValueError|'
      r'SyntaxError|NameError|ZeroDivisionError|RuntimeError|ReferenceError)):?\s*(.*)',
      caseSensitive: false,
    );

    double topOffset = 50.0;
    for (final lineText in lines) {
      if (lineText.trim().isEmpty) continue;
      bool isError = false;
      bool isStack = false;

      final errorMatch = errorPatternRegex.firstMatch(lineText);
      if (errorMatch != null) {
        isError = true;
        detectedError ??= '${errorMatch.group(1)}: ${errorMatch.group(2) ?? ''}'.trim();
      }

      final pyMatch = pythonFileRegex.firstMatch(lineText);
      if (pyMatch != null) {
        isStack = true;
        detectedFile ??= pyMatch.group(1);
        detectedLine ??= int.tryParse(pyMatch.group(2) ?? '');
        stackLines.add(lineText);
      }

      boxes.add(
        OcrBoundingBox(
          text: lineText,
          boundingBox: Rect.fromLTWH(20, topOffset, 300, 24),
          isErrorSignature: isError,
          isStackTrace: isStack,
        ),
      );
      topOffset += 28.0;
    }

    return OcrAnalysisPayload(
      rawText: text,
      boxes: boxes,
      detectedErrorType: detectedError,
      detectedTargetFile: detectedFile,
      detectedLineNumber: detectedLine,
      stackTraceLines: stackLines,
    );
  }

  /// Sample mock terminal frame representing the hackathon challenge prompt
  static String sampleKeyErrorTerminalOutput() {
    return '''
Traceback (most recent call last):
  File "app.py", line 2, in process_user_data
    return {'name': user_dict['name'], 'role': user_dict['role'].upper(), 'status': 'active'}
KeyError: 'role'
''';
  }

  void dispose() {
    _textRecognizer?.close();
  }
}
