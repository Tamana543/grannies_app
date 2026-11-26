import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/care_plan.dart';
import '../services/app_store.dart';
import '../services/bdapps_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.store});
  final AppStore store;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? timer;
  bool busy = false, picking = false;
  bool sosBusy = false;
  final bdapps = BdappsService();
  bool get isHelper => widget.store.role == 'helper';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await setupReminders();
      await refresh();
    });
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if ((!isHelper || widget.store.pendingSync) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        refresh();
      }
    });
  }

  Future<void> setupReminders({bool askAgain = false}) async {
    try {
      await widget.store.scheduleReminders();
      if (isHelper ||
          (widget.store.reminderPrompted && !askAgain) ||
          !mounted) {
        return;
      }
      final enable = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Medicine reminders'),
          content: const Text(
            'Allow notifications and alarms so this phone can remind you at your medicine times, even when the app is closed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable reminders'),
            ),
          ],
        ),
      );
      if (enable == null) return;
      widget.store.reminderPrompted = true;
      await widget.store.persist();
      if (enable) await native.invokeMethod<void>('requestReminderPermissions');
    } catch (e) {
      if (mounted) {
        showError(
          context,
          'Could not enable medicine reminders. Please check notification and alarm permissions for this app.',
        );
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (busy || !mounted) return;
    busy = true;
    try {
      if (isHelper) {
        if (widget.store.pendingSync) await widget.store.sync();
      } else {
        await widget.store.refreshGrandma();
      }
    } catch (_) {
      // Keep the saved routine available and retry silently on the next tick.
    } finally {
      busy = false;
    }
  }

  Future<void> sendSos() async {
    if (sosBusy) return;
    setState(() => sosBusy = true);
    try {
      final plan = widget.store.plan!;
      if (await bdapps.isSubscribed(plan.helperPhone)) {
        await bdapps.sendSos(plan);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('SOS message submitted to ${plan.helperName}.'),
            ),
          );
        }
      } else {
        await bdapps.subscribe(plan.helperPhone);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Family SOS is ready. Tap S.O.S to message ${plan.helperName}.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => sosBusy = false);
    }
  }

  Future<void> editHelperPhone() async {
    var enteredPhone = widget.store.plan!.helperPhone;
    final form = GlobalKey<FormState>();
    final phone = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your phone number'),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: enteredPhone,
            onChanged: (value) => enteredPhone = value,
            keyboardType: TextInputType.phone,
            maxLength: 20,
            decoration: const InputDecoration(
              hintText: '01XXXXXXXXX or +8801XXXXXXXXX',
              helperText: 'Receive grandma’s SOS messages here.',
            ),
            validator: (value) => validPhone(value ?? '')
                ? null
                : 'Enter a valid Bangladesh mobile number',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, enteredPhone);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (phone == null || !mounted) return;
    try {
      final updated = widget.store.plan!.withHelperPhone(phone);
      if (updated.encode().length > 1000) {
        throw const FormatException(
          'The care plan is too long to add a phone number. Please shorten the medicine names.',
        );
      }
      await widget.store.savePlan(updated);
      await refresh();
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    }
  }

  Future<void> pickPhoto() async {
    if (picking) return;
    setState(() => picking = true);
    try {
      final path = await native.invokeMethod<String>('pickFamilyPhoto');
      if (path != null) {
        final old = widget.store.photoPath;
        widget.store.photoPath = path;
        try {
          await widget.store.persist();
        } catch (_) {
          widget.store.photoPath = old;
          rethrow;
        }
        if (mounted) setState(() {});
        if (old.isNotEmpty &&
            old != path &&
            old.startsWith('${widget.store.directory.path}/family_')) {
          try {
            await File(old).delete();
          } on FileSystemException {
            /* Old cache cleanup is optional. */
          }
        }
      }
    } catch (_) {
      if (mounted) {
        showError(
          context,
          'Could not save that photo. Please try another image.',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.store.plan!;
    final events = [
      for (final medicine in plan.medicines)
        for (final time in medicine.times) (name: medicine.name, time: time),
    ]..sort((a, b) => a.time.compareTo(b.time));
    return Scaffold(
      appBar: AppBar(
        title: const Brand(),
        actions: [
          if (isHelper)
            IconButton(
              tooltip: 'Your phone number',
              icon: const Icon(Icons.phone_outlined),
              onPressed: editHelperPhone,
            ),
          if (!isHelper)
            IconButton(
              tooltip: 'Medicine reminders',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => setupReminders(askAgain: true),
            ),
        ],
      ),
      body: SafeArea(
        child: PageBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isHelper
                              ? 'A LITTLE CARE, EVERY DAY'
                              : 'IT’S GOOD TO SEE YOU',
                          style: const TextStyle(
                            color: green,
                            fontSize: 10,
                            letterSpacing: 1.7,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isHelper
                              ? 'Hello, ${plan.helperName}.'
                              : 'Hello, ${plan.grandmaName}.',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isHelper
                              ? '${plan.grandmaName}’s daily routine · ${plan.age} years'
                              : '${plan.helperName} is here for you. Here’s your daily routine.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    backgroundColor: paleGreen,
                    radius: 25,
                    child: Icon(
                      isHelper
                          ? Icons.favorite_outline_rounded
                          : Icons.wb_sunny_outlined,
                      color: green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (isHelper) ...[_familyPanel(), const SizedBox(height: 22)],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Today’s medicines',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: paleGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${events.length} scheduled',
                      style: const TextStyle(
                        fontSize: 11,
                        color: green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Your daily schedule · local time',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (events.isEmpty)
                const Panel(
                  child: Text('No medicines have been added to this routine.'),
                ),
              for (var i = 0; i < events.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    color: i.isEven
                        ? paleGreen.withValues(alpha: .65)
                        : paleRed.withValues(alpha: .55),
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.medication_outlined,
                            color: i.isEven ? green : red,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                events[i].name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: ink,
                                ),
                              ),
                              const Text(
                                'Every day',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          events[i].time,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!isHelper) ...[
                const SizedBox(height: 24),
                Center(
                  child: Semantics(
                    label: 'SOS',
                    child: Column(
                      children: [
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: FilledButton(
                            onPressed: sosBusy ? null : sendSos,
                            style: FilledButton.styleFrom(
                              shape: const CircleBorder(),
                              backgroundColor: red,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFFF2DEDA),
                              disabledForegroundColor: const Color(0xFF9B7772),
                            ),
                            child: sosBusy
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.phone_in_talk_rounded,
                                        size: 34,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'S.O.S',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _familyPanel() => Semantics(
    button: true,
    label: 'Choose a family photo. Automatically cropped to a rectangle.',
    child: PressCard(
      onTap: pickPhoto,
      color: paleGreen,
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: widget.store.photoPath.isNotEmpty
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(widget.store.photoPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _familyPlaceholder(),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: green,
                        ),
                      ),
                    ),
                  ],
                )
              : _familyPlaceholder(),
        ),
      ),
    ),
  );
  Widget _familyPlaceholder() => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CareIllustration(size: 66),
            const SizedBox(width: 8),
            Icon(
              picking
                  ? Icons.hourglass_top_rounded
                  : Icons.add_a_photo_outlined,
              color: green,
            ),
            const SizedBox(width: 8),
            const CareIllustration(helper: true, size: 66),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Family makes every day brighter.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: green,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
