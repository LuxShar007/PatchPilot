import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/bridge_service.dart';
import '../services/diagnostic_service.dart';
import '../services/voice_service.dart';
import '../widgets/pulse_mic_button.dart';
import 'patch_inspector_screen.dart';
import 'scanner_screen.dart';

/// Primary Fixing Studio for RecTrace - dual input error log + source code with workspace pull
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final TextEditingController _logController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _commandController = TextEditingController();

  final DiagnosticService _diagnosticService = DiagnosticService();
  final VoiceService _voiceService = VoiceService();

  bool _isAnalyzing = false;
  bool _isLoadingRepoFiles = false;
  String _selectedFileName = 'app.py';
  List<Map<String, dynamic>> _repoFiles = [];
  BridgePingResult? _bridgePing;

  @override
  void initState() {
    super.initState();
    _initializeDefaultState();
  }

  Future<void> _initializeDefaultState() async {
    // 1. Initialize Voice Service
    await _voiceService.initialize();
    _voiceService.onStateChanged = (isListening, transcript) {
      if (mounted) {
        setState(() {
          _commandController.text = transcript;
        });
      }
    };

    // 2. Pre-fill default KeyError challenge
    _injectPresetChallenge('keyerror');

    // 3. Ping Laptop Bridge and fetch repository files
    _checkBridgeAndFetchFiles();
  }

  @override
  void dispose() {
    _logController.dispose();
    _codeController.dispose();
    _commandController.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  Future<void> _checkBridgeAndFetchFiles() async {
    final ping = await BridgeService.checkHealth();
    if (mounted) {
      setState(() => _bridgePing = ping);
    }
    if (ping.isOnline) {
      _loadWorkspaceFiles();
    }
  }

  Future<void> _loadWorkspaceFiles() async {
    setState(() => _isLoadingRepoFiles = true);
    final files = await BridgeService.fetchRepoFiles();
    if (mounted) {
      setState(() {
        _repoFiles = files;
        _isLoadingRepoFiles = false;
      });
    }
  }

  Future<void> _fetchSelectedFileContent(String relativePath) async {
    final content = await BridgeService.fetchFileContent(relativePath);
    if (content != null && mounted) {
      setState(() {
        _codeController.text = content;
        _selectedFileName = relativePath;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded $relativePath from Laptop Workspace (${content.split('\n').length} lines)'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _injectPresetChallenge(String key) {
    switch (key) {
      case 'zerodiv':
        _selectedFileName = 'math_ops.py';
        _logController.text = '''Traceback (most recent call last):
  File "math_ops.py", line 18, in calculate_ratio
    return numerator / denominator
ZeroDivisionError: division by zero''';
        _codeController.text = '''def calculate_ratio(numerator, denominator):
    return numerator / denominator
''';
        _commandController.text = 'Guard against zero denominator';
        break;

      case 'typeerror':
        _selectedFileName = 'UserList.tsx';
        _logController.text = '''TypeError: Cannot read properties of undefined (reading 'map')
    at renderUserList (src/components/UserList.tsx:42:15)''';
        _codeController.text = '''export const UserList = ({ items }: Props) => {
  return (
    <div className="list-container">
      {items.map(item => <UserCard key={item.id} {...item} />)}
    </div>
  );
};
''';
        _commandController.text = 'Add optional chaining and null check';
        break;

      case 'indexerror':
        _selectedFileName = 'cache.py';
        _logController.text = '''Traceback (most recent call last):
  File "cache.py", line 35, in get_item
    return items[idx]
IndexError: list index out of range''';
        _codeController.text = '''def get_item(items, idx):
    return items[idx]
''';
        _commandController.text = 'Add bounds check for index';
        break;

      case 'keyerror':
      default:
        _selectedFileName = 'app.py';
        _logController.text = '''Traceback (most recent call last):
  File "app.py", line 2, in process_user_data
    return {'name': user_dict['name'], 'role': user_dict['role'].upper(), 'status': 'active'}
KeyError: 'role' ''';
        _codeController.text = '''def process_user_data(user_dict: dict) -> dict:
    return {'name': user_dict['name'], 'role': user_dict['role'].upper(), 'status': 'active'}
''';
        _commandController.text = "Fix missing 'role' key with fallback to 'user'";
        break;
    }
    setState(() {});
  }

  Future<void> _triggerPrecisionFix() async {
    final errorText = _logController.text.trim();
    if (errorText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please paste or enter an error stack trace first'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final codeText = _codeController.text.trim();
      final userCmd = _commandController.text.trim();

      final result = await _diagnosticService.analyze(
        scannedText: errorText,
        sourceCode: codeText.isNotEmpty ? codeText : null,
        fileName: _selectedFileName,
        userCommand: userCmd.isNotEmpty ? userCmd : null,
      );

      if (mounted) {
        setState(() => _isAnalyzing = false);

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PatchInspectorScreen(diagnosticResult: result),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Diagnosis failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showBridgeQuickPanel() {
    final ipController = TextEditingController(text: BridgeService.activeLaptopIp);
    bool isResetting = false;

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
                        color: (isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isOnline ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                        color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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
                              color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Quick Presets
                Row(
                  children: [
                    ActionChip(
                      label: const Text('127.0.0.1 (Localhost)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      backgroundColor: const Color(0xFFF3F2EF),
                      side: const BorderSide(color: Color(0xFFE7E7E4)),
                      onPressed: () async {
                        ipController.text = '127.0.0.1';
                        BridgeService.activeLaptopIp = '127.0.0.1';
                        await _checkBridgeAndFetchFiles();
                        setPanelState(() {});
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      label: const Text('10.0.2.2 (Emulator)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      backgroundColor: const Color(0xFFF3F2EF),
                      side: const BorderSide(color: Color(0xFFE7E7E4)),
                      onPressed: () async {
                        ipController.text = '10.0.2.2';
                        BridgeService.activeLaptopIp = '10.0.2.2';
                        await _checkBridgeAndFetchFiles();
                        setPanelState(() {});
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ipController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.computer, size: 18, color: Color(0xFF111111)),
                    hintText: 'Enter Laptop IP (e.g. 192.168.1.100)',
                    filled: true,
                    fillColor: const Color(0xFFF3F2EF),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE7E7E4))),
                    suffixIcon: TextButton(
                      onPressed: () async {
                        final newIp = ipController.text.trim();
                        if (newIp.isNotEmpty) {
                          BridgeService.activeLaptopIp = newIp;
                          await _checkBridgeAndFetchFiles();
                          setPanelState(() {});
                          setState(() {});
                        }
                      },
                      child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF111111))),
                    ),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: isResetting
                      ? null
                      : () async {
                          setPanelState(() => isResetting = true);
                          final res = await BridgeService.resetRemoteTestbed();
                          setPanelState(() => isResetting = false);
                          await _checkBridgeAndFetchFiles();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(res['message']?.toString() ?? 'Testbed reset!'), behavior: SnackBarBehavior.floating),
                            );
                          }
                        },
                  icon: isResetting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restore, size: 16, color: Color(0xFF111111)),
                  label: const Text('Reset Testbed (Baseline Bug)', style: TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w700, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE7E7E4)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
                'Code & Error Precision Fixing Studio',
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
              await _checkBridgeAndFetchFiles();
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
                      color: isBridgeOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isBridgeOnline ? '${_bridgePing?.latencyMs}ms' : 'Offline',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isBridgeOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Camera Scan Button (Secondary Mode)
          Container(
            margin: const EdgeInsets.only(right: 6, top: 10, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE7E7E4)),
            ),
            child: IconButton(
              icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF111111), size: 17),
              tooltip: 'Launch Camera OCR Scanner',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ScannerScreen()),
                );
              },
            ),
          ),

          // Sample Injector Button
          Container(
            margin: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE7E7E4)),
            ),
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.auto_fix_high, color: Color(0xFF111111), size: 17),
              tooltip: 'Load Sample Bug Challenge',
              color: const Color(0xFFFCFCFB),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE7E7E4))),
              onSelected: _injectPresetChallenge,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'keyerror',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🐍 KeyError: "role"', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF111111))),
                      Text('app.py (Missing Dict Key)', style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'zerodiv',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('➗ ZeroDivisionError', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF111111))),
                      Text('math_ops.py (Division by Zero)', style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'typeerror',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚛️ TypeError (Undefined Map)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF111111))),
                      Text('UserList.tsx (React Optional Chaining)', style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'indexerror',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📦 IndexError: Out of Range', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF111111))),
                      Text('cache.py (List Bounds Violation)', style: TextStyle(fontSize: 11, color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 🔴 Red Light Hackathon Context Banner
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF27272A)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield, color: Color(0xFFEF4444), size: 14),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RED LIGHT MODE ACTIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Laptop closed · iQOO Mobile Remediation Studio connected via Office Kit',
                          style: TextStyle(
                            color: Color(0xFFA1A1AA),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF27272A),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '55% BUILD',
                      style: TextStyle(color: Color(0xFFE4E4E7), fontSize: 9, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),

            // 1. Deck 1: Error & Stack Trace Input Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFCFCFB),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE7E7E4)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.bug_report, color: Color(0xFFEF4444), size: 14),
                            SizedBox(width: 4),
                            Text('1. TERMINAL ERROR / STACK TRACE', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w800, fontSize: 10.5, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Quick Paste from Office Kit Shared Clipboard Button
                      OutlinedButton.icon(
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data != null && data.text != null && data.text!.isNotEmpty) {
                            setState(() => _logController.text = data.text!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Pasted from Office Kit Shared Clipboard!'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.paste, size: 13, color: Color(0xFF111111)),
                        label: const Text('Office Kit Paste', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF111111))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE7E7E4)),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: const Size(0, 28),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Terminal Error Text Field
                  Container(
                    height: 125,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121215),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    child: TextField(
                      controller: _logController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF4F4F5), fontSize: 11.5, height: 1.35),
                      decoration: const InputDecoration(
                        hintText: 'Paste traceback, terminal error log, or uncaught exception here...',
                        hintStyle: TextStyle(color: Color(0xFF71717A), fontFamily: 'monospace', fontSize: 11.5),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2. Deck 2: Target Source Code Context Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFCFCFB),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE7E7E4)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.code, color: Color(0xFF3B82F6), size: 14),
                            SizedBox(width: 4),
                            Text('2. SOURCE CODE CONTEXT', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w800, fontSize: 10.5, letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Workspace File Selector Dropdown
                      if (_repoFiles.isNotEmpty)
                        PopupMenuButton<String>(
                          onSelected: _fetchSelectedFileContent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F2EF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE7E7E4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.folder_open, size: 13, color: Color(0xFF111111)),
                                const SizedBox(width: 4),
                                Text(_selectedFileName, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF111111))),
                                const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF111111)),
                              ],
                            ),
                          ),
                          itemBuilder: (context) => _repoFiles.map((f) {
                            final path = f['path'] as String;
                            return PopupMenuItem<String>(
                              value: path,
                              child: Text(path, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                            );
                          }).toList(),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _isLoadingRepoFiles ? null : _loadWorkspaceFiles,
                          icon: _isLoadingRepoFiles
                              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.sync, size: 13, color: Color(0xFF111111)),
                          label: const Text('Pull from Laptop', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF111111))),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE7E7E4)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(0, 28),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Source Code Text Field
                  Container(
                    height: 135,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121215),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF27272A)),
                    ),
                    child: TextField(
                      controller: _codeController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(fontFamily: 'monospace', color: Color(0xFF34D399), fontSize: 11.5, height: 1.35),
                      decoration: const InputDecoration(
                        hintText: 'Paste target source code, function, or file contents here...',
                        hintStyle: TextStyle(color: Color(0xFF71717A), fontFamily: 'monospace', fontSize: 11.5),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 3. Developer Guidance & Voice Input Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFCFCFB),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE7E7E4)),
              ),
              child: Row(
                children: [
                  PulseMicButton(
                    isListening: _voiceService.isListening,
                    size: 46,
                    onTap: () {
                      if (_voiceService.isListening) {
                        _voiceService.stopListening();
                      } else {
                        _voiceService.startListening(
                          onResult: (transcript) {
                            setState(() => _commandController.text = transcript);
                          },
                        );
                      }
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _commandController,
                      decoration: const InputDecoration(
                        hintText: 'Optional instructions (e.g. "Add null check", "Use fallback")',
                        hintStyle: TextStyle(fontSize: 12, color: Color(0xFF868381)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 4. Primary Submit CTA: "ANALYZE & GENERATE PRECISION FIX"
            ElevatedButton(
              onPressed: _isAnalyzing ? null : _triggerPrecisionFix,
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
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        SizedBox(width: 10),
                        Text('GENERATING PRECISION FIX...', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: -0.2)),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt, size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text('ANALYZE & GENERATE PRECISION FIX', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, letterSpacing: -0.2)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
