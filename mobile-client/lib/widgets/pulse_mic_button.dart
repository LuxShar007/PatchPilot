import 'package:flutter/material.dart';

/// Animated microphone button with glowing multi-ripple pulses when actively listening
class PulseMicButton extends StatefulWidget {
  final bool isListening;
  final VoidCallback onTap;
  final double size;

  const PulseMicButton({
    super.key,
    required this.isListening,
    required this.onTap,
    this.size = 56.0,
  });

  @override
  State<PulseMicButton> createState() => _PulseMicButtonState();
}

class _PulseMicButtonState extends State<PulseMicButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _secondaryPulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.45).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad),
    );

    _secondaryPulseAnimation = Tween<double>(begin: 1.0, end: 1.7).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutQuad),
      ),
    );

    if (widget.isListening) {
      _controller.repeat(reverse: false);
    }
  }

  @override
  void didUpdateWidget(covariant PulseMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !_controller.isAnimating) {
      _controller.repeat(reverse: false);
    } else if (!widget.isListening && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final alpha1 = (1.0 - progress).clamp(0.0, 1.0) * 0.35;
        final alpha2 = (1.0 - progress).clamp(0.0, 1.0) * 0.2;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer secondary ripple ring
            if (widget.isListening)
              Container(
                width: widget.size * _secondaryPulseAnimation.value,
                height: widget.size * _secondaryPulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withValues(alpha: alpha2),
                ),
              ),

            // Inner primary ripple ring
            if (widget.isListening)
              Container(
                width: widget.size * _pulseAnimation.value,
                height: widget.size * _pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withValues(alpha: alpha1),
                ),
              ),

            // Center Interactive Mic Button
            GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isListening ? const Color(0xFF09090B) : Colors.white,
                  border: Border.all(
                    color: widget.isListening ? const Color(0xFF10B981) : const Color(0xFFE7E7E4),
                    width: widget.isListening ? 2.0 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                    if (widget.isListening)
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: Icon(
                  widget.isListening ? Icons.mic : Icons.mic_none,
                  color: widget.isListening ? const Color(0xFF10B981) : const Color(0xFF111111),
                  size: widget.size * 0.46,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
