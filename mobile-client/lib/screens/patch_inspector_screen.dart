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
  String? _bridgePushStatus;

  Future<void> _handleCopyDiff() async {
    setState(() => _isCopying = true);
    final success = await BridgeService.copyDiffToClipboard(widget.diagnosticResult.patchDiff);
    setState(() => _isCopying = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF4ADE80), size: 20),
              const SizedBox(width: 10),
              Text(
                success ? 'Patch diff copied to system clipboard! (Office Kit synced)' : 'Failed to copy to clipboard',
                style: const TextStyle(fontWeight: FontWeight.w600),
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
    final result = await BridgeService.pushToBridge(
      widget.diagnosticResult.patchDiff,
      filename: 'fix.patch',
    );
    setState(() {
      _isPushing = false;
      _bridgePushStatus = result.message;
    });

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF334155)),
          ),
          title: Row(
            children: [
              Icon(
                result.success ? Icons.cloud_done : Icons.error_outline,
                color: result.success ? const Color(0xFF4ADE80) : const Color(0xFFEF4444),
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                result.success ? 'Bridge Push Successful' : 'Bridge Push Failed',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.message,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Target Location:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(
                      result.filePath.isNotEmpty ? result.filePath : 'inbox_patches/fix.patch',
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontFamily: 'monospace',
                        fontSize: 12,
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
              child: const Text('OK', style: TextStyle(color: Color(0xFF38BDF8))),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.diagnosticResult;

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF94A3B8)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Diagnostic Patch Inspector',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Color(0xFFF8FAFC),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.data_object, color: Color(0xFF38BDF8)),
            tooltip: 'View Raw JSON Contract',
            onPressed: () {
              _showRawJsonDialog(context, result);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Root Cause Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFEF4444)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.bug_report, color: Color(0xFFEF4444), size: 13),
                            SizedBox(width: 4),
                            Text(
                              'ROOT CAUSE',
                              style: TextStyle(
                                color: Color(0xFFEF4444),
                                fontWeight: FontWeight.bold,
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
                        ),
                        child: Text(
                          result.targetFile,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF38BDF8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    result.rootCause,
                    style: const TextStyle(
                      color: Color(0xFFF1F5F9),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2. Explanation Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Patch Explanation',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.explanation,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 3. Test Command Runner Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    'Validation Command: ',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  Expanded(
                    child: Text(
                      result.testCommand,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF4ADE80),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_copy, color: Color(0xFF64748B), size: 16),
                    tooltip: 'Copy test command',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: result.testCommand));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Test command copied!'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4. Formatted Unified Diff Viewer
            DiffViewer(
              patchDiff: result.patchDiff,
              fileName: result.targetFile,
            ),

            const SizedBox(height: 24),

            // 5. Primary Action Buttons: "Copy Diff" & "Push to Bridge"
            Row(
              children: [
                // Action 1: Copy Diff
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isCopying ? null : _handleCopyDiff,
                    icon: _isCopying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.copy, size: 18),
                    label: const Text(
                      'COPY DIFF',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF0284C7)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Action 2: Push to Bridge
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPushing ? null : _handlePushToBridge,
                    icon: _isPushing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_alt, size: 18),
                    label: const Text(
                      'PUSH TO BRIDGE',
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showRawJsonDialog(BuildContext context, DiagnosticResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        title: const Row(
          children: [
            Icon(Icons.data_object, color: Color(0xFF38BDF8), size: 20),
            SizedBox(width: 8),
            Text(
              'Output Contract JSON',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF020617),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Text(
              result.toPrettyJson(),
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFF38BDF8),
                fontSize: 11,
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
                const SnackBar(content: Text('Raw JSON copied to clipboard!')),
              );
            },
            icon: const Icon(Icons.copy, size: 16, color: Color(0xFF38BDF8)),
            label: const Text('Copy JSON', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
        ],
      ),
    );
  }
}
