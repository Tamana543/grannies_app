import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_store.dart';
import '../theme.dart';
import '../widgets/common.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.store});
  final AppStore store;
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final pages = PageController();
  Timer? timer;
  int index = 0;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (pages.hasClients && !MediaQuery.disableAnimationsOf(context)) {
        pages.animateToPage(
          (index + 1) % 3,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    pages.dispose();
    super.dispose();
  }

  Future<void> choose(String role) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.store.chooseRole(role);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showError(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            const Center(child: Brand()),
            const SizedBox(height: 28),
            Text(
              'Welcome to a little\npeace of mind.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Small moments of care. Every single day.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            SizedBox(
              height:
                  206 *
                  MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: PageView(
                  controller: pages,
                  onPageChanged: (value) => setState(() => index = value),
                  children: [
                    _banner(
                      'A little closer,\nwherever you are.',
                      'Care that connects generations.',
                      paleGreen,
                      false,
                    ),
                    _banner(
                      'A simple routine.\nA calmer day.',
                      'Daily medicines, together in one place.',
                      const Color(0xFFF3F1E5),
                      false,
                    ),
                    _banner(
                      'Love is in the\nlittle check-ins.',
                      'Make room for what matters most.',
                      paleRed,
                      true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: index == i ? 24 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: index == i ? green : const Color(0xFFD9E4DA),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Who are we caring for?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text('Choose your place in the family.'),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  _role(
                    'I’m a grandma',
                    'Let my family care for me',
                    'If you have lovely children who want to take care of you, press this.',
                    false,
                  ),
                  _role(
                    'I’m a helper',
                    'Care for someone I love',
                    'If you have someone who is important to you and you want to keep them safe, choose this.',
                    true,
                  ),
                ];
                if (constraints.maxWidth < 330 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                  return Column(
                    children: [cards[0], const SizedBox(height: 14), cards[1]],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 14),
                    Expanded(child: cards[1]),
                  ],
                );
              },
            ),
            const SizedBox(height: 26),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_outline_rounded, color: muted, size: 16),
                SizedBox(width: 8),
                Text(
                  'Made for families. Made with care.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  Widget _banner(String title, String subtitle, Color color, bool helper) =>
      Container(
        color: color,
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'A LITTLE CARE GOES A LONG WAY',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: green,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 23,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(subtitle, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CareIllustration(helper: helper, size: 94),
          ],
        ),
      );
  Widget _role(
    String title,
    String subtitle,
    String explanation,
    bool helper,
  ) => Tooltip(
    message: explanation,
    triggerMode: TooltipTriggerMode.longPress,
    child: Semantics(
      button: true,
      label: '$title. $explanation',
      child: PressCard(
        color: helper ? paleRed : paleGreen,
        onTap: () => choose(helper ? 'helper' : 'grandma'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 18),
          child: Column(
            children: [
              CareIllustration(helper: helper, size: 92),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Icon(Icons.arrow_forward_rounded, color: helper ? red : green),
            ],
          ),
        ),
      ),
    ),
  );
}
