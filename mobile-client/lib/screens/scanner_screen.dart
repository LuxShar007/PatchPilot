import 'dart:async';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/ocr_box.dart';
import '../services/bridge_service.dart';
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

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;

  final OcrService _ocrService = OcrService();
  final VoiceService _voiceService = VoiceService();
  final DiagnosticService _diagnosticService = DiagnosticService();

  OcrAnalysisPayload _currentPayload =
      const OcrAnalysisPayload(rawText: '', boxes: []);
  String _currentVoiceCommand = '';
  bool _isAnalyzing = false;
  bool _isCameraStreaming = false;
  DateTime _lastFrameTime = DateTime.now();
  BridgePingResult? _bridgePing;
  bool _isCheckingBridge = false;

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

    // 3. Ping Laptop Bridge Daemon
    _checkBridgeHealth();
  }

  Future<void> _checkBridgeHealth() async {
    if (_isCheckingBridge) return;
    setState(() => _isCheckingBridge = true);
    final ping = await BridgeService.checkHealth();
    if (mounted) {
      setState(() {
        _bridgePing = ping;
        _isCheckingBridge = false;
      });
    }
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
        debugPrint(
            'No cameras available, enabling mock terminal viewfinder mode.');
        _loadMockTerminalPayload();
      }
    } catch (e) {
      debugPrint(
          'Camera initialization failed: $e. Falling back to simulated viewfinder.');
      _loadMockTerminalPayload();
    }
  }

  void _startCameraStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_isCameraStreaming) return;

    if (!kIsWeb && _cameraController!.value.isInitialized) {
      _isCameraStreaming = true;
      _cameraController!.startImageStream((CameraImage image) {
        // Throttle OCR frames to ~300ms intervals to optimize CPU/NPU on loaner iQOO phone
        final now = DateTime.now();
        if (now.difference(_lastFrameTime).inMilliseconds < 350) return;
        _lastFrameTime = now;

        _processCameraFrame(image);
      });
    } else {
      debugPrint(
          "Web platform detected: Image streaming bypassed for web preview.");
    }
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

    final imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg;

    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21;

    final allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow:
            image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
      ),
    );
  }

  void _loadMockTerminalPayload() {
    _injectDemoChallenge('keyerror');
  }

  void _injectDemoChallenge(String key) {
    String sampleText;
    String voicePrompt;
    String name;

    switch (key) {
      case 'zerodiv':
        sampleText = OcrService.sampleZeroDivisionTerminalOutput();
        voicePrompt = 'Guard against zero denominator';
        name = 'ZeroDivisionError (math_ops.py:18)';
        break;
      case 'typeerror':
        sampleText = OcrService.sampleTypeErrorTerminalOutput();
        voicePrompt = 'Add optional chaining and null check';
        name = 'TypeError (UserList.tsx:42)';
        break;
      case 'indexerror':
        sampleText = OcrService.sampleIndexErrorTerminalOutput();
        voicePrompt = 'Add bounds check for index';
        name = 'IndexError (cache.py:35)';
        break;
      case 'nullpointer':
        sampleText = OcrService.sampleNullPointerTerminalOutput();
        voicePrompt = 'Add null check before getProfile()';
        name = 'NullPointerException (UserService.java:55)';
        break;
      case 'keyerror':
      default:
        sampleText = OcrService.sampleKeyErrorTerminalOutput();
        voicePrompt = "Fix missing 'role' key with fallback to 'user'";
        name = 'KeyError "role" (app.py:2)';
        break;
    }

    final payload = _ocrService.parseRawTextString(sampleText);
    setState(() {
      _currentPayload = payload;
      _currentVoiceCommand = voicePrompt;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.auto_fix_high, color: Color(0xFF10B981), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Injected: $name',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF18181B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _triggerAnalysis() async {
    if (_isAnalyzing) return;

    setState(() {
      _isAnalyzing = true;
    });

    try {
      OcrAnalysisPayload payloadToAnalyze = _currentPayload;

      // If camera is initialized, capture a razor-sharp snapshot to guarantee full OCR accuracy
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        try {
          if (_isCameraStreaming) {
            await _cameraController!.stopImageStream();
            _isCameraStreaming = false;
          }
          final xfile = await _cameraController!.takePicture();
          final inputImage = InputImage.fromFilePath(xfile.path);
          final snapshotPayload = await _ocrService.processImage(inputImage);
          if (snapshotPayload.rawText.trim().isNotEmpty) {
            payloadToAnalyze = snapshotPayload;
            _currentPayload = snapshotPayload;
          }
        } catch (e) {
          debugPrint('Snapshot capture error: $e');
        } finally {
          _startCameraStream();
        }
      }

      // If no text was detected, notify user directly without silent fallback
      if (payloadToAnalyze.rawText.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No terminal text detected. Please aim camera at the error log and tap again.'),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final result = await _diagnosticService.analyzeError(
        scannedText: payloadToAnalyze.rawText,
        userCommand: _currentVoiceCommand,
      );

      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });

        // Navigate to Patch Inspector Screen and await return
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                PatchInspectorScreen(diagnosticResult: result),
          ),
        );

        // Clear scanned buffer and voice state upon returning so user can scan a new error immediately
        if (mounted) {
          setState(() {
            _currentPayload = const OcrAnalysisPayload(rawText: '', boxes: []);
            _currentVoiceCommand = '';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Analysis failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPasteLogModal() {
    final logController = TextEditingController();
    final commandController = TextEditingController(text: _currentVoiceCommand);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFFCFCFB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Modal Handle Bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7E7E4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Modal Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F2EF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE7E7E4)),
                      ),
                      child: const Icon(Icons.code,
                          color: Color(0xFF111111), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Paste & Solve Error Log',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: Color(0xFF111111),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Paste any terminal stack trace to analyze & patch',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF6B6B6B)),
                          ),
                        ],
                      ),
                    ),
                    // Quick Paste from Clipboard
                    OutlinedButton.icon(
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data != null && data.text != null) {
                          setModalState(() {
                            logController.text = data.text!;
                          });
                        }
                      },
                      icon: const Icon(Icons.content_paste,
                          size: 14, color: Color(0xFF111111)),
                      label: const Text('Paste',
                          style: TextStyle(
                              color: Color(0xFF111111),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE7E7E4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Quick Sample Presets
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        backgroundColor: const Color(0xFFF3F2EF),
                        side: const BorderSide(color: Color(0xFFE7E7E4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999)),
                        label: const Text('ZeroDivisionError',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111111))),
                        onPressed: () {
                          setModalState(() {
                            logController.text =
                                '''Traceback (most recent call last):
  File "math_ops.py", line 18, in calculate_ratio
    return numerator / denominator
ZeroDivisionError: division by zero''';
                            commandController.text =
                                'Guard against zero denominator';
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        backgroundColor: const Color(0xFFF3F2EF),
                        side: const BorderSide(color: Color(0xFFE7E7E4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999)),
                        label: const Text('TypeError (React/TS)',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111111))),
                        onPressed: () {
                          setModalState(() {
                            logController.text =
                                '''TypeError: Cannot read properties of undefined (reading 'map')
    at renderUserList (src/components/UserList.tsx:42:15)''';
                            commandController.text =
                                'Add optional chaining and null check';
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        backgroundColor: const Color(0xFFF3F2EF),
                        side: const BorderSide(color: Color(0xFFE7E7E4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999)),
                        label: const Text("KeyError 'role'",
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111111))),
                        onPressed: () {
                          setModalState(() {
                            logController.text =
                                '''Traceback (most recent call last):
  File "app.py", line 2, in process_user_data
    return {'name': user_dict['name'], 'role': user_dict['role'].upper(), 'status': 'active'}
KeyError: 'role' ''';
                            commandController.text =
                                'Fix missing role key with fallback default';
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        backgroundColor: const Color(0xFFF3F2EF),
                        side: const BorderSide(color: Color(0xFFE7E7E4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999)),
                        label: const Text('IndexError',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111111))),
                        onPressed: () {
                          setModalState(() {
                            logController.text =
                                '''Traceback (most recent call last):
  File "cache.py", line 35, in get_item
    return items[idx]
IndexError: list index out of range''';
                            commandController.text =
                                'Add bounds check for index';
                          });
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Multi-line Terminal Text Field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: logController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFFF4F4F5),
                        fontSize: 12,
                        height: 1.4,
                      ),
                      decoration: const InputDecoration(
                        hintText:
                            'Paste stack trace or terminal error logs here...',
                        hintStyle: TextStyle(
                            color: Color(0xFF71717A),
                            fontFamily: 'monospace',
                            fontSize: 12),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Voice / Custom Developer Command Input
                TextField(
                  controller: commandController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.mic_none,
                        color: Color(0xFF111111), size: 18),
                    hintText:
                        'Optional instructions (e.g. "Add fallback check")',
                    hintStyle: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF868381)),
                    filled: true,
                    fillColor: const Color(0xFFF3F2EF),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE7E7E4)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE7E7E4)),
                    ),
                  ),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),

                const SizedBox(height: 14),

                // Primary Submit CTA
                ElevatedButton(
                  onPressed: () async {
                    final text = logController.text.trim();
                    if (text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Please paste or enter error log text first'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }

                    final nav = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);

                    Navigator.pop(modalContext);

                    setState(() {
                      _isAnalyzing = true;
                    });

                    try {
                      final customCmd = commandController.text.trim();
                      final result = await _diagnosticService.analyzeError(
                        scannedText: text,
                        userCommand: customCmd.isNotEmpty ? customCmd : null,
                      );

                      if (mounted) {
                        setState(() {
                          _isAnalyzing = false;
                        });

                        await nav.push(
                          MaterialPageRoute(
                            builder: (context) =>
                                PatchInspectorScreen(diagnosticResult: result),
                          ),
                        );

                        if (mounted) {
                          setState(() {
                            _currentPayload = const OcrAnalysisPayload(
                                rawText: '', boxes: []);
                            _currentVoiceCommand = '';
                          });
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() {
                          _isAnalyzing = false;
                        });
                        messenger.showSnackBar(
                          SnackBar(
                              content: Text('Analysis failed: $e'),
                              backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111111),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bolt, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'ANALYZE & GENERATE FIX',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            letterSpacing: -0.2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showBridgeQuickPanel() {
    final ipController =
        TextEditingController(text: BridgeService.activeLaptopIp);
    bool isResetting = false;
    bool isTesting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => StatefulBuilder(
        builder: (context, setPanelState) {
          final isOnline = _bridgePing?.isOnline ?? false;

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFFCFCFB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7E7E4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isOnline
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isOnline
                            ? Icons.wifi_tethering
                            : Icons.wifi_tethering_off,
                        color: isOnline
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Laptop Bridge Live Control',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: Color(0xFF111111),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isOnline
                                ? 'Connected: ${BridgeService.activeLaptopIp}:8000 (${_bridgePing?.latencyMs}ms)'
                                : 'Offline / Unreachable (${BridgeService.activeLaptopIp}:8000)',
                            style: TextStyle(
                              fontSize: 12,
                              color: isOnline
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          color: Color(0xFF111111), size: 20),
                      tooltip: 'Ping now',
                      onPressed: () async {
                        await _checkBridgeHealth();
                        setPanelState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Quick Host Presets
                const Text(
                  'Quick Host Presets:',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B6B6B)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ActionChip(
                      label: const Text('10.0.2.2 (Emulator)',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      backgroundColor: const Color(0xFFF3F2EF),
                      side: const BorderSide(color: Color(0xFFE7E7E4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9999)),
                      onPressed: () async {
                        ipController.text = '10.0.2.2';
                        BridgeService.activeLaptopIp = '10.0.2.2';
                        await _checkBridgeHealth();
                        setPanelState(() {});
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      label: const Text('127.0.0.1 (Localhost)',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      backgroundColor: const Color(0xFFF3F2EF),
                      side: const BorderSide(color: Color(0xFFE7E7E4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9999)),
                      onPressed: () async {
                        ipController.text = '127.0.0.1';
                        BridgeService.activeLaptopIp = '127.0.0.1';
                        await _checkBridgeHealth();
                        setPanelState(() {});
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // IP Input Row
                TextField(
                  controller: ipController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.computer,
                        size: 18, color: Color(0xFF111111)),
                    hintText: 'Enter Laptop IP (e.g. 192.168.1.100)',
                    filled: true,
                    fillColor: const Color(0xFFF3F2EF),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE7E7E4)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE7E7E4)),
                    ),
                    suffixIcon: TextButton(
                      onPressed: () async {
                        final newIp = ipController.text.trim();
                        if (newIp.isNotEmpty) {
                          BridgeService.activeLaptopIp = newIp;
                          await _checkBridgeHealth();
                          setPanelState(() {});
                          setState(() {});
                        }
                      },
                      child: const Text('Connect',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111111))),
                    ),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                const SizedBox(height: 16),
                // Remote Actions: Reset Testbed & Run CI Tests
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isResetting
                            ? null
                            : () async {
                                setPanelState(() => isResetting = true);
                                final res =
                                    await BridgeService.resetRemoteTestbed();
                                setPanelState(() => isResetting = false);
                                await _checkBridgeHealth();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          res['message']?.toString() ??
                                              'Testbed reset!'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        icon: isResetting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.restore,
                                size: 16, color: Color(0xFF111111)),
                        label: const Text('Reset Testbed',
                            style: TextStyle(
                                color: Color(0xFF111111),
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE7E7E4)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isTesting
                            ? null
                            : () async {
                                setPanelState(() => isTesting = true);
                                final res =
                                    await BridgeService.runRemoteTests();
                                setPanelState(() => isTesting = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('Test Run: ${res['status']}'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        icon: isTesting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.play_arrow,
                                size: 16, color: Color(0xFF111111)),
                        label: const Text('Run Tests',
                            style: TextStyle(
                                color: Color(0xFF111111),
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE7E7E4)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      if (mounted) {
        _cameraController?.dispose();
        _cameraController = null;
      }
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (mounted) {
      _cameraController?.dispose();
      _cameraController = null;
    }
    _ocrService.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBridgeOnline = _bridgePing?.isOnline ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F5),
        elevation: 0,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RecTrace',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: Color(0xFF111111),
                ),
              ),
              Text(
                'Developer Diagnostic Copilot',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B6B6B),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // 1-Tap Quick Reset Testbed for Live Judging Demos
          IconButton(
            icon: const Icon(Icons.restore, color: Color(0xFF111111), size: 20),
            tooltip: 'Reset Laptop Testbed to Baseline Bug',
            onPressed: () async {
              final res = await BridgeService.resetRemoteTestbed();
              await _checkBridgeHealth();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.refresh, color: Color(0xFF10B981), size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(res['message']?.toString() ?? 'Laptop testbed reset to baseline!')),
                      ],
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),

          // Live Bridge Ping Chip Button
          GestureDetector(
            onTap: _showBridgeQuickPanel,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: const Color(0xFFE7E7E4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isBridgeOnline
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isBridgeOnline
                        ? '${_bridgePing?.latencyMs}ms'
                        : 'Bridge Offline',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isBridgeOnline
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Auralis Pill Chip Backend Model Selector
          PopupMenuButton<InferenceBackend>(
            initialValue: _diagnosticService.activeBackend,
            onSelected: (backend) {
              setState(() {
                _diagnosticService.activeBackend = backend;
              });
            },
            color: const Color(0xFFFCFCFB),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE7E7E4)),
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: const Color(0xFFE7E7E4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulsing emerald live status dot
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF10B981),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _diagnosticService.activeBackend ==
                            InferenceBackend.onDeviceGemma2B
                        ? 'Gemma-2B'
                        : _diagnosticService.activeBackend ==
                                InferenceBackend.onDevicePhi3Mini
                            ? 'Phi-3'
                            : 'Groq Cloud',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111111),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.keyboard_arrow_down,
                      color: Color(0xFF6B6B6B), size: 15),
                ],
              ),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: InferenceBackend.onDeviceGemma2B,
                child: Text('⚡ Gemma-2B (On-Device SLM)',
                    style: TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              const PopupMenuItem(
                value: InferenceBackend.onDevicePhi3Mini,
                child: Text('⚡ Phi-3 Mini (On-Device SLM)',
                    style: TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              const PopupMenuItem(
                value: InferenceBackend.cloudGroqLlama3,
                child: Text('☁️ Groq Llama-3 (Cloud Fallback)',
                    style: TextStyle(color: Color(0xFF6B6B6B), fontSize: 13)),
              ),
            ],
          ),

          // Paste Log & Solve Button
          Container(
            margin: const EdgeInsets.only(right: 4, top: 10, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE7E7E4)),
            ),
            child: IconButton(
              icon: const Icon(Icons.content_paste_go,
                  color: Color(0xFF111111), size: 17),
              tooltip: 'Paste & Solve Error Log',
              onPressed: _showPasteLogModal,
            ),
          ),

          // Demo Injector Popup Menu Button
          Container(
            margin: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE7E7E4)),
            ),
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.auto_fix_high,
                  color: Color(0xFF111111), size: 18),
              tooltip: 'Inject Demo Challenge',
              color: const Color(0xFFFCFCFB),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE7E7E4)),
              ),
              onSelected: (key) {
                _injectDemoChallenge(key);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'keyerror',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🐍 KeyError: "role"',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF111111))),
                      Text('app.py:2 (Python Missing Dict Key)',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'zerodiv',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('➗ ZeroDivisionError',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF111111))),
                      Text('math_ops.py:18 (Division by Zero)',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'typeerror',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚛️ TypeError (Undefined Map)',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF111111))),
                      Text('UserList.tsx:42 (React / TypeScript)',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'indexerror',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📦 IndexError: Out of Range',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF111111))),
                      Text('cache.py:35 (List Bounds Violation)',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'nullpointer',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('☕ NullPointerException',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF111111))),
                      Text('UserService.java:55 (Java Null Reference)',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Camera Viewfinder or Auralis-style Gradient Aura Viewfinder
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F2EF),
                    borderRadius: BorderRadius.circular(28),
                    border:
                        Border.all(color: const Color(0xFFE7E7E4), width: 1.2),
                  ),
                  child: _isCameraInitialized && _cameraController != null
                      ? CameraPreview(
                          _cameraController!,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return CustomPaint(
                                size: Size(constraints.maxWidth,
                                    constraints.maxHeight),
                                painter: OcrOverlayPainter(
                                  boxes: _currentPayload.boxes,
                                  previewSize:
                                      _cameraController!.value.previewSize ??
                                          Size(constraints.maxWidth,
                                              constraints.maxHeight),
                                  widgetSize: Size(constraints.maxWidth,
                                      constraints.maxHeight),
                                ),
                              );
                            },
                          ),
                        )
                      : _buildAuralisHeroViewfinder(),
                ),
              ),
            ),
          ),

          // 2. Real-time Status Overlay HUD (Top)
          Positioned(
            top: 24,
            left: 32,
            right: 32,
            child: _buildHudStatusPills(),
          ),

          // 3. Bottom Glassmorphism Controls Dock
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildBottomControlPanel(),
          ),
        ],
      ),
    );
  }

  /// Auralis-style clean aesthetic hero canvas with glowing multi-color aura mesh
  Widget _buildAuralisHeroViewfinder() {
    return Stack(
      children: [
        // Background Ceramic Panel
        Container(
          color: const Color(0xFFF3F2EF),
        ),

        // Glowing Multi-color Aura Mesh (Rose, Indigo, Purple, Teal, Sky Blue)
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: const Offset(-60, -30),
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0xFFF43F5E), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(30, -20),
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0xFF6366F1), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(-20, 50),
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0xFF14B8A6), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(70, 30),
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0xFF38BDF8), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Blur Filter to turn orbs into soft aura mesh
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 45, sigmaY: 45),
            child: Container(color: Colors.white.withValues(alpha: 0.25)),
          ),
        ),

        // Central Glassmorphic Widget Container (Matching Auralis screenshot)
        Center(
          child: SingleChildScrollView(
            child: Container(
              width: 380,
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 36,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Widget Header: Identifier & Status Pill
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NEURAL ENGINE V4.2 PRO',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: Color(0xFF6B6B6B),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'On-Device SLM Viewfinder',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111111),
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.25)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lens, color: Color(0xFF10B981), size: 7),
                            SizedBox(width: 5),
                            Text(
                              'STUDIO MODE',
                              style: TextStyle(
                                color: Color(0xFF047857),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Spectral Visualizer Bars
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildWaveformBar(24, const Color(0xFF3B82F6)),
                      _buildWaveformBar(38, const Color(0xFF3B82F6)),
                      _buildWaveformBar(62, const Color(0xFF6366F1)),
                      _buildWaveformBar(52, const Color(0xFF6366F1)),
                      _buildWaveformBar(80, const Color(0xFF8B5CF6)),
                      _buildWaveformBar(92, const Color(0xFFA855F7)),
                      _buildWaveformBar(68, const Color(0xFF8B5CF6)),
                      _buildWaveformBar(44, const Color(0xFF3B82F6)),
                      _buildWaveformBar(58, const Color(0xFF3B82F6)),
                      _buildWaveformBar(30, const Color(0xFF06B6D4)),
                      _buildWaveformBar(48, const Color(0xFF14B8A6)),
                      _buildWaveformBar(20, const Color(0xFF14B8A6)),
                      _buildWaveformBar(34, const Color(0xFF06B6D4)),
                      _buildWaveformBar(16, const Color(0xFF3B82F6)),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Metrics Grid: Latency, Confidence, Target File
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F5).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE7E7E4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('LATENCY',
                                style: TextStyle(
                                    color: Color(0xFF6B6B6B),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)),
                            SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('24',
                                    style: TextStyle(
                                        color: Color(0xFF111111),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800)),
                                SizedBox(width: 2),
                                Text('ms',
                                    style: TextStyle(
                                        color: Color(0xFF6B6B6B),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CONFIDENCE',
                                style: TextStyle(
                                    color: Color(0xFF6B6B6B),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)),
                            SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('99.8',
                                    style: TextStyle(
                                        color: Color(0xFF111111),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800)),
                                SizedBox(width: 2),
                                Text('%',
                                    style: TextStyle(
                                        color: Color(0xFF6B6B6B),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TARGET',
                                style: TextStyle(
                                    color: Color(0xFF6B6B6B),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)),
                            SizedBox(height: 2),
                            Text('role.py:42',
                                style: TextStyle(
                                    color: Color(0xFF111111),
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Code / Terminal Output snippet
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _currentPayload.rawText.isNotEmpty
                          ? _currentPayload.rawText
                          : OcrService.sampleKeyErrorTerminalOutput(),
                      style: const TextStyle(
                        color: Color(0xFFF4F4F5),
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.35,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaveformBar(double height, Color color) {
    return Container(
      width: 5,
      height: height * 0.7,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9999),
      ),
    );
  }

  Widget _buildHudStatusPills() {
    return Row(
      children: [
        if (_currentPayload.hasError)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: const Color(0xFFEF4444)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFEF4444), size: 14),
                const SizedBox(width: 6),
                Text(
                  _currentPayload.detectedErrorType ?? 'Error Detected',
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        if (_currentPayload.hasError &&
            _currentPayload.detectedTargetFile != null)
          const SizedBox(width: 8),
        if (_currentPayload.detectedTargetFile != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: const Color(0xFFE7E7E4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    color: Color(0xFF111111), size: 14),
                const SizedBox(width: 6),
                Text(
                  '${_currentPayload.detectedTargetFile}${_currentPayload.detectedLineNumber != null ? ':${_currentPayload.detectedLineNumber}' : ''}',
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBottomControlPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE7E7E4), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Voice Command Transcript Bubble
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _voiceService.isListening
                        ? const Color(0xFF10B981)
                        : const Color(0xFFE7E7E4),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _voiceService.isListening
                          ? Icons.graphic_eq
                          : Icons.record_voice_over,
                      color: _voiceService.isListening
                          ? const Color(0xFF10B981)
                          : const Color(0xFF111111),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _currentVoiceCommand.isNotEmpty
                            ? _currentVoiceCommand
                            : (_voiceService.isListening
                                ? 'Listening for developer command...'
                                : 'Tap mic or speak instructions...'),
                        style: TextStyle(
                          color: _currentVoiceCommand.isNotEmpty
                              ? const Color(0xFF111111)
                              : const Color(0xFF6B6B6B),
                          fontSize: 13,
                          fontWeight: _currentVoiceCommand.isNotEmpty
                              ? FontWeight.w600
                              : FontWeight.normal,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Preset Voice Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: VoiceService.presetCommands.map((preset) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        backgroundColor: const Color(0xFFF7F7F5),
                        side: const BorderSide(color: Color(0xFFE7E7E4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        label: Text(
                          preset,
                          style: const TextStyle(
                            color: Color(0xFF111111),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
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

              const SizedBox(height: 14),

              // Action Row: Pulse Mic Button + Primary Black Pill Button CTA
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isAnalyzing ? null : _triggerAnalysis,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF111111),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      child: _isAnalyzing
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'GENERATING FIX...',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bolt, size: 18, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'ANALYZE & GENERATE PATCH',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    letterSpacing: -0.2,
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
        ),
      ),
    );
  }
}
