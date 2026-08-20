import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Result structure for Bridge health/ping checks
class BridgePingResult {
  final bool isOnline;
  final int latencyMs;
  final String host;
  final int port;
  final String? serviceName;
  final String? errorMessage;

  const BridgePingResult({
    required this.isOnline,
    required this.latencyMs,
    required this.host,
    required this.port,
    this.serviceName,
    this.errorMessage,
  });
}

/// Service for clipboard synchronization, network bridge push, and workspace file transfer
class BridgeService {
  static const String defaultPatchFileName = 'fix.patch';
  static const String bridgeDirectoryName = 'inbox_patches';

  // Default laptop host (127.0.0.1 on desktop/web, 10.0.2.2 on Android emulator, or configured LAN IP)
  static String activeLaptopIp = (kIsWeb || (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)))
      ? '127.0.0.1'
      : '10.0.2.2';
  static int daemonPort = 8000;

  /// Ping laptop bridge health endpoint and measure real-time network latency
  static Future<BridgePingResult> checkHealth({String? laptopHost}) async {
    final host = (laptopHost != null && laptopHost.isNotEmpty) ? laptopHost : activeLaptopIp;
    final uri = Uri.parse('http://$host:$daemonPort/health');
    final stopwatch = Stopwatch()..start();

    try {
      final response = await http.get(uri).timeout(const Duration(milliseconds: 2500));
      stopwatch.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return BridgePingResult(
          isOnline: true,
          latencyMs: stopwatch.elapsedMilliseconds,
          host: host,
          port: daemonPort,
          serviceName: data['service']?.toString() ?? 'RecTrace Laptop Bridge',
        );
      } else {
        return BridgePingResult(
          isOnline: false,
          latencyMs: stopwatch.elapsedMilliseconds,
          host: host,
          port: daemonPort,
          errorMessage: 'HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      stopwatch.stop();
      return BridgePingResult(
        isOnline: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        host: host,
        port: daemonPort,
        errorMessage: e.toString(),
      );
    }
  }

  /// Reset remote testbed in mock_project to baseline bug
  static Future<Map<String, dynamic>> resetRemoteTestbed({String? laptopHost}) async {
    final host = (laptopHost != null && laptopHost.isNotEmpty) ? laptopHost : activeLaptopIp;
    final uri = Uri.parse('http://$host:$daemonPort/reset-testbed');

    try {
      final response = await http.post(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Trigger pytest suite on remote testbed on-demand
  static Future<Map<String, dynamic>> runRemoteTests({String? laptopHost}) async {
    final host = (laptopHost != null && laptopHost.isNotEmpty) ? laptopHost : activeLaptopIp;
    final uri = Uri.parse('http://$host:$daemonPort/run-tests');

    try {
      final response = await http.post(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'output': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'output': e.toString()};
    }
  }

  /// Query live status of daemon including recent patches and test outcomes
  static Future<Map<String, dynamic>?> fetchStatus({String? laptopHost}) async {
    final host = (laptopHost != null && laptopHost.isNotEmpty) ? laptopHost : activeLaptopIp;
    final uri = Uri.parse('http://$host:$daemonPort/status');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error fetching status: $e');
    }
    return null;
  }

  /// Create an isolated Git Branch and commit the applied patch
  static Future<Map<String, dynamic>> createBranchAndCommit({
    String? branchName,
    String? commitMessage,
    String? patchFile,
    String? laptopHost,
  }) async {
    final host = (laptopHost != null && laptopHost.isNotEmpty) ? laptopHost : activeLaptopIp;
    final uri = Uri.parse('http://$host:$daemonPort/create-branch-commit');

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'branch_name': branchName,
          'commit_message': commitMessage,
          'patch_file': patchFile,
        }),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'status': 'error', 'message': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Fetch Git branch and latest commit info
  static Future<Map<String, dynamic>?> fetchGitInfo({String? laptopHost}) async {
    final host = (laptopHost != null && laptopHost.isNotEmpty) ? laptopHost : activeLaptopIp;
    final uri = Uri.parse('http://$host:$daemonPort/git-info');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error fetching git info: $e');
    }
    return null;
  }

  /// Fetch list of source code files in laptop workspace
  static Future<List<Map<String, dynamic>>> fetchRepoFiles({String? laptopHost}) async {
    final host = (laptopHost != null && laptopHost.isNotEmpty) ? laptopHost : activeLaptopIp;
    final uri = Uri.parse('http://$host:$daemonPort/repo-files');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = data['files'] as List<dynamic>? ?? [];
        return list.map((f) => f as Map<String, dynamic>).toList();
      }
    } catch (e) {
      debugPrint('Error fetching repo files: $e');
    }
    return [];
  }

  /// Fetch raw content of a specific file from laptop workspace
  static Future<String?> fetchFileContent(String path, {String? laptopHost}) async {
    final host = (laptopHost != null && laptopHost.isNotEmpty) ? laptopHost : activeLaptopIp;
    final uri = Uri.parse('http://$host:$daemonPort/file-content?path=$path');

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['content'] as String?;
      }
    } catch (e) {
      debugPrint('Error fetching file content for $path: $e');
    }
    return null;
  }

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
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final record = data['record'] as Map<String, dynamic>?;
        final buildStatus = record?['build_status'] ?? data['status'] ?? 'SUCCESS';
        final msg = data['message'] ?? 'Patch applied successfully by Laptop Bridge.';
        return FilePushResult(
          success: buildStatus == 'BUILD PASSING',
          filePath: 'http://$host:$daemonPort/apply-patch',
          message: '$msg (CI: $buildStatus)',
          record: record,
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

    // If network failed with a valid record from daemon (e.g. tests failed)
    if (netResult.record != null) {
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
  final Map<String, dynamic>? record;

  const FilePushResult({
    required this.success,
    required this.filePath,
    required this.message,
    this.record,
  });
}
