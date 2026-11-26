// Direct headless smoke check: no test-driver or VM-service sockets required.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:grannies_healthbar/main.dart';
import 'package:grannies_healthbar/screens/onboarding.dart';
import 'package:grannies_healthbar/services/app_store.dart';
import 'package:grannies_healthbar/widgets/common.dart';

class _SmokeBinding extends WidgetsFlutterBinding {
  @override
  ViewConfiguration createViewConfigurationFor(
    RenderView renderView,
  ) => ViewConfiguration(
    logicalConstraints: const BoxConstraints.tightFor(width: 390, height: 844),
    physicalConstraints: const BoxConstraints.tightFor(width: 390, height: 844),
    devicePixelRatio: 1,
  );
}

Iterable<Element> descendants(Element element) sync* {
  yield element;
  final children = <Element>[];
  element.visitChildren(children.add);
  for (final child in children) {
    yield* descendants(child);
  }
}

Future<void> main() async {
  final binding = _SmokeBinding();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = (details) {
    errors.add(details);
    stderr.writeln(details);
  };
  final directory = await Directory.systemTemp.createTemp('grannies_smoke');
  final store = AppStore(directory)..code = 'XY89';
  store.reminderPrompted = true;
  await store.persist();
  final boundary = GlobalKey();
  runApp(
    RepaintBoundary(
      key: boundary,
      child: GranniesApp(store: store),
    ),
  );
  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 750));
    binding.scheduleFrame();
    await binding.endOfFrame;
  }

  List<T> widgets<T extends Widget>() =>
      descendants(binding.rootElement!)
          .map((e) => e.widget)
          .whereType<T>()
          .toList();
  bool hasText(String text) => widgets<Text>().any((w) => w.data == text);
  void check(bool value, String label) {
    if (!value) throw StateError(label);
    stdout.writeln('PASS $label');
  }

  Future<void> capture(String name) async {
    await settle();
    final image =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/grannies-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  Future<void> press(String text) async {
    final buttons = descendants(binding.rootElement!).where(
      (e) =>
          e.widget is ButtonStyleButton &&
          descendants(e)
              .any((c) => c.widget is Text && (c.widget as Text).data == text),
    );
    final button = buttons.first.widget as ButtonStyleButton;
    if (button.onPressed == null) throw StateError('Disabled button: $text');
    button.onPressed!();
    await settle();
  }

  try {
    await settle();
    check(
      hasText('I’m a grandma') && hasText('I’m a helper'),
      'Welcome has both illustrated role choices',
    );
    await capture('welcome');
    widgets<PressCard>().last.onTap();
    await settle();
    check(widgets<HelperSetupPage>().isNotEmpty, 'Helper choice opens setup');
    await press('Next');
    check(
      widgets<Text>().where((t) => t.data == 'Enter').length == 4,
      'Empty pairing fields show validation',
    );
    final codes = widgets<TextField>().where((f) => f.maxLength == 1).toList();
    for (var i = 0; i < 4; i++) {
      codes[i].controller!.text = 'XY89'[i];
      codes[i].onChanged!('XY89'[i]);
    }
    await settle();
    await press('Next');
    check(
      store.draft['grandmaCode'] == 'XY89' && store.draft['step'] == 1,
      'Pair code is cached before question transition',
    );
    final age = widgets<TextField>().firstWhere(
      (f) => f.controller != null && f.maxLength != 1,
    );
    age.controller!.text = '74';
    age.onChanged!('74');
    await settle();
    await press('Next');
    check(hasText('What’s grandma’s name?'), 'Age question advances');
    await press('Back');
    check(hasText('How old is grandma?'), 'Question pages navigate back');
    await press('Next');
    var field = widgets<TextField>().firstWhere((f) => f.maxLength == 60);
    field.controller!.text = 'Rose';
    field.onChanged!('Rose');
    await settle();
    await press('Next');
    field = widgets<TextField>().firstWhere((f) => f.maxLength == 60);
    field.controller!.text = 'Sam';
    field.onChanged!('Sam');
    final phone = widgets<EditableText>().firstWhere(
      (field) => field.keyboardType == TextInputType.phone,
    );
    phone.controller.text = '01812345678';
    phone.onChanged!('01812345678');
    await settle();
    await press('Next');
    await capture('medicines');
    final medicine = widgets<TextField>().firstWhere((f) => f.maxLength == 60);
    // Enter through EditableText so FormField validation sees the updated value.
    final editable = widgets<EditableText>().first;
    editable.controller.text = 'Vitamin D';
    editable.onChanged!('Vitamin D');
    medicine.onChanged!('Vitamin D');
    await settle();
    await press('Save routine');
    check(
      store.plan?.grandmaName == 'Rose' &&
          store.plan?.helperName == 'Sam' &&
          store.plan?.key == 'XY89--XY89',
      'Helper saves complete care plan using this device’s own code',
    );
    check(store.pendingSync, 'Unreachable server keeps retryable pending sync');
    await capture('helper-dashboard');
    final reopened = AppStore(directory);
    await reopened.load();
    check(
      reopened.code == store.code &&
          reopened.plan?.medicines.single.name == 'Vitamin D',
      'Identity and medicines survive reopening storage',
    );
    final plan = store.plan;
    store.plan = null;
    await store.chooseRole('grandma');
    await settle();
    check(
      widgets<GrandmaPairPage>().isNotEmpty,
      'Grandma pairing screen opens',
    );
    await capture('pairing');
    store.plan = plan;
    await store.chooseRole('grandma');
    await settle();
    await capture('grandma-dashboard');
    check(
      widgets<FilledButton>().any((b) => b.onPressed != null),
      'Grandma SOS button is available',
    );
    check(errors.isEmpty, 'All rendered screens have no Flutter layout errors');
    runApp(const SizedBox.shrink());
    await settle();
    await directory.delete(recursive: true);
    stdout.writeln('ALL HEADLESS SMOKE CHECKS PASSED');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
