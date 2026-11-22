import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/profiles/presentation/guest_welcome_screen.dart';

void main() {
  testWidgets('welcome requires a name only for named entry', (tester) async {
    var asGuest = 0;
    var forLovedOne = 0;
    final named = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: GuestWelcomeScreen(
          onSelf: () => asGuest++,
          onLovedOne: () => forLovedOne++,
          onSelfNamed: named.add,
        ),
      ),
    ));

    expect(find.text('همراه دارو'), findsOneWidget);
    expect(find.text('دوست داری چطور صدات کنیم؟'), findsOneWidget);
    await tester.ensureVisible(find.text('شروع برای خودم'));
    await tester.tap(find.text('شروع برای خودم'));
    await tester.pump();
    expect(named, isEmpty);
    expect(find.text('برای شروع، نامت رو بنویس.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('welcome-name-input')),
        '  امیر  ');
    await tester.testTextInput.hide();
    await tester.ensureVisible(find.text('شروع برای خودم'));
    await tester.tap(find.text('شروع برای خودم'));
    await tester.pump();
    expect(named, ['امیر']);
    expect(asGuest, 0);
    expect(forLovedOne, 0);

    await tester.ensureVisible(find.text('برای یکی از عزیزانم'));
    await tester.tap(find.text('برای یکی از عزیزانم'));
    await tester.pump();
    expect(forLovedOne, 1);

    await tester.ensureVisible(find.text('ورود به عنوان مهمان'));
    await tester.tap(find.text('ورود به عنوان مهمان'));
    await tester.pump();
    expect(asGuest, 1);
    expect(tester.takeException(), isNull);
  });
}
