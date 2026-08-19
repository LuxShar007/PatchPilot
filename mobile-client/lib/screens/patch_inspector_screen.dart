import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/diagnostic_result.dart';
import '../services/bridge_service.dart';
import '../widgets/diff_viewer.dart';

class PatchInspectorScreen extends StatefulWidget {
  final DiagnosticResult diagnosticResult;

  const PatchInspectorScreen({
    super.key,
    required this.diagnosticResult,
  });

  @override
  State<PatchInspectorScreen> createState() => _PatchInspectorScreenState();
}

class _PatchInspectorScreenState extends State<PatchInspectorScreen> {
  bool _isCopying = false;
  bool _isPushing = false;
  late TextEditingController _ipController;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: BridgeService.activeLaptopIp);
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _handleCopyDiff() async {
    setState(() => _isCopying = true);
    // Direct system clipboard write (relayed instantly by Office Kit Shared Clipboard)
    await Clipboard.setData(ClipboardData(text: widget.diagnosticResult.patchDiff));
    final success = await BridgeService.copyDiffToClipboard(widget.diagnosticResult.patchDiff);
    setState(() => _isCopying = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF4ADE80), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  success
                      ? 'Patch copied to clipboard! (Office Kit Shared Clipboard active)'
                      : 'Failed to copy to clipboard',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handlePushToBridge() async {
    setState(() => _isPushing = true);

    // Derive patch file name from target file (e.g. fix_app.patch)
    final baseName = widget.diagnosticResult.targetFile.split('/').last.split('.').first;
    final patchFileName = 'fix_${baseName.isNotEmpty ? baseName : 'bug'}.patch';

    final result = await BridgeService.pushToBridge(
      widget.diagnosticResult.patchDiff,
      filename: patchFileName,
      laptopIp: BridgeService.activeLaptopIp,
    );

    setState(() {
      _isPushing = false;
    });

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFFFCFCFB),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFE7E7E4)),
          ),
          title: Row(
            children: [
              Icon(
                result.success ? Icons.cloud_done : Icons.error_outline,
                color: result.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.success ? 'Bridge Push Successful' : 'Bridge Push Failed',
                  style: const TextStyle(
                    color: Color(0xFF111111),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.message,
                style: const TextStyle(color: Color(0xFF6B6B6B), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F2EF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE7E7E4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Target Endpoint / Path:', style: TextStyle(color: Color(0xFF868381), fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      result.filePath.isNotEmpty ? result.filePath : 'http://${BridgeService.activeLaptopIp}:8000/apply-patch',
                      style: const TextStyle(
                        color: Color(0xFF111111),
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
  }

  void _showConfigureIpDialog() {
    _ipController.text = BridgeService.activeLaptopIp;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFCFCFB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE7E7E4)),
        ),
        title: const Row(
          children: [
            Icon(Icons.settings_ethernet, color: Color(0xFF111111), size: 20),
            SizedBox(width: 8),
            Text(
              'Configure Laptop IP',
              style: TextStyle(color: Color(0xFF111111), fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the local Wi-Fi IP address of your laptop running daemon.py (Port 8000):',
              style: TextStyle(color: Color(0xFF6B6B6B), fontSize: 12.5, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                hintText: 'e.g. 192.168.1.100 or 10.0.2.2',
                filled: true,
                fillColor: const Color(0xFFF3F2EF),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE7E7E4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE7E7E4)),
                ),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B6B6B))),
          ),
          ElevatedButton(
            onPressed: () {
              final newIp = _ipController.text.trim();
              if (newIp.isNotEmpty) {
                setState(() {
                  BridgeService.activeLaptopIp = newIp;
                });
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF111111),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save IP'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.diagnosticResult;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F7F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111111)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Diagnostic Patch Inspector',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: Color(0xFF111111),
          ),
        ),
        actions: [
          // IP Settings button
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE7E7E4)),
            ),
            child: IconButton(
              icon: const Icon(Icons.wifi_tethering, color: Color(0xFF111111), size: 18),
              tooltip: 'Configure Laptop IP (${BridgeService.activeLaptopIp})',
              onPressed: _showConfigureIpDialog,
            ),
          ),
          // JSON Viewer button
          Container(
            margin: const EdgeInsets.only(right: 12, left: 8, top: 10, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE7E7E4)),
            ),
            child: IconButton(
              icon: const Icon(Icons.data_object, color: Color(0xFF111111), size: 18),
              tooltip: 'View Raw JSON Contract',
              onPressed: () {
                _showRawJsonDialog(context, result);
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Root Cause Summary Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFCFCFB),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE7E7E4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.bug_report, color: Color(0xFFEF4444), size: 12),
                            SizedBox(width: 4),
                            Text(
                              'ROOT CAUSE',
                              style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Target file badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F2EF),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(color: const Color(0xFFE7E7E4)),
                        ),
                        child: Text(
                          result.targetFile,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF111111),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    result.rootCause,
                    style: const TextStyle(
                      color: Color(0xFF111111),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. Explanation Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F2EF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE7E7E4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF111111), size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Patch Explanation',
                          style: TextStyle(
                            color: Color(0xFF6B6B6B),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.explanation,
                          style: const TextStyle(
                            color: Color(0xFF111111),
                            fontSize: 13.5,
                            height: 1.45,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3. Test Command Runner Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    'Validation: ',
                    style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
                  ),
                  Expanded(
                    child: Text(
                      result.testCommand,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF34D399),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_copy, color: Color(0xFFA1A1AA), size: 16),
                    tooltip: 'Copy test command',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: result.testCommand));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Test command copied!'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 4. Formatted Unified Diff Viewer
            DiffViewer(
              patchDiff: result.patchDiff,
              fileName: result.targetFile,
            ),

            const SizedBox(height: 24),

            // 5. Primary Action Buttons: "Copy Diff" & "Push via Office Kit"
            Row(
              children: [
                // Action 1: Copy Diff (Direct System Clipboard -> Office Kit Sync)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isCopying ? null : _handleCopyDiff,
                    icon: _isCopying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF111111)),
                          )
                        : const Icon(Icons.copy, size: 18, color: Color(0xFF111111)),
                    label: const Text(
                      'COPY DIFF',
                      style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2, color: Color(0xFF111111)),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF111111),
                      side: const BorderSide(color: Color(0xFFE7E7E4)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder(),
                      elevation: 0,
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Action 2: Push via Office Kit (Direct Network HTTP Push + Shared Storage)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPushing ? null : _handlePushToBridge,
                    icon: _isPushing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_alt, size: 18, color: Colors.white),
                    label: const Text(
                      'PUSH VIA OFFICE KIT',
                      style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF111111),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder(),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showRawJsonDialog(BuildContext context, DiagnosticResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFCFCFB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE7E7E4)),
        ),
        title: const Row(
          children: [
            Icon(Icons.data_object, color: Color(0xFF111111), size: 20),
            SizedBox(width: 8),
            Text(
              'Output Contract JSON',
              style: TextStyle(color: Color(0xFF111111), fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              result.toPrettyJson(),
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFF34D399),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result.toPrettyJson()));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Raw JSON copied to clipboard!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16, color: Color(0xFF111111)),
            label: const Text('Copy JSON', style: TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF6B6B6B))),
          ),
        ],
      ),
    );
  }
}
