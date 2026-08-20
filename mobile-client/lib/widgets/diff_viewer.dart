import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Formatted interactive Diff Viewer for RecTrace with colored unified diff rendering and copy actions
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
        color: const Color(0xFF121215), // Deep zinc dark surface
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF27272A), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Minimalist Window Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF09090B),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(19),
                topRight: Radius.circular(19),
              ),
              border: Border(
                bottom: BorderSide(color: Color(0xFF27272A), width: 1),
              ),
            ),
            child: Row(
              children: [
                // Three subtle macOS style window dots
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                const Icon(Icons.code_rounded, color: Color(0xFFA1A1AA), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName ?? 'patch.diff',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFFF4F4F5),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Quick Copy Diff button
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: Color(0xFFA1A1AA), size: 15),
                  tooltip: 'Copy Diff Text',
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: patchDiff));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Unified diff copied to clipboard!'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF27272A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'UNIFIED DIFF',
                    style: TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
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
    Color textColor = const Color(0xFFD4D4D8);
    Color bgColor = Colors.transparent;
    Widget? prefixIcon;

    if (line.startsWith('+') && !line.startsWith('+++')) {
      // Insertions: Translucent emerald green
      textColor = const Color(0xFF34D399);
      bgColor = const Color(0x2210B981);
      prefixIcon = const Text(
        '+',
        style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontFamily: 'monospace'),
      );
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      // Deletions: Translucent red
      textColor = const Color(0xFFF87171);
      bgColor = const Color(0x22EF4444);
      prefixIcon = const Text(
        '-',
        style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontFamily: 'monospace'),
      );
    } else if (line.startsWith('@@')) {
      // Hunk header
      textColor = const Color(0xFF93C5FD);
      bgColor = const Color(0x223B82F6);
    } else if (line.startsWith('---') || line.startsWith('+++')) {
      // File header
      textColor = const Color(0xFFA1A1AA);
      bgColor = const Color(0xFF27272A).withValues(alpha: 0.5);
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2.5),
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
                color: Color(0xFF71717A),
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
