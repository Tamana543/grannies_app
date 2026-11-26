import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/care_plan.dart';
import '../services/app_store.dart';
import '../theme.dart';
import '../widgets/common.dart';

class GrandmaPairPage extends StatefulWidget {
  const GrandmaPairPage({super.key, required this.store});
  final AppStore store;
  @override
  State<GrandmaPairPage> createState() => _GrandmaPairPageState();
}

class _GrandmaPairPageState extends State<GrandmaPairPage>
    with WidgetsBindingObserver {
  Timer? timer;
  bool busy = false;
  String status = 'Looking for your family’s care plan…';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        check();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  Future<void> check() async {
    if (busy || !mounted) return;
    setState(() => busy = true);
    try {
      final found = await widget.store.refreshGrandma();
      if (mounted && !found) {
        setState(
          () => status = 'Waiting for your helper to share a care plan. We’ll check again automatically.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => status = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back to welcome',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () async {
          try {
            await widget.store.chooseRole('');
          } catch (e) {
            if (context.mounted) showError(context, friendlyError(e));
          }
        },
      ),
    ),
    body: SafeArea(
      child: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const Center(child: Brand()),
            const SizedBox(height: 38),
            const Center(child: CareIllustration(size: 132)),
            const SizedBox(height: 30),
            Text(
              'Care starts with\na little connection.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 14),
            const Text('Your family code', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: widget.store.code
                  .split('')
                  .map(
                    (char) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      padding: const EdgeInsets.only(bottom: 10),
                      width: 50,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: red, width: 4),
                        ),
                      ),
                      child: Text(
                        char,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'sans-serif-rounded',
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            const Text(
              'Share these four letters and numbers with your child or helper so they can set up your daily medicines.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await native.invokeMethod<void>('shareCode', {
                    'code': widget.store.code,
                  });
                } catch (_) {
                  if (context.mounted) {
                    showError(
                      context,
                      'Could not open sharing. You can copy the code instead.',
                    );
                  }
                }
              },
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share to WhatsApp'),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.store.code));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Family code copied')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy code'),
            ),
            const SizedBox(height: 24),
            Panel(
              color: paleGreen,
              child: Column(
                children: [
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Text(status, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: busy ? null : check,
                    child: const Text('Check again'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MedicineDraft {
  _MedicineDraft(this.name, this.times);
  String name;
  List<String> times;
  final Object id = Object();
}

class HelperSetupPage extends StatefulWidget {
  const HelperSetupPage({super.key, required this.store});
  final AppStore store;
  @override
  State<HelperSetupPage> createState() => _HelperSetupPageState();
}

class _HelperSetupPageState extends State<HelperSetupPage> {
  final form = GlobalKey<FormState>();
  final codeFields = List.generate(4, (_) => TextEditingController());
  final codeFocus = List.generate(4, (_) => FocusNode());
  late final TextEditingController age, grandma, helper, helperPhone;
  final List<_MedicineDraft> medicines = [];
  final pager = PageController();
  int step = 0;
  bool busy = false, moving = false;
  String? saveError;
  @override
  void initState() {
    super.initState();
    final draft = widget.store.draft;
    final code = draft['grandmaCode'] as String? ?? '';
    for (var i = 0; i < code.length && i < 4; i++) {
      codeFields[i].text = code[i];
    }
    age = TextEditingController(text: draft['age'] as String? ?? '');
    grandma = TextEditingController(
      text: draft['grandmaName'] as String? ?? '',
    );
    helper = TextEditingController(text: draft['helperName'] as String? ?? '');
    helperPhone = TextEditingController(
      text: draft['helperPhone'] as String? ?? '',
    );
    for (final item in draft['medicines'] as List? ?? []) {
      medicines.add(
        _MedicineDraft(
          item['name'] as String,
          List<String>.from(item['times'] as List),
        ),
      );
    }
    if (medicines.isEmpty) medicines.add(_MedicineDraft('', ['08:00']));
    step = (draft['step'] as int? ?? 0).clamp(0, 4);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pager.hasClients) pager.jumpToPage(step);
    });
  }

  @override
  void dispose() {
    for (final c in codeFields) {
      c.dispose();
    }
    for (final f in codeFocus) {
      f.dispose();
    }
    age.dispose();
    grandma.dispose();
    helper.dispose();
    helperPhone.dispose();
    pager.dispose();
    super.dispose();
  }

  Future<void> cache() async {
    widget.store.draft = {
      'grandmaCode': codeFields.map((c) => c.text).join(),
      'age': age.text,
      'grandmaName': grandma.text,
      'helperName': helper.text,
      'helperPhone': helperPhone.text,
      'step': step,
      'medicines': medicines
          .map((m) => {'name': m.name, 'times': m.times})
          .toList(),
    };
    await widget.store.persist();
  }

  void changed(String _) {
    cache().catchError((Object e) {
      if (mounted) {
        showError(
          context,
          'Could not save setup progress. Please check device storage.',
        );
      }
    });
  }

  Future<void> move(int target) async {
    if (busy || moving) return;
    if (target > step && !(form.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => moving = true);
    final old = step;
    try {
      if (old == 0 && target == 1) {
  final family = await widget.store.lookupFamily(
    codeFields.map((c) => c.text).join(),
  );
  if (family == null) {
    if (mounted) {
      showError(context,
          'That code was not found. Ask grandma to open Grannies so her code is registered, then try again.');
    }
    return;
  }
  if (!mounted) return;
  setState(() {
    if (age.text.isEmpty && family.age > 0) age.text = '${family.age}';
    if (grandma.text.isEmpty) grandma.text = family.grandmaName;
    if (helper.text.isEmpty) helper.text = family.helperName;
    if (helperPhone.text.isEmpty) helperPhone.text = family.helperPhone;
    final untouched =
        medicines.length == 1 && medicines.first.name.trim().isEmpty;
    if (untouched && family.medicines.isNotEmpty) {
      medicines
        ..clear()
        ..addAll(family.medicines.map(
            (m) => _MedicineDraft(m.name, List<String>.from(m.times))));
    }
  });
}
      step = target;
      await cache();
      if (!mounted) return;
      await pager.animateToPage(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
      if (mounted) setState(() {});
    } catch (e) {
      step = old;
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => moving = false);
    }
  }

  Future<void> save() async {
    if (!(form.currentState?.validate() ?? false)) return;
    final names = medicines.map((m) => m.name.trim().toLowerCase()).toSet();
    if (names.length != medicines.length) {
      showError(
        context,
        'Use a different name for each medicine, or add more times to the same entry.',
      );
      return;
    }
    final code = codeFields.map((c) => c.text).join();
    if (!validCode(code)) {
      showError(context, 'Enter grandma’s four-character code.');
      return;
    }
    final plan = CarePlan(
      grandmaCode: code,
      helperCode: widget.store.code,
      age: int.parse(age.text),
      grandmaName: grandma.text.trim(),
      helperName: helper.text.trim(),
      helperPhone: normalizePhone(helperPhone.text),
      medicines: medicines
          .map(
            (m) => Medicine(
              name: m.name.trim(),
              times: m.times.toSet().toList()..sort(),
            ),
          )
          .toList(),
    );
    if (plan.encode().length > 1000) {
      showError(
        context,
        'The plan is too long for this API’s 1,000-character field. Please shorten it.',
      );
      return;
    }
    setState(() {
      busy = true;
      saveError = null;
    });
    try {
      await cache();
      // Persist first; the dashboard owns retryable server synchronization.
      await widget.store.savePlan(plan);
    } catch (e) {
      if (mounted) {
        setState(() {
          saveError = friendlyError(e);
          busy = false;
        });
      }
    }
  }

  String? requiredName(String? value) => value == null || value.trim().isEmpty
      ? 'Please enter a name'
      : value.contains('/')
      ? 'Replace / with a space for this server'
      : null;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Brand()),
    body: SafeArea(
      child: PageBody(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR FAMILY, CONNECTED',
                    style: TextStyle(
                      color: green,
                      fontSize: 11,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Expanded(
                        child: Container(
                          height: 5,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: i <= step ? green : const Color(0xFFE5ECE5),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Step ${step + 1} of 5 · ${['Connection', 'About grandma', 'About grandma', 'About you', 'Daily routine'][step]}',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: form,
                child: PageView(
                  controller: pager,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _question(
                      'Add grandma’s code',
                      'Four little characters. A whole lot of care.',
                      Column(
                        children: [
                          const Center(child: CareIllustration(size: 100)),
                          const SizedBox(height: 28),
                          Row(
                            children: List.generate(
                              4,
                              (i) => Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: i == 3 ? 0 : 10,
                                  ),
                                  child: TextFormField(
                                    controller: codeFields[i],
                                    focusNode: codeFocus[i],
                                    textAlign: TextAlign.center,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    autocorrect: false,
                                    maxLength: 1,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp('[a-zA-Z0-9]'),
                                      ),
                                      TextInputFormatter.withFunction(
                                        (old, value) => value.copyWith(
                                          text: value.text.toUpperCase(),
                                        ),
                                      ),
                                    ],
                                    decoration: InputDecoration(
                                      counterText: '',
                                      labelText: ' ${i + 1}',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 18,
                                          ),
                                    ),
                                    validator: (v) =>
                                        step == 0 &&
                                            (v == null || v.length != 1)
                                        ? 'Enter'
                                        : null,
                                    onChanged: (v) {
                                      if (v.isNotEmpty && i < 3) {
                                        codeFocus[i + 1].requestFocus();
                                      }
                                      changed(v);
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Ask grandma to share the code shown on her screen.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    _question(
                      'How old is grandma?',
                      'Let’s get to know the person you love.',
                      TextFormField(
                        controller: age,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Grandma’s age',
                          suffixText: 'years',
                        ),
                        onChanged: changed,
                        validator: (v) =>
                            step == 1 &&
                                ((int.tryParse(v ?? '') ?? 0) < 1 ||
                                    (int.tryParse(v ?? '') ?? 0) > 130)
                            ? 'Enter an age from 1 to 130'
                            : null,
                      ),
                    ),
                    _question(
                      'What’s grandma’s name?',
                      'The name that always feels like home.',
                      TextFormField(
                        controller: grandma,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Grandma’s name',
                        ),
                        onChanged: changed,
                        validator: (v) => step == 2 ? requiredName(v) : null,
                      ),
                    ),
                    _question(
                      'And what’s your name?',
                      'Every caring routine starts with you.',
                      Column(
                        children: [
                          TextFormField(
                            controller: helper,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 60,
                            decoration: const InputDecoration(
                              labelText: 'Your name',
                            ),
                            onChanged: changed,
                            validator: (v) =>
                                step == 3 ? requiredName(v) : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: helperPhone,
                            keyboardType: TextInputType.phone,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            maxLength: 20,
                            decoration: const InputDecoration(
                              labelText: 'Your phone number',
                              hintText: '01XXXXXXXXX or +8801XXXXXXXXX',
                              helperText:
                                  'Grandma’s SOS messages will be sent here.',
                            ),
                            onChanged: changed,
                            validator: (v) => step == 3 && !validPhone(v ?? '')
                                ? 'Enter a valid Bangladesh mobile number'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    _question(
                      'A little daily routine',
                      'Add her medicines and the times she takes them. These times repeat every day.',
                      Column(
                        children: [
                          for (var i = 0; i < medicines.length; i++)
                            _medicine(medicines[i], i),
                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : () {
                                    setState(
                                      () => medicines.add(
                                        _MedicineDraft('', ['08:00']),
                                      ),
                                    );
                                    changed('');
                                  },
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            label: const Text('Add a medicine'),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Times are shown in this phone’s local time. Add only the schedule already agreed with her clinician.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (saveError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(saveError!, style: const TextStyle(color: red)),
              ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: busy || moving
                        ? null
                        : () async {
                            if (step > 0) {
                              await move(step - 1);
                            } else {
                              try {
                                await cache();
                                await widget.store.chooseRole('');
                              } catch (e) {
                                if (context.mounted) {
                                  showError(context, friendlyError(e));
                                }
                              }
                            }
                          },
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: busy || moving
                        ? null
                        : () => step == 4 ? save() : move(step + 1),
                    icon: Icon(
                      step == 4
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                    label: Text(
                      busy
                          ? 'Saving…'
                          : step == 4
                          ? 'Save routine'
                          : 'Next',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _question(String title, String subtitle, Widget child) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 10),
      Text(subtitle),
      const SizedBox(height: 28),
      Panel(child: child),
    ],
  );
  Widget _medicine(_MedicineDraft medicine, int index) => Padding(
    key: ObjectKey(medicine.id),
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'MEDICINE ${index + 1}',
              style: const TextStyle(
                fontSize: 11,
                color: green,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            if (medicines.length > 1)
              IconButton(
                tooltip: 'Remove medicine ${index + 1}',
                onPressed: () {
                  setState(() => medicines.remove(medicine));
                  changed('');
                },
                icon: const Icon(Icons.close_rounded, color: red),
              ),
          ],
        ),
        TextFormField(
          initialValue: medicine.name,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Medicine name'),
          validator: (v) => step == 4 ? requiredName(v) : null,
          onChanged: (v) {
            medicine.name = v;
            changed(v);
          },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var j = 0; j < medicine.times.length; j++)
              InputChip(
                label: Text(medicine.times[j]),
                avatar: const Icon(Icons.schedule_rounded, size: 16),
                onPressed: () => pickTime(medicine, j),
                onDeleted: medicine.times.length > 1
                    ? () {
                        setState(() => medicine.times.removeAt(j));
                        changed('');
                      }
                    : null,
              ),
            ActionChip(
              label: const Text('+ Time'),
              onPressed: () => pickTime(medicine, null),
            ),
          ],
        ),
      ],
    ),
  );
  Future<void> pickTime(_MedicineDraft medicine, int? index) async {
    final parts = (index == null ? '08:00' : medicine.times[index]).split(':');
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (result == null || !mounted) return;
    final text =
        '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (index == null) {
        medicine.times.add(text);
      } else {
        medicine.times[index] = text;
      }
    });
    changed('');
  }
}
