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
  BridgePingResult? _bridgePing;
  bool _isCheckingBridge = false;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: BridgeService.activeLaptopIp);
    _checkBridgeHealth();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _checkBridgeHealth() async {
    if (_isCheckingBridge) return;
    setState(() => _isCheckingBridge = true);
    final res = await BridgeService.checkHealth();
    if (mounted) {
      setState(() {
        _bridgePing = res;
        _isCheckingBridge = false;
      });
    }
  }

  Future<void> _handleCopyDiff() async {
    setState(() => _isCopying = true);
    await Clipboard.setData(ClipboardData(text: widget.diagnosticResult.patchDiff));
    final success = await BridgeService.copyDiffToClipboard(widget.diagnosticResult.patchDiff);
    setState(() => _isCopying = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
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
          backgroundColor: const Color(0xFF121215),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      _showCiCdResultModal(result, patchFileName);
    }
  }

  void _showCiCdResultModal(FilePushResult result, String patchFileName) {
    final record = result.record;
    final buildStatus = record?['build_status'] ?? (result.success ? 'BUILD PASSING' : 'BUILD FAILED');
    final isPassing = buildStatus == 'BUILD PASSING';
    final gitApplyStatus = record?['git_apply_status'] ?? (result.success ? 'SUCCESS' : 'UNKNOWN');
    final testStatus = record?['test_status'] ?? (result.success ? 'PASSED' : 'UNKNOWN');
    final testOutput = record?['test_output'] ?? record?['git_apply_output'] ?? result.message;

    final targetSlug = widget.diagnosticResult.targetFile.split('/').last.split('.').first;
    final defaultBranch = 'rectrace/fix-${targetSlug.isNotEmpty ? targetSlug : 'bug'}';
    final defaultMsg = 'fix: resolve ${widget.diagnosticResult.rootCause.split(':').first.trim()} in ${widget.diagnosticResult.targetFile}';

    final branchController = TextEditingController(text: defaultBranch);
    final commitController = TextEditingController(text: defaultMsg);
    bool isCreatingBranch = false;
    Map<String, dynamic>? branchCommitResult;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.88,
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  const SizedBox(height: 18),

                  // Header with Build Status Badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (isPassing ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPassing ? Icons.verified : Icons.error_outline,
                          color: isPassing ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPassing ? 'CI/CD Build Passing' : 'Build Verification Failed',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: Color(0xFF111111),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Patch: $patchFileName',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B6B), fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isPassing ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFEF4444).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(
                            color: isPassing ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          ),
                        ),
                        child: Text(
                          buildStatus,
                          style: TextStyle(
                            color: isPassing ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Step-by-Step CI Pipeline Checklist Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F2EF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE7E7E4)),
                    ),
                    child: Column(
                      children: [
                        _buildPipelineStepRow(
                          stepNum: '1',
                          title: 'Bridge Transmission',
                          detail: 'Transferred to laptop daemon via HTTP/Storage',
                          status: 'OK',
                          isSuccess: true,
                        ),
                        const Divider(height: 16, color: Color(0xFFE7E7E4)),
                        _buildPipelineStepRow(
                          stepNum: '2',
                          title: 'Git Apply',
                          detail: 'Applied patch to mock_project workspace',
                          status: gitApplyStatus,
                          isSuccess: gitApplyStatus == 'SUCCESS',
                        ),
                        const Divider(height: 16, color: Color(0xFFE7E7E4)),
                        _buildPipelineStepRow(
                          stepNum: '3',
                          title: 'Pytest Verification',
                          detail: 'Ran automated CI test suite',
                          status: testStatus,
                          isSuccess: testStatus == 'PASSED',
                        ),
                      ],
                    ),
                  ),

                  // 🌿 1-Tap Git Branch & Commit Creator (When build passes)
                  if (isPassing) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121215),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF27272A)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                            blurRadius: 16,
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
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.fork_right, color: Color(0xFF34D399), size: 16),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Git Branch & Commit Generator',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const Spacer(),
                              if (branchCommitResult != null && branchCommitResult!['status'] == 'success')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('COMMITTED', style: TextStyle(color: Color(0xFF34D399), fontSize: 10, fontWeight: FontWeight.w800)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (branchCommitResult == null) ...[
                            TextField(
                              controller: branchController,
                              style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                labelText: 'Branch Name',
                                labelStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11),
                                filled: true,
                                fillColor: const Color(0xFF18181B),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF27272A)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF27272A)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: commitController,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                labelText: 'Commit Message',
                                labelStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11),
                                filled: true,
                                fillColor: const Color(0xFF18181B),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF27272A)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Color(0xFF27272A)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: isCreatingBranch
                                  ? null
                                  : () async {
                                      setModalState(() => isCreatingBranch = true);
                                      final res = await BridgeService.createBranchAndCommit(
                                        branchName: branchController.text.trim(),
                                        commitMessage: commitController.text.trim(),
                                        patchFile: patchFileName,
                                      );
                                      setModalState(() {
                                        isCreatingBranch = false;
                                        branchCommitResult = res;
                                      });
                                    },
                              icon: isCreatingBranch
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.commit, size: 16, color: Colors.white),
                              label: Text(
                                isCreatingBranch ? 'Creating Branch...' : 'CREATE BRANCH & COMMIT',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 42),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ] else ...[
                            // Success View with Branch & Commit SHA
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF18181B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.check_circle, color: Color(0xFF34D399), size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          branchCommitResult!['message']?.toString() ?? 'Branch Created!',
                                          style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.w600, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text('Branch: ', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11)),
                                      Text(
                                        branchCommitResult!['branch']?.toString() ?? '',
                                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 11.5),
                                      ),
                                      const Spacer(),
                                      const Text('SHA: ', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 11)),
                                      Text(
                                        branchCommitResult!['commit_sha']?.toString() ?? '',
                                        style: const TextStyle(color: Color(0xFF34D399), fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 11.5),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 14, color: Color(0xFFA1A1AA)),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Copy commit SHA',
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: branchCommitResult!['commit_sha']?.toString() ?? ''));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Commit SHA copied!'), duration: Duration(seconds: 1)),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Pytest / Git Terminal Output
                  if (testOutput.isNotEmpty) ...[
                    const Text(
                      'Verification Terminal Output:',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF6B6B6B)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121215),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF27272A)),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          testOutput,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Color(0xFF34D399),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            await BridgeService.resetRemoteTestbed();
                            _checkBridgeHealth();
                          },
                          icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF111111)),
                          label: const Text('Reset Testbed', style: TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE7E7E4)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF111111),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPipelineStepRow({
    required String stepNum,
    required String title,
    required String detail,
    required String status,
    required bool isSuccess,
  }) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            shape: BoxShape.circle,
          ),
          child: Text(
            stepNum,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFF111111)),
              ),
              Text(
                detail,
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF868381)),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: (isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isSuccess ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
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
              'Laptop Bridge Host',
              style: TextStyle(color: Color(0xFF111111), fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a preset or enter the IP of the laptop running daemon.py (Port 8000):',
              style: TextStyle(color: Color(0xFF6B6B6B), fontSize: 12.5, height: 1.35),
            ),
            const SizedBox(height: 12),
            // Quick Presets
            Row(
              children: [
                ActionChip(
                  label: const Text('10.0.2.2 (Emulator)', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _ipController.text = '10.0.2.2';
                  },
                ),
                const SizedBox(width: 6),
                ActionChip(
                  label: const Text('127.0.0.1 (Local)', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _ipController.text = '127.0.0.1';
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
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
            onPressed: () async {
              final newIp = _ipController.text.trim();
              if (newIp.isNotEmpty) {
                setState(() {
                  BridgeService.activeLaptopIp = newIp;
                });
                Navigator.pop(context);
                await _checkBridgeHealth();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF111111),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save & Ping'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.diagnosticResult;
    final isBridgeOnline = _bridgePing?.isOnline ?? false;

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
          // Live Bridge Ping Chip Button
          GestureDetector(
            onTap: _showConfigureIpDialog,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: const Color(0xFFE7E7E4)),
              ),
              child: Row(
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
          // JSON Viewer button
          Container(
            margin: const EdgeInsets.only(right: 12, left: 4, top: 10, bottom: 10),
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
                color: const Color(0xFF121215),
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
                      'PUSH VIA BRIDGE',
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
              color: const Color(0xFF121215),
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
