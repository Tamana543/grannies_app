import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/care_plan.dart';
import 'api_service.dart';

const native = MethodChannel('grannies_healthbar/device');

class AppStore extends ChangeNotifier {
  AppStore(this.directory);
  final Directory directory;
  String code = '', role = '', photoPath = '';
  String apiAddress = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://bdappsdigitalapps.com/auw26/AUW242106/',
  );
  Map<String, dynamic> draft = {};
  CarePlan? plan;
  bool pendingSync = false;
  bool reminderPrompted = false;
  File get _file => File('${directory.path}/care_state.json');
  Future<CarePlan?> lookupFamily(String familyCode) =>
    ApiService(apiAddress).lookup(familyCode, helperCode: code);
  Future<void> load() async {
    if (await _file.exists()) {
      final data =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      code = data['code'] as String;
      role = data['role'] as String? ?? '';
      photoPath = data['photoPath'] as String? ?? '';
      final savedAddress = data['apiAddress'] as String?;
if (savedAddress != null && !savedAddress.contains('pythonanywhere.com')) {
  apiAddress = savedAddress;
}
      draft = Map<String, dynamic>.from(data['draft'] as Map? ?? {});
      pendingSync = data['pendingSync'] == true;
      reminderPrompted = data['reminderPrompted'] == true;
      if (data['plan'] is Map) {
        final entry = (data['plan'] as Map).entries.first;
        plan = CarePlan.fromEntry(
          '${entry.key}',
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
      if (!validCode(code)) {
        throw const FormatException('Saved identity is invalid.');
      }
      return;
    }
    String device = 'Android';
    try {
      device = await native.invokeMethod<String>('deviceInfo') ?? device;
    } on PlatformException {
      /* Optional device hint. */
    }
    final random = Random.secure();
    final seed =
        '$device-${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
    final hint = seed.codeUnits.fold<int>(
      0,
      (a, b) => (a * 31 + b) & 0x7fffffff,
    );
    code = List.generate(
      4,
      (i) =>
          codeAlphabet[(random.nextInt(codeAlphabet.length) +
                  (hint >> (i * 4))) %
              codeAlphabet.length],
    ).join();
    await persist();
  }

  Future<void> _tail = Future<void>.value();
  Future<void> persist() {
    final contents = jsonEncode({
      'code': code,
      'role': role,
      'photoPath': photoPath,
      'apiAddress': apiAddress,
      'draft': draft,
      'plan': plan?.toWire(),
      'pendingSync': pendingSync,
      'reminderPrompted': reminderPrompted,
    });
    final write = _tail.then((_) async {
      await directory.create(recursive: true);
      final temp = File('${_file.path}.tmp');
      await temp.writeAsString(contents, flush: true);
      await temp.rename(_file.path);
    });
    _tail = write.catchError((Object _) {});
    return write;
  }

  Future<void> chooseRole(String value) async {
    final previous = role;
    role = value;
    try {
      await persist();
    } catch (_) {
      role = previous;
      rethrow;
    }
    notifyListeners();
    await scheduleReminders();
  }

  Future<void> savePlan(CarePlan value) async {
    final previous = plan;
    final wasPending = pendingSync;
    plan = value;
    pendingSync = true;
    try {
      await persist();
    } catch (_) {
      plan = previous;
      pendingSync = wasPending;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> sync() async {
    final current = plan;
    if (current == null) return;
    await ApiService(apiAddress).save(current);
    pendingSync = false;
    try {
      await persist();
    } catch (_) {
      pendingSync = true;
      rethrow;
    }
    notifyListeners();
  }

  
    Future<bool> refreshGrandma() async {
    final api = ApiService(apiAddress);
    try {
      await api.registerCode(code);
    } catch (_) {
      // Not fatal; the check below reports connection problems.
    }
    final result = await api.fetch(code);
    if (result == null) return false;
    final previous = plan;
    plan = result;
    try {
      await persist();
    } catch (_) {
      plan = previous;
      rethrow;
    }
    notifyListeners();
    await scheduleReminders();
    return true;
  }

  Future<void> scheduleReminders() async {
    try {
      await native.invokeMethod<void>('scheduleMedicines', {
        'events': [
          if (role == 'grandma' && plan != null)
            for (final medicine in plan!.medicines)
              for (final time in medicine.times)
                {'name': medicine.name, 'time': time},
        ],
      });
    } on MissingPluginException {
      // No Android host in standalone domain/widget checks.
    }
  }
}

String friendlyError(Object error) {
    if (error is TimeoutException) {
    return 'The server took too long to answer. Your saved information is still here.';
  }
  if (error is SocketException) {
    return 'Cannot reach the server. Check its address and your connection. Your saved information is still here.';
  }
  if (error is FormatException) return error.message;
  if (error is HttpException) return error.message;
  return 'Something went wrong. Your saved information is still here. Please try again.';
}
