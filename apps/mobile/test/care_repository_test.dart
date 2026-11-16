import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/care/data/care_repository.dart';
import 'package:medication_companion/features/profiles/data/profile_repository.dart';

void main() {
  late AppDatabase db;
  late CareRepository care;
  late ProfileRepository profiles;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    care = CareRepository(db);
    profiles = ProfileRepository(db);
  });
  tearDown(() async => db.close());

  test('new visit seeds editable pre- and post-visit checklists', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final when = DateTime(2027, 1, 15, 9, 30);
    final id = await care.addVisit(
      profileId: profile.id, title: 'ویزیت نمونه', scheduledAt: when,
      doctor: 'دکتر نمونه', purpose: 'بررسی نتیجه آزمایش',
    );
    final visits = await care.visitsFor(profile.id);
    expect(visits.single.id, id);
    expect(visits.single.scheduledAt.toLocal(), when);
    final before = await care.checklistFor(
        profileId: profile.id, visitId: id, phase: 'before');
    final after = await care.checklistFor(
        profileId: profile.id, visitId: id, phase: 'after');
    expect(before, hasLength(5));
    expect(after, hasLength(3));
    expect(before.every((item) => item.enabled && !item.checked), isTrue);
  });

  test('checklist can be checked, disabled, reordered, extended, removed', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final visit = await care.addVisit(
      profileId: profile.id, title: 'ویزیت',
      scheduledAt: DateTime(2027, 2, 20),
    );
    Future<List<VisitChecklistItem>> items() => care.checklistFor(
      profileId: profile.id, visitId: visit, phase: 'before');
    final original = await items();
    await care.toggleChecklistItem(
        profileId: profile.id, itemId: original.first.id, checked: true);
    await care.toggleChecklistItem(
        profileId: profile.id, itemId: original.first.id, enabled: false);
    expect((await items()).first.checked, isFalse);
    expect((await items()).first.enabled, isFalse);
    await expectLater(() => care.toggleChecklistItem(
      profileId: profile.id, itemId: original.first.id, checked: true,
    ), throwsStateError);
    await care.moveChecklistItem(
        profileId: profile.id, itemId: original[1].id, direction: -1);
    expect((await items()).first.id, original[1].id);
    await care.addChecklistItem(
        profileId: profile.id, visitId: visit, phase: 'before', title: 'یادداشت');
    expect(await items(), hasLength(6));
    await care.removeChecklistItem(profile.id, original.first.id);
    expect(await items(), hasLength(5));
  });

  test('task status and edits generate append-only events', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final visitId = await care.addVisit(
      profileId: profile.id, title: 'ویزیت',
      scheduledAt: DateTime(2027, 3, 21),
    );
    final id = await care.addTask(
      profileId: profile.id, title: 'آزمایش نسخه‌شده',
      dueAt: DateTime(2027, 3, 20), visitId: visitId,
    );
    await care.setTaskStatus(
        profileId: profile.id, taskId: id, status: 'deferred');
    await care.updateTask(
      profileId: profile.id, taskId: id, title: 'آزمایش - موعد تازه',
      dueAt: DateTime(2027, 3, 23), visitId: visitId,
    );
    await care.setTaskStatus(
        profileId: profile.id, taskId: id, status: 'done');
    expect((await care.tasksFor(profile.id)).single.status, 'done');
    expect((await care.tasksFor(profile.id)).single.title, 'آزمایش - موعد تازه');
    expect((await care.eventsFor(profile.id, id)).map((e) => e.action),
        ['created', 'deferred', 'edited', 'done']);
    await care.archiveTask(profile.id, id);
    expect(await care.tasksFor(profile.id), isEmpty);
    expect((await care.eventsFor(profile.id, id)).last.action, 'archived');
  });

  test('questions can be standalone or linked and marked answered', () async {
    final profile = await profiles.createGuestProfile(forSelf: true);
    final visitId = await care.addVisit(
      profileId: profile.id, title: 'ویزیت',
      scheduledAt: DateTime(2027, 3, 21),
    );
    final standalone = await care.addQuestion(
        profileId: profile.id, question: 'سؤال عمومی');
    final linked = await care.addQuestion(
        profileId: profile.id, question: 'آیا نتیجه آمده؟', visitId: visitId);
    await care.setQuestionAnswered(
        profileId: profile.id, questionId: linked, answered: true);
    expect((await care.questionsFor(profile.id, visitId: visitId)).single.answered,
        isTrue);
    expect(await care.questionsFor(profile.id), hasLength(2));
    await care.archiveQuestion(profile.id, standalone);
    expect((await care.questionsFor(profile.id)).single.id, linked);
  });

  test('all care writes and reads deny other profiles, including linked IDs', () async {
    final first = await profiles.createGuestProfile(forSelf: true);
    final second = await profiles.createGuestProfile(
        forSelf: false, displayName: 'پروفایل دوم');
    final visitId = await care.addVisit(
      profileId: first.id, title: 'ویزیت خصوصی',
      scheduledAt: DateTime(2027, 3, 21),
    );
    final taskId = await care.addTask(
        profileId: first.id, title: 'کار خصوصی', visitId: visitId);
    final questionId = await care.addQuestion(
        profileId: first.id, question: 'سؤال خصوصی', visitId: visitId);
    final item = (await care.checklistFor(
        profileId: first.id, visitId: visitId, phase: 'before')).first;
    expect(await care.visitsFor(second.id), isEmpty);
    expect(await care.tasksFor(second.id), isEmpty);
    expect(await care.questionsFor(second.id), isEmpty);
    await expectLater(() => care.addTask(
      profileId: second.id, title: 'اشتباه', visitId: visitId,
    ), throwsStateError);
    await expectLater(() => care.addQuestion(
      profileId: second.id, question: 'اشتباه', visitId: visitId,
    ), throwsStateError);
    await expectLater(() => care.setVisitStatus(
      profileId: second.id, visitId: visitId, status: 'cancelled',
    ), throwsStateError);
    await expectLater(() => care.setTaskStatus(
      profileId: second.id, taskId: taskId, status: 'done',
    ), throwsStateError);
    await expectLater(() => care.setQuestionAnswered(
      profileId: second.id, questionId: questionId, answered: true,
    ), throwsStateError);
    await expectLater(() => care.toggleChecklistItem(
      profileId: second.id, itemId: item.id, checked: true,
    ), throwsStateError);
    expect((await care.tasksFor(first.id)).single.status, 'open');
    expect((await care.questionsFor(first.id)).single.answered, isFalse);
  });

  test('v3 to v4 keeps an existing local profile without resetting data', () async {
    await db.close();
    final executor = NativeDatabase.memory(setup: (raw) {
      raw.execute('CREATE TABLE profiles ('
          'id TEXT NOT NULL PRIMARY KEY, display_name TEXT NOT NULL, '
          'kind TEXT NOT NULL, created_at INTEGER NOT NULL)');
      raw.execute("INSERT INTO profiles VALUES ('old', 'کاربر قدیمی', 'self', 1)");
      raw.execute('PRAGMA user_version = 3');
    });
    db = AppDatabase.forTesting(executor);
    expect((await db.select(db.profiles).get()).single.id, 'old');
    final migrated = CareRepository(db);
    final id = await migrated.addVisit(
      profileId: 'old', title: 'ویزیت پس از ارتقا',
      scheduledAt: DateTime(2027, 4, 1),
    );
    expect((await migrated.visitsFor('old')).single.id, id);
    expect((await db.customSelect('PRAGMA user_version').getSingle())
        .read<int>('user_version'), 4);
  });
}
