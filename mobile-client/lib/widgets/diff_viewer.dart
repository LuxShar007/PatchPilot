import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Formatted interactive Diff Viewer for PatchPilot with colored unified diff rendering
class DiffViewer extends StatelessWidget {
  final String patchDiff;
  final String? fileName;

  const DiffViewer({
    super.key,
    required this.patchDiff,
    this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final lines = patchDiff.split('\n');

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Dark slate IDE background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
              border: Border(
                bottom: BorderSide(color: Color(0xFF334155), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.code, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName ?? 'patch.diff',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFF1F5F9),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.4)),
                  ),
                  child: const Text(
                    'UNIFIED DIFF',
                    style: TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Diff Code Body
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(lines.length, (index) {
                  final line = lines[index];
                  if (line.isEmpty && index == lines.length - 1) return const SizedBox.shrink();
                  return _buildDiffLine(line, index + 1);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffLine(String line, int lineNumber) {
    Color textColor = const Color(0xFFCBD5E1); // Default slate text
    Color bgColor = Colors.transparent;
    Widget? prefixIcon;

    if (line.startsWith('+') && !line.startsWith('+++')) {
      // Added line
      textColor = const Color(0xFF4ADE80); // Emerald green
      bgColor = const Color(0xFF052E16).withOpacity(0.6);
      prefixIcon = const Text(
        '+',
        style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold, fontFamily: 'monospace'),
      );
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      // Removed line
      textColor = const Color(0xFFF87171); // Crimson red
      bgColor = const Color(0xFF450A0A).withOpacity(0.6);
      prefixIcon = const Text(
        '-',
        style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontFamily: 'monospace'),
      );
    } else if (line.startsWith('@@')) {
      // Hunk header
      textColor = const Color(0xFF38BDF8); // Cyan
      bgColor = const Color(0xFF082F49).withOpacity(0.5);
    } else if (line.startsWith('---') || line.startsWith('+++')) {
      // File header
      textColor = const Color(0xFF94A3B8);
      bgColor = const Color(0xFF1E293B).withOpacity(0.3);
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line Number Indicator
          SizedBox(
            width: 32,
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Prefix marker
          SizedBox(
            width: 12,
            child: prefixIcon ?? const SizedBox.shrink(),
          ),
          const SizedBox(width: 6),
          // Code content
          Text(
            line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              color: textColor,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
