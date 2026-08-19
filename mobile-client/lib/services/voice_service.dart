import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Callback signature for voice recognition state updates
typedef VoiceStateCallback = void Function(bool isListening, String transcript);

/// Service managing hands-free developer speech recognition and voice commands
class VoiceService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  String _lastWords = '';
  VoiceStateCallback? onStateChanged;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  String get lastWords => _lastWords;

  /// Preset developer voice commands for rapid evaluation & testing
  static const List<String> presetCommands = [
    "Fix null pointer and run tests",
    "Handle missing 'role' key with fallback to 'user'",
    "Add empty array fallback for undefined map call",
    "Refactor user auth validation and run pytest",
  ];

  /// Initializes the speech recognition engine
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (val) {
          debugPrint('Speech error: $val');
          _isListening = false;
          _notify();
        },
        onStatus: (status) {
          debugPrint('Speech status: $status');
          _isListening = status == 'listening';
          _notify();
        },
      );
      return _isInitialized;
    } catch (e) {
      debugPrint('Speech recognition initialize failed (falling back to mock mode): $e');
      _isInitialized = true; // allow mock fallback
      return true;
    }
  }

  /// Starts listening to developer speech
  Future<void> startListening({Function(String result)? onResult}) async {
    if (!_isInitialized) {
      await initialize();
    }

    _lastWords = '';
    _isListening = true;
    _notify();

    try {
      if (_speech.isAvailable) {
        await _speech.listen(
          onResult: (result) {
            _lastWords = result.recognizedWords;
            _notify();
            if (onResult != null) onResult(_lastWords);
          },
          listenOptions: SpeechListenOptions(
            listenMode: ListenMode.confirmation,
            cancelOnError: true,
            partialResults: true,
            listenFor: const Duration(seconds: 15),
            pauseFor: const Duration(seconds: 3),
          ),
        );
      } else {
        // Fallback for emulator / non-mic environments
        _simulateVoiceInput(onResult);
      }
    } catch (e) {
      debugPrint('Error starting speech listener: $e');
      _simulateVoiceInput(onResult);
    }
  }

  /// Simulates voice input when physical mic is not accessible
  void _simulateVoiceInput(Function(String result)? onResult) {
    Timer(const Duration(milliseconds: 1200), () {
      _lastWords = "Fix missing role key with fallback default";
      _isListening = false;
      _notify();
      if (onResult != null) onResult(_lastWords);
    });
  }

  /// Stops speech listening
  Future<void> stopListening() async {
    _isListening = false;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('Error stopping speech listener: $e');
    }
    _notify();
  }

  /// Sets manual text (e.g. from preset chips or keyboard edit)
  void setManualCommand(String command) {
    _lastWords = command;
    _notify();
  }

  void _notify() {
    onStateChanged?.call(_isListening, _lastWords);
  }

  void dispose() {
    _speech.stop();
  }
}
