import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grannies_healthbar/models/care_plan.dart';
import 'package:grannies_healthbar/services/app_store.dart';

CarePlan phonePlan() => CarePlan(
  grandmaCode: 'AB23',
  helperCode: 'XY89',
  age: 74,
  grandmaName: 'Rose',
  helperName: 'Sam',
  helperPhone: '01812-345678',
  medicines: [
    Medicine(name: 'Vitamin D', times: ['08:00', '20:30']),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Bangladesh phone formats normalize to the bdapps address format', () {
    for (final phone in [
      '01812345678',
      '+880 1812-345678',
      '008801812345678',
    ]) {
      expect(validPhone(phone), isTrue);
      expect(normalizePhone(phone), '8801812345678');
    }
    for (final phone in [
      '',
      'AB23',
      '01812',
      '01212345678',
      '+1 555 123 4567',
    ]) {
      expect(validPhone(phone), isFalse);
    }
  });

  test('phone survives server JSON and legacy records still load', () {
    final plan = phonePlan();
    final parsed = findPlan([
      {'text': plan.encode()},
    ], 'AB23')!;
    expect(parsed.helperPhone, '8801812345678');
    final legacy = plan.details..remove('helperPhone');
    expect(CarePlan.fromEntry(plan.key, legacy).helperPhone, isEmpty);
    expect(parsed.medicines.single.times, ['08:00', '20:30']);
  });

  test('only grandma schedules reminders, changing role clears them', () async {
    final directory = await Directory.systemTemp.createTemp('phone_reminders_');
    final calls = <dynamic>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'scheduleMedicines') calls.add(call.arguments);
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(native, null);
      await directory.delete(recursive: true);
    });
    final store = AppStore(directory)
      ..code = 'AB23'
      ..plan = phonePlan();
    await store.chooseRole('grandma');
    expect(calls.last['events'], [
      {'name': 'Vitamin D', 'time': '08:00'},
      {'name': 'Vitamin D', 'time': '20:30'},
    ]);
    store.reminderPrompted = true;
    await store.persist();
    final reopened = AppStore(directory);
    await reopened.load();
    expect(reopened.plan!.helperPhone, '8801812345678');
    expect(reopened.reminderPrompted, isTrue);
    await store.chooseRole('helper');
    expect(calls.last['events'], isEmpty);
  });
}
