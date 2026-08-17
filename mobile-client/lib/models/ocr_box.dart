import 'dart:ui';

/// Represents a detected visual text bounding box from Google ML Kit OCR
class OcrBoundingBox {
  final String text;
  final Rect boundingBox;
  final List<Point<int>> cornerPoints;
  final bool isErrorSignature;
  final bool isStackTrace;

  const OcrBoundingBox({
    required this.text,
    required this.boundingBox,
    this.cornerPoints = const [],
    this.isErrorSignature = false,
    this.isStackTrace = false,
  });
}

/// Represents the structured OCR extraction payload
class OcrAnalysisPayload {
  final String rawText;
  final List<OcrBoundingBox> boxes;
  final String? detectedErrorType;
  final String? detectedTargetFile;
  final int? detectedLineNumber;
  final List<String> stackTraceLines;

  const OcrAnalysisPayload({
    required this.rawText,
    required this.boxes,
    this.detectedErrorType,
    this.detectedTargetFile,
    this.detectedLineNumber,
    this.stackTraceLines = const [],
  });

  bool get hasError => detectedErrorType != null || stackTraceLines.isNotEmpty;

  @override
  String toString() {
    return 'OcrAnalysisPayload(error: $detectedErrorType, file: $detectedTargetFile:$detectedLineNumber, traces: ${stackTraceLines.length})';
  }
}
