import 'package:flutter/material.dart';

import '../theme.dart';

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: child,
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(24),
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xFFE4EBE4)),
    ),
    child: child,
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.favorite_rounded, color: green, size: 22),
      SizedBox(width: 8),
      Text(
        'grannies',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: ink),
      ),
      Text(' / healthbar', style: TextStyle(fontSize: 13, color: muted)),
    ],
  );
}

class PressCard extends StatefulWidget {
  const PressCard({
    super.key,
    required this.child,
    required this.onTap,
    this.color = Colors.white,
  });
  final Widget child;
  final VoidCallback onTap;
  final Color color;
  @override
  State<PressCard> createState() => _PressCardState();
}

class _PressCardState extends State<PressCard> {
  bool down = false;
  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: down ? .97 : 1,
    duration: const Duration(milliseconds: 140),
    curve: Curves.easeOutCubic,
    child: Material(
      color: widget.color,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => down = value),
        child: widget.child,
      ),
    ),
  );
}

class CareIllustration extends StatelessWidget {
  const CareIllustration({super.key, this.helper = false, this.size = 110});
  final bool helper;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size * .9,
          height: size * .9,
          decoration: BoxDecoration(
            color: helper ? const Color(0xFFF5DAD3) : const Color(0xFFD8E8D3),
            shape: BoxShape.circle,
          ),
        ),
        Positioned(
          bottom: 1,
          child: Container(
            width: size * .72,
            height: size * .42,
            decoration: BoxDecoration(
              color: helper ? red : green,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(size * .4),
                bottom: const Radius.circular(18),
              ),
            ),
          ),
        ),
        Positioned(
          top: size * .15,
          child: Container(
            width: size * .48,
            height: size * .52,
            decoration: BoxDecoration(
              color: const Color(0xFFF2CCAC),
              borderRadius: BorderRadius.circular(size * .22),
              border: Border(
                top: BorderSide(
                  color: helper
                      ? const Color(0xFF4B3E37)
                      : const Color(0xFFF7F5EF),
                  width: size * .12,
                ),
              ),
            ),
            child: Icon(
              helper ? Icons.face_rounded : Icons.face_6_rounded,
              color: const Color(0xFF594F43),
              size: size * .4,
            ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: size * .12,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.favorite_rounded,
              color: helper ? red : green,
              size: size * .17,
            ),
          ),
        ),
      ],
    ),
  );
}

void showError(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
