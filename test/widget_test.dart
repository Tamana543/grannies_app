import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grannies_healthbar/main.dart';
import 'package:grannies_healthbar/services/app_store.dart';

void main() {
  testWidgets(
    'helper onboarding validates, caches code and navigates both ways',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'grannies_ui_test',
      );
      final store = AppStore(directory)..code = 'XY89';
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: GranniesApp(store: store),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('I’m a grandma'), findsOneWidget);
      expect(find.text('I’m a helper'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await tester.runAsync(
        () =>
            File('/tmp/grannies-welcome.png')
                .writeAsBytes(bytes!.buffer.asUint8List()),
      );
      image.dispose();
      await tester.ensureVisible(find.text('I’m a helper'));
      await tester.tap(find.text('I’m a helper'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Add grandma’s code'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Enter'), findsNWidgets(4));
      final fields = find.byType(TextFormField);
      for (var i = 0; i < 4; i++) {
        await tester.enterText(fields.at(i), 'AB23'[i]);
      }
      await tester.tap(find.text('Next'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('How old is grandma?'), findsOneWidget);
      expect(store.draft['grandmaCode'], 'AB23');
      await tester.enterText(find.byType(TextFormField).last, '74');
      await tester.tap(find.text('Next'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('What’s grandma’s name?'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('How old is grandma?'), findsOneWidget);
      expect(store.draft['age'], '74');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await store.persist();
        await directory.delete(recursive: true);
      });
    },
  );
}
