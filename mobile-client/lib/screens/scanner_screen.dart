import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/diagnostic_result.dart';
import '../models/ocr_box.dart';
import '../services/diagnostic_service.dart';
import '../services/ocr_service.dart';
import '../services/voice_service.dart';
import '../widgets/ocr_overlay_painter.dart';
import '../widgets/pulse_mic_button.dart';
import 'patch_inspector_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;

  final OcrService _ocrService = OcrService();
  final VoiceService _voiceService = VoiceService();
  final DiagnosticService _diagnosticService = DiagnosticService();

  OcrAnalysisPayload _currentPayload = const OcrAnalysisPayload(rawText: '', boxes: []);
  String _currentVoiceCommand = '';
  bool _isAnalyzing = false;
  bool _isCameraStreaming = false;
  DateTime _lastFrameTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // 1. Initialize Camera
    await _initCamera();

    // 2. Initialize Voice Service
    await _voiceService.initialize();
    _voiceService.onStateChanged = (isListening, transcript) {
      if (mounted) {
        setState(() {
          _currentVoiceCommand = transcript;
        });
      }
    };
  }

  Future<void> _initCamera() async {
    try {
      await Permission.camera.request();
      await Permission.microphone.request();

      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        final backCamera = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        );

        _cameraController = CameraController(
          backCamera,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );

        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
          _startCameraStream();
        }
      } else {
        debugPrint('No cameras available, enabling mock terminal viewfinder mode.');
        _loadMockTerminalPayload();
      }
    } catch (e) {
      debugPrint('Camera initialization failed: $e. Falling back to simulated viewfinder.');
      _loadMockTerminalPayload();
    }
  }

  void _startCameraStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_isCameraStreaming) return;

    _isCameraStreaming = true;
    _cameraController!.startImageStream((CameraImage image) {
      // Throttle OCR frames to ~300ms intervals to optimize CPU/NPU on loaner iQOO phone
      final now = DateTime.now();
      if (now.difference(_lastFrameTime).inMilliseconds < 350) return;
      _lastFrameTime = now;

      _processCameraFrame(image);
    });
  }

  Future<void> _processCameraFrame(CameraImage image) async {
    if (_ocrService.isProcessing) return;

    try {
      final inputImage = _buildInputImageFromCamera(image);
      if (inputImage != null) {
        final payload = await _ocrService.processImage(inputImage);
        if (mounted && payload.rawText.isNotEmpty) {
          setState(() {
            _currentPayload = payload;
          });
        }
      }
    } catch (e) {
      debugPrint('Frame processing error: $e');
    }
  }

  InputImage? _buildInputImageFromCamera(CameraImage image) {
    if (_cameraController == null) return null;
    final camera = _cameraController!.description;

    final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    // Use first plane byte buffer
    final bytes = image.planes.isNotEmpty ? image.planes[0].bytes : Uint8List(0);

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
      ),
    );
  }

  void _loadMockTerminalPayload() {
    final sampleText = OcrService.sampleKeyErrorTerminalOutput();
    final payload = _ocrService.parseRawTextString(sampleText);
    setState(() {
      _currentPayload = payload;
      _currentVoiceCommand = "Fix missing 'role' key with fallback to 'user'";
    });
  }

  Future<void> _triggerAnalysis() async {
    if (_isAnalyzing) return;

    setState(() {
      _isAnalyzing = true;
    });

    try {
      // Ensure we have a payload to analyze
      var payloadToAnalyze = _currentPayload;
      if (payloadToAnalyze.rawText.isEmpty) {
        _loadMockTerminalPayload();
        payloadToAnalyze = _currentPayload;
      }

      final result = await _diagnosticService.analyze(
        ocrPayload: payloadToAnalyze,
        voiceCommand: _currentVoiceCommand,
      );

      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });

        // Navigate to Patch Inspector Screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PatchInspectorScreen(diagnosticResult: result),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _ocrService.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
              ),
              child: const Icon(Icons.psychology_outlined, color: Color(0xFF38BDF8), size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PATCHPILOT',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Color(0xFFF8FAFC),
                  ),
                ),
                Text(
                  'Vision & Voice Copilot',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Backend Model Selector Chip
          PopupMenuButton<InferenceBackend>(
            initialValue: _diagnosticService.activeBackend,
            onSelected: (backend) {
              setState(() {
                _diagnosticService.activeBackend = backend;
              });
            },
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF334155)),
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Color(0xFF38BDF8), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _diagnosticService.activeBackend == InferenceBackend.onDeviceGemma2B
                        ? 'Gemma-2B (NPU)'
                        : _diagnosticService.activeBackend == InferenceBackend.onDevicePhi3Mini
                            ? 'Phi-3 (NPU)'
                            : 'Groq Cloud',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8), size: 16),
                ],
              ),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: InferenceBackend.onDeviceGemma2B,
                child: Text('⚡ Gemma-2B (On-Device SLM)', style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
              const PopupMenuItem(
                value: InferenceBackend.onDevicePhi3Mini,
                child: Text('⚡ Phi-3 Mini (On-Device SLM)', style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
              const PopupMenuItem(
                value: InferenceBackend.cloudGroqLlama3,
                child: Text('☁️ Groq Llama-3 (Cloud Fallback)', style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ],
          ),

          // Preset Demo Injector
          IconButton(
            icon: const Icon(Icons.auto_fix_high, color: Color(0xFFF59E0B)),
            tooltip: 'Inject Hackathon Demo Frame',
            onPressed: () {
              _loadMockTerminalPayload();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Injected KeyError Challenge Stack Trace & Voice Prompt'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Camera Viewfinder or Simulated Code Canvas
          Positioned.fill(
            child: _isCameraInitialized && _cameraController != null
                ? CameraPreview(
                    _cameraController!,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return CustomPaint(
                          size: Size(constraints.maxWidth, constraints.maxHeight),
                          painter: OcrOverlayPainter(
                            boxes: _currentPayload.boxes,
                            previewSize: _cameraController!.value.previewSize ??
                                Size(constraints.maxWidth, constraints.maxHeight),
                            widgetSize: Size(constraints.maxWidth, constraints.maxHeight),
                          ),
                        );
                      },
                    ),
                  )
                : _buildSimulatedViewfinder(),
          ),

          // 2. Real-time Status Overlay HUD
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _buildHudStatusPills(),
          ),

          // 3. Bottom Controls Panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomControlPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulatedViewfinder() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF020617),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  const Text(
                    'iQOO Loaner Device - Terminal Viewfinder',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF1E293B), height: 20),
              Text(
                _currentPayload.rawText.isNotEmpty
                    ? _currentPayload.rawText
                    : OcrService.sampleKeyErrorTerminalOutput(),
                style: const TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHudStatusPills() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentPayload.hasError)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.4), blurRadius: 8),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _currentPayload.detectedErrorType ?? 'Error Line Detected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (_currentPayload.detectedTargetFile != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withOpacity(0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF38BDF8), size: 14),
                const SizedBox(width: 6),
                Text(
                  '${_currentPayload.detectedTargetFile}${_currentPayload.detectedLineNumber != null ? ':${_currentPayload.detectedLineNumber}' : ''}',
                  style: const TextStyle(
                    color: Color(0xFFE0F2FE),
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBottomControlPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.95),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        border: const Border(
          top: BorderSide(color: Color(0xFF1E293B), width: 1.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Voice Command Transcript Bubble
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _voiceService.isListening
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF334155),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _voiceService.isListening ? Icons.graphic_eq : Icons.record_voice_over,
                  color: _voiceService.isListening ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _currentVoiceCommand.isNotEmpty
                        ? _currentVoiceCommand
                        : (_voiceService.isListening ? 'Listening...' : 'Tap mic or speak command...'),
                    style: TextStyle(
                      color: _currentVoiceCommand.isNotEmpty
                          ? const Color(0xFFF1F5F9)
                          : const Color(0xFF64748B),
                      fontSize: 13,
                      fontStyle: _currentVoiceCommand.isEmpty ? FontStyle.italic : FontStyle.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Preset Voice Chips for quick touch access
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: VoiceService.presetCommands.map((preset) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Color(0xFF334155)),
                    label: Text(
                      preset,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                    onPressed: () {
                      _voiceService.setManualCommand(preset);
                      setState(() {
                        _currentVoiceCommand = preset;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // Action Row: Pulse Mic Button + Analyze CTA
          Row(
            children: [
              PulseMicButton(
                isListening: _voiceService.isListening,
                onTap: () {
                  if (_voiceService.isListening) {
                    _voiceService.stopListening();
                  } else {
                    _voiceService.startListening(
                      onResult: (transcript) {
                        setState(() {
                          _currentVoiceCommand = transcript;
                        });
                      },
                    );
                  }
                  setState(() {});
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isAnalyzing ? null : _triggerAnalysis,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 4,
                  ),
                  child: _isAnalyzing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            SizedBox(width: 10),
                            Text('RUNNING SLM INFERENCE...'),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'ANALYZE & GENERATE PATCH',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
