import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/core/storage/app_database.dart';
import 'package:medication_companion/features/medications/data/notification_inbox_repository.dart';

void main() {
  late AppDatabase db;
  late NotificationInboxRepository repo;
  const alert = InboxNotice(condition: 'stock:med:low',
    medicationId: 'med', title: 'کمبود', message: 'موجودی کم است',
    urgent: false);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = NotificationInboxRepository(db);
  });
  tearDown(() async => db.close());

  test('opening and reconciling never implicitly marks a message read', () async {
    final first = (await repo.reconcile('p1', [alert])).single;
    expect(first.read, isFalse);
    final again = (await repo.reconcile('p1', [alert])).single;
    expect(again.id, first.id);
    expect(again.read, isFalse);
    await repo.markRead('p1', first.id);
    final read = (await repo.reconcile('p1', [alert])).single;
    expect(read.read, isTrue);
    expect(read.active, isTrue);
    expect((await NotificationInboxRepository(db).load('p1')).single.read, isTrue);
  });

  test('resolution disables old message; recurrence creates unread episode', () async {
    final first = (await repo.reconcile('p1', [alert])).single;
    await repo.markRead('p1', first.id);
    final ended = (await repo.reconcile('p1', [])).single;
    expect(ended.active, isFalse);
    expect(ended.read, isTrue);
    final recurrent = await repo.reconcile('p1', [alert]);
    expect(recurrent.length, 2);
    expect(recurrent.first.active, isFalse);
    expect(recurrent.last.id, isNot(first.id));
    expect(recurrent.last.active, isTrue);
    expect(recurrent.last.read, isFalse);
  });

  test('read state never crosses profile boundary', () async {
    final first = (await repo.reconcile('p1', [alert])).single;
    await repo.reconcile('p2', [alert]);
    await repo.markRead('p1', first.id);
    expect((await repo.load('p2')).single.read, isFalse);
  });
}
