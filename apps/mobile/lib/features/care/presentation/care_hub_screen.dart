import 'package:material_ui/material_ui.dart';

import '../../../core/storage/app_database.dart';
import '../data/care_repository.dart';

String _dateLabel(DateTime? date) {
  if (date == null) return 'بدون موعد';
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _visitStatus(String status) => switch (status) {
      'completed' => 'انجام‌شده',
      'cancelled' => 'لغوشده',
      _ => 'برنامه‌ریزی‌شده',
    };

String _taskStatus(String status) => switch (status) {
      'done' => 'انجام‌شده',
      'deferred' => 'به تعویق افتاده',
      _ => 'باز',
    };

class CareHubScreen extends StatefulWidget {
  const CareHubScreen({super.key, required this.profile, required this.repository});

  final Profile profile;
  final CareRepository repository;

  @override
  State<CareHubScreen> createState() => _CareHubScreenState();
}

class _CareHubScreenState extends State<CareHubScreen> {
  int _tab = 0;
  bool _loading = true;
  List<CareTask> _tasks = [];
  List<CareVisit> _visits = [];
  List<VisitQuestion> _questions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final profileId = widget.profile.id;
      final tasks = await widget.repository.tasksFor(profileId);
      final visits = await widget.repository.visitsFor(profileId);
      final questions = await widget.repository.questionsFor(profileId);
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _visits = visits;
        _questions = questions;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تغییرات ذخیره شد.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ثبت نشد: $e')),
        );
      }
    }
  }

  Future<_CareDraft?> _editor(String kind, {
    String? title,
    DateTime? when,
    String? doctor,
    String? location,
    String? purpose,
    String? visitId,
  }) => showDialog<_CareDraft>(
        context: context,
        builder: (_) => _CareEditor(
          kind: kind,
          visits: _visits,
          initial: _CareDraft(
            title: title ?? '', when: when, doctor: doctor,
            location: location, purpose: purpose, visitId: visitId,
          ),
        ),
      );

  Future<void> _add() async {
    const kinds = ['task', 'visit', 'question'];
    final kind = kinds[_tab];
    final draft = await _editor(kind);
    if (draft == null) return;
    await _perform(() async {
      switch (kind) {
        case 'task':
          await widget.repository.addTask(
            profileId: widget.profile.id, title: draft.title,
            dueAt: draft.when, visitId: draft.visitId,
          );
        case 'visit':
          await widget.repository.addVisit(
            profileId: widget.profile.id, title: draft.title,
            scheduledAt: draft.when!, doctor: draft.doctor,
            location: draft.location, purpose: draft.purpose,
          );
        case 'question':
          await widget.repository.addQuestion(
            profileId: widget.profile.id, question: draft.title,
            visitId: draft.visitId,
          );
      }
    });
  }

  Future<void> _editTask(CareTask task) async {
    final draft = await _editor('task',
      title: task.title, when: task.dueAt, visitId: task.visitId,
    );
    if (draft == null) return;
    await _perform(() => widget.repository.updateTask(
      profileId: widget.profile.id, taskId: task.id,
      title: draft.title, dueAt: draft.when, visitId: draft.visitId,
    ));
  }

  Future<void> _editVisit(CareVisit visit) async {
    final draft = await _editor('visit',
      title: visit.title, when: visit.scheduledAt, doctor: visit.doctor,
      location: visit.location, purpose: visit.purpose,
    );
    if (draft == null) return;
    await _perform(() => widget.repository.updateVisit(
      profileId: widget.profile.id, visitId: visit.id,
      title: draft.title, scheduledAt: draft.when!,
      doctor: draft.doctor, location: draft.location,
      purpose: draft.purpose,
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('پیگیری‌های ${widget.profile.displayName}')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('خطا: $_error'))
                : Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('این فهرست برای ثبت برنامه‌های شخصی است؛ '
                            'تغییری در نسخه یا مصرف دارو ایجاد نمی‌کند.'),
                      ),
                      Expanded(child: IndexedStack(index: _tab, children: [
                        _taskList(), _visitList(), _questionList(),
                      ])),
                    ],
                  ),
        floatingActionButton: _loading || _error != null
            ? null
            : FloatingActionButton.extended(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(['کار جدید', 'ویزیت جدید', 'سؤال جدید'][_tab]),
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.task_alt), label: 'کارها'),
            NavigationDestination(icon: Icon(Icons.event), label: 'ویزیت‌ها'),
            NavigationDestination(icon: Icon(Icons.question_answer_outlined), label: 'سؤال‌ها'),
          ],
        ),
      );

  Widget _taskList() {
    if (_tasks.isEmpty) return const Center(child: Text('هنوز کاری ثبت نشده است.'));
    final tasks = [..._tasks]..sort((a, b) {
      final aDone = a.status == 'done' ? 1 : 0;
      final bDone = b.status == 'done' ? 1 : 0;
      if (aDone != bDone) return aDone.compareTo(bDone);
      if (a.dueAt == null && b.dueAt != null) return 1;
      if (b.dueAt == null && a.dueAt != null) return -1;
      return a.dueAt?.compareTo(b.dueAt!) ?? 0;
    });
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
      itemCount: tasks.length,
      itemBuilder: (context, i) {
        final task = tasks[i];
        final visit = _visits.where((v) => v.id == task.visitId).firstOrNull;
        return Card(child: ListTile(
          leading: Icon(task.status == 'done'
              ? Icons.check_circle : Icons.radio_button_unchecked,
            color: task.status == 'done' ? Colors.green : null),
          title: Text(task.title),
          subtitle: Text('${_dateLabel(task.dueAt)} · ${_taskStatus(task.status)}'
              '${visit == null ? '' : ' · ${visit.title}'}'),
          onTap: () => _perform(() => widget.repository.setTaskStatus(
            profileId: widget.profile.id, taskId: task.id,
            status: task.status == 'done' ? 'open' : 'done',
          )),
          trailing: PopupMenuButton<String>(
            tooltip: 'گزینه‌های کار',
            onSelected: (choice) {
              if (choice == 'edit') { _editTask(task); return; }
              if (choice == 'archive') {
                _perform(() => widget.repository.archiveTask(widget.profile.id, task.id));
                return;
              }
              _perform(() => widget.repository.setTaskStatus(
                profileId: widget.profile.id, taskId: task.id, status: choice,
              ));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'done', child: Text('انجام شد')),
              PopupMenuItem(value: 'deferred', child: Text('به تعویق افتاد')),
              PopupMenuItem(value: 'open', child: Text('بازگشت به باز')),
              PopupMenuItem(value: 'edit', child: Text('ویرایش عنوان و موعد')),
              PopupMenuItem(value: 'archive', child: Text('بایگانی')),
            ],
          ),
        ));
      },
    );
  }

  Widget _visitList() {
    if (_visits.isEmpty) return const Center(child: Text('هنوز ویزیتی ثبت نشده است.'));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
      itemCount: _visits.length,
      itemBuilder: (context, i) {
        final visit = _visits[i];
        return Card(child: ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: Text(visit.title),
          subtitle: Text('${_dateLabel(visit.scheduledAt)} · ${_visitStatus(visit.status)}'
              '${visit.doctor == null ? '' : ' · ${visit.doctor}'}'),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => VisitDetailScreen(
                repository: widget.repository, profile: widget.profile,
                visit: visit,
              ),
            ));
            await _reload();
          },
          trailing: PopupMenuButton<String>(
            tooltip: 'گزینه‌های ویزیت',
            onSelected: (choice) {
              if (choice == 'edit') { _editVisit(visit); return; }
              _perform(() => widget.repository.setVisitStatus(
                profileId: widget.profile.id, visitId: visit.id, status: choice,
              ));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'scheduled', child: Text('برنامه‌ریزی‌شده')),
              PopupMenuItem(value: 'completed', child: Text('انجام‌شده')),
              PopupMenuItem(value: 'cancelled', child: Text('لغوشده')),
              PopupMenuItem(value: 'edit', child: Text('ویرایش ویزیت')),
            ],
          ),
        ));
      },
    );
  }

  Widget _questionList() {
    if (_questions.isEmpty) return const Center(child: Text('هنوز سؤالی ثبت نشده است.'));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
      itemCount: _questions.length,
      itemBuilder: (context, i) {
        final question = _questions[i];
        final visit = _visits.where((v) => v.id == question.visitId).firstOrNull;
        return Card(child: CheckboxListTile(
          title: Text(question.question),
          subtitle: Text(visit == null ? 'بدون ویزیت مشخص' : visit.title),
          value: question.answered,
          onChanged: (value) => _perform(() => widget.repository.setQuestionAnswered(
            profileId: widget.profile.id, questionId: question.id,
            answered: value ?? false,
          )),
          secondary: IconButton(
            tooltip: 'بایگانی سؤال',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => _perform(() => widget.repository.archiveQuestion(
              widget.profile.id, question.id,
            )),
          ),
        ));
      },
    );
  }
}

class VisitDetailScreen extends StatefulWidget {
  const VisitDetailScreen({super.key, required this.repository,
      required this.profile, required this.visit});
  final CareRepository repository;
  final Profile profile;
  final CareVisit visit;

  @override
  State<VisitDetailScreen> createState() => _VisitDetailScreenState();
}

class _VisitDetailScreenState extends State<VisitDetailScreen> {
  List<VisitChecklistItem> _before = [];
  List<VisitChecklistItem> _after = [];
  List<VisitQuestion> _questions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _reload(); }

  Future<void> _reload() async {
    try {
      final id = widget.profile.id;
      final visitId = widget.visit.id;
      final before = await widget.repository.checklistFor(
          profileId: id, visitId: visitId, phase: 'before');
      final after = await widget.repository.checklistFor(
          profileId: id, visitId: visitId, phase: 'after');
      final questions = await widget.repository.questionsFor(id, visitId: visitId);
      if (!mounted) return;
      setState(() { _before = before; _after = after; _questions = questions;
        _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ذخیره شد.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ثبت نشد: $e')));
    }
  }

  Future<String?> _askText(String label) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(controller: controller, autofocus: true,
          maxLength: 160, decoration: const InputDecoration(labelText: 'متن')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('ذخیره')),
        ],
      ),
    );
    controller.dispose();
    return (value?.trim().isEmpty ?? true) ? null : value?.trim();
  }

  Future<void> _addCheck(String phase) async {
    final text = await _askText('افزودن مورد چک‌لیست');
    if (text == null) return;
    await _run(() => widget.repository.addChecklistItem(
      profileId: widget.profile.id, visitId: widget.visit.id,
      phase: phase, title: text,
    ));
  }

  Future<void> _addQuestion() async {
    final text = await _askText('سؤال از پزشک');
    if (text == null) return;
    await _run(() async {
      await widget.repository.addQuestion(
        profileId: widget.profile.id, visitId: widget.visit.id, question: text,
      );
    });
  }

  Widget _checkSection(String phase, String title, List<VisitChecklistItem> items) {
    return Card(child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          IconButton(tooltip: 'افزودن به $title', onPressed: () => _addCheck(phase),
              icon: const Icon(Icons.add_circle_outline)),
        ]),
        if (items.isEmpty) const Text('موردی وجود ندارد.'),
        for (var i = 0; i < items.length; i++)
          Row(children: [
            Checkbox(value: items[i].checked,
              onChanged: !items[i].enabled ? null : (checked) => _run(() =>
                widget.repository.toggleChecklistItem(
                  profileId: widget.profile.id, itemId: items[i].id,
                  checked: checked ?? false,
                ))),
            Expanded(child: Text(items[i].title,
              style: TextStyle(color: items[i].enabled ? null : Colors.grey))),
            PopupMenuButton<String>(
              tooltip: 'تنظیم مورد',
              onSelected: (choice) {
                final item = items[i];
                if (choice == 'toggle') {
                  _run(() => widget.repository.toggleChecklistItem(
                    profileId: widget.profile.id, itemId: item.id,
                    enabled: !item.enabled,
                  ));
                } else if (choice == 'remove') {
                  _run(() => widget.repository.removeChecklistItem(
                      widget.profile.id, item.id));
                } else {
                  _run(() => widget.repository.moveChecklistItem(
                    profileId: widget.profile.id, itemId: item.id,
                    direction: choice == 'up' ? -1 : 1,
                  ));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'toggle',
                    child: Text(items[i].enabled ? 'غیرفعال‌کردن' : 'فعال‌کردن')),
                const PopupMenuItem(value: 'up', child: Text('انتقال به بالا')),
                const PopupMenuItem(value: 'down', child: Text('انتقال به پایین')),
                const PopupMenuItem(value: 'remove', child: Text('حذف از چک‌لیست')),
              ],
            ),
          ]),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.visit.title)),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text('خطا: $_error'))
            : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 28), children: [
                ListTile(title: Text(_dateLabel(widget.visit.scheduledAt)),
                  subtitle: Text('${widget.visit.doctor ?? 'پزشک نامشخص'}'
                      '${widget.visit.location == null ? '' : ' · ${widget.visit.location}'}'
                      '${widget.visit.purpose == null ? '' : '\n${widget.visit.purpose}'}')),
                _checkSection('before', 'پیش از ویزیت', _before),
                _checkSection('after', 'پس از ویزیت', _after),
                Card(child: Column(children: [
                  ListTile(title: const Text('سؤال‌های این ویزیت'),
                    trailing: IconButton(
                      tooltip: 'افزودن سؤال', icon: const Icon(Icons.add),
                      onPressed: _addQuestion,
                    )),
                  if (_questions.isEmpty) const Padding(
                    padding: EdgeInsets.all(12), child: Text('هنوز سؤالی ندارید.')),
                  for (final question in _questions)
                    CheckboxListTile(
                      title: Text(question.question), value: question.answered,
                      onChanged: (v) => _run(() => widget.repository.setQuestionAnswered(
                        profileId: widget.profile.id, questionId: question.id,
                        answered: v ?? false,
                      )),
                    ),
                ])),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('این چک‌لیست صرفاً کمکی است. تغییر دارو یا تصمیم پزشکی را'
                      ' تنها طبق نظر پزشک ثبت کنید.'),
                ),
              ]),
  );
}

class _CareDraft {
  const _CareDraft({required this.title, this.when, this.doctor,
      this.location, this.purpose, this.visitId});
  final String title;
  final DateTime? when;
  final String? doctor;
  final String? location;
  final String? purpose;
  final String? visitId;
}

class _CareEditor extends StatefulWidget {
  const _CareEditor({required this.kind, required this.visits,
      required this.initial});
  final String kind;
  final List<CareVisit> visits;
  final _CareDraft initial;
  @override
  State<_CareEditor> createState() => _CareEditorState();
}

class _CareEditorState extends State<_CareEditor> {
  late final TextEditingController _title;
  late final TextEditingController _doctor;
  late final TextEditingController _location;
  late final TextEditingController _purpose;
  DateTime? _when;
  String? _visitId;

  @override
  void initState() {
    super.initState();
    final draft = widget.initial;
    _title = TextEditingController(text: draft.title);
    _doctor = TextEditingController(text: draft.doctor);
    _location = TextEditingController(text: draft.location);
    _purpose = TextEditingController(text: draft.purpose);
    _when = draft.when ?? (widget.kind == 'visit'
        ? DateTime.now().add(const Duration(days: 1)) : null);
    _visitId = draft.visitId;
  }

  @override
  void dispose() {
    _title.dispose(); _doctor.dispose(); _location.dispose(); _purpose.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final original = _when ?? DateTime.now();
    final day = await showDatePicker(
      context: context, initialDate: original,
      firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context,
        initialTime: TimeOfDay.fromDateTime(original));
    if (time == null || !mounted) return;
    setState(() => _when = DateTime(day.year, day.month, day.day,
        time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final visit = widget.kind == 'visit';
    final question = widget.kind == 'question';
    return AlertDialog(
      title: Text(question ? 'سؤال جدید' : visit ? 'ثبت ویزیت' : 'ثبت کار'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _title, autofocus: true, maxLength: question ? 500 : 160,
            maxLines: question ? 3 : 1,
            decoration: InputDecoration(labelText: question ? 'متن سؤال' : 'عنوان *')),
          if (!question) ...[
            ListTile(
              title: Text(_dateLabel(_when)),
              subtitle: Text(visit ? 'زمان ویزیت * (میلادی)' : 'موعد کار (اختیاری، میلادی)'),
              leading: const Icon(Icons.calendar_month_outlined),
              onTap: _pickDate,
              trailing: !visit && _when != null
                  ? IconButton(tooltip: 'حذف موعد', icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _when = null))
                  : null,
            ),
          ],
          if (visit) ...[
            TextField(controller: _doctor, maxLength: 120,
                decoration: const InputDecoration(labelText: 'پزشک (اختیاری)')),
            TextField(controller: _location, maxLength: 160,
                decoration: const InputDecoration(labelText: 'مرکز مراجعه (اختیاری)')),
            TextField(controller: _purpose, maxLength: 500, maxLines: 2,
                decoration: const InputDecoration(labelText: 'هدف مراجعه (اختیاری)')),
          ] else if (widget.visits.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _visitId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'اتصال به ویزیت (اختیاری)'),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('بدون ویزیت')),
                for (final item in widget.visits)
                  DropdownMenuItem<String>(value: item.id, child: Text(item.title)),
              ],
              onChanged: (id) => setState(() => _visitId = id),
            ),
          ],
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('انصراف')),
        FilledButton(onPressed: () {
          if (_title.text.trim().isEmpty || (visit && _when == null)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('عنوان و زمان ویزیت را وارد کنید.')));
            return;
          }
          Navigator.pop(context, _CareDraft(
            title: _title.text.trim(), when: _when,
            doctor: _doctor.text, location: _location.text,
            purpose: _purpose.text, visitId: _visitId,
          ));
        }, child: const Text('ذخیره')),
      ],
    );
  }
}
