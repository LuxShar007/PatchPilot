import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Service for clipboard synchronization, network bridge push, and workspace file transfer
class BridgeService {
  static const String defaultPatchFileName = 'fix.patch';
  static const String bridgeDirectoryName = 'inbox_patches';
  
  // Default laptop host (10.0.2.2 for Android emulator, or configured LAN IP)
  static String activeLaptopIp = '10.0.2.2';
  static int daemonPort = 8000;

  /// Action 1: "Copy Diff" -> Copies patch_diff directly to system clipboard (Office Kit Shared Clipboard)
  static Future<bool> copyDiffToClipboard(String patchDiff) async {
    try {
      await Clipboard.setData(ClipboardData(text: patchDiff));
      debugPrint('Copied patch diff to clipboard (${patchDiff.length} bytes)');
      return true;
    } catch (e) {
      debugPrint('Failed to copy diff to clipboard: $e');
      return false;
    }
  }

  /// Action 2: "Network Push" -> Sends direct HTTP POST request to laptop daemon on local network
  static Future<FilePushResult> pushNetworkPatch(
    String patchDiff, {
    String filename = defaultPatchFileName,
    String? laptopHost,
  }) async {
    final host = (laptopHost != null && laptopHost.isNotEmpty) ? laptopHost : activeLaptopIp;
    final uri = Uri.parse('http://$host:$daemonPort/apply-patch');

    try {
      debugPrint('Sending HTTP POST patch to $uri ...');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'filename': filename,
          'patch': patchDiff,
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final buildStatus = data['record']?['build_status'] ?? data['status'] ?? 'SUCCESS';
        final msg = data['message'] ?? 'Patch applied successfully by Laptop Bridge.';
        return FilePushResult(
          success: true,
          filePath: 'http://$host:$daemonPort/apply-patch',
          message: '$msg (CI: $buildStatus)',
        );
      } else {
        return FilePushResult(
          success: false,
          filePath: uri.toString(),
          message: 'Laptop Bridge returned status code ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Network push error: $e');
      return FilePushResult(
        success: false,
        filePath: uri.toString(),
        message: 'Could not connect to laptop bridge at $host:$daemonPort: $e',
      );
    }
  }

  /// Action 3: "Fallback File Export" -> Writes patch to external/shared storage rather than private app sandbox
  static Future<FilePushResult> pushToLocalStorage(
    String patchDiff, {
    String filename = defaultPatchFileName,
    String? customDirectoryPath,
  }) async {
    try {
      Directory targetDir;

      if (customDirectoryPath != null && customDirectoryPath.isNotEmpty) {
        targetDir = Directory(customDirectoryPath);
      } else if (kIsWeb) {
        return FilePushResult(
          success: true,
          filePath: '$bridgeDirectoryName/$filename',
          message: 'Saved to Web workspace simulated inbox',
        );
      } else if (Platform.isAndroid) {
        // Try external storage directory first so files are accessible to Office Kit / USB / user
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          targetDir = Directory('${extDir.path}/$bridgeDirectoryName');
        } else {
          final docDir = await getApplicationDocumentsDirectory();
          targetDir = Directory('${docDir.path}/$bridgeDirectoryName');
        }
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        targetDir = Directory('${docDir.path}/$bridgeDirectoryName');
      }

      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final file = File('${targetDir.path}/$filename');
      await file.writeAsString(patchDiff, flush: true);

      // Also copy to clipboard to ensure Office Kit shared clipboard picks it up immediately
      await copyDiffToClipboard(patchDiff);

      debugPrint('Successfully exported patch to: ${file.path}');
      return FilePushResult(
        success: true,
        filePath: file.path,
        message: 'Saved $filename to external storage & synced to Shared Clipboard.',
      );
    } catch (e) {
      debugPrint('Error writing patch to local storage: $e');
      return FilePushResult(
        success: false,
        filePath: '',
        message: 'Failed to write patch: $e',
      );
    }
  }

  /// Combined Bridge Push: Tries network POST first; if unreachable, falls back gracefully to external storage
  static Future<FilePushResult> pushToBridge(
    String patchDiff, {
    String filename = defaultPatchFileName,
    String? customDirectoryPath,
    String? laptopIp,
  }) async {
    // 1. Try Network HTTP POST to Laptop Daemon
    final netResult = await pushNetworkPatch(
      patchDiff,
      filename: filename,
      laptopHost: laptopIp,
    );

    if (netResult.success) {
      // Also copy to clipboard
      await copyDiffToClipboard(patchDiff);
      return netResult;
    }

    // 2. Fallback to external storage and clipboard
    final localResult = await pushToLocalStorage(
      patchDiff,
      filename: filename,
      customDirectoryPath: customDirectoryPath,
    );

    if (localResult.success) {
      return FilePushResult(
        success: true,
        filePath: localResult.filePath,
        message: 'Network offline (${netResult.message}). Saved to accessible external storage and synced to Office Kit clipboard.',
      );
    }

    return netResult;
  }
}

/// Result object for file push operations
class FilePushResult {
  final bool success;
  final String filePath;
  final String message;

  const FilePushResult({
    required this.success,
    required this.filePath,
    required this.message,
  });
}
