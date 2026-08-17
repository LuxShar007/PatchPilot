import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Service for clipboard synchronization and workspace file transfer bridge
class BridgeService {
  static const String defaultPatchFileName = 'fix.patch';
  static const String bridgeDirectoryName = 'inbox_patches';

  /// Action 1: "Copy Diff" -> Copies patch_diff to system clipboard (scored via Office Kit)
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

  /// Action 2: "Push to Bridge" -> Saves patch_diff as fix.patch into inbox_patches/
  static Future<FilePushResult> pushToBridge(
    String patchDiff, {
    String filename = defaultPatchFileName,
    String? customDirectoryPath,
  }) async {
    try {
      Directory targetDir;

      if (customDirectoryPath != null && customDirectoryPath.isNotEmpty) {
        targetDir = Directory(customDirectoryPath);
      } else {
        // Use application documents directory or external storage
        Directory baseDir;
        if (kIsWeb) {
          return const FilePushResult(
            success: true,
            filePath: 'inbox_patches/$defaultPatchFileName',
            message: 'Simulated bridge write on Web',
          );
        } else {
          baseDir = await getApplicationDocumentsDirectory();
        }
        targetDir = Directory('${baseDir.path}/$bridgeDirectoryName');
      }

      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final file = File('${targetDir.path}/$filename');
      await file.writeAsString(patchDiff, flush: true);

      debugPrint('Successfully wrote patch to: ${file.path}');
      return FilePushResult(
        success: true,
        filePath: file.path,
        message: 'Saved $filename to inbox_patches/',
      );
    } catch (e) {
      debugPrint('Error pushing patch to bridge: $e');
      return FilePushResult(
        success: false,
        filePath: '',
        message: 'Failed to write patch: $e',
      );
    }
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
