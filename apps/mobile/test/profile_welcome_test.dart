import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_companion/features/profiles/presentation/guest_welcome_screen.dart';

void main() {
  testWidgets('guest entry choices invoke the expected action', (tester) async {
    var forSelf = 0;
    var forLovedOne = 0;
    await tester.pumpWidget(MaterialApp(
      home: GuestWelcomeScreen(
        onSelf: () => forSelf++,
        onLovedOne: () => forLovedOne++,
      ),
    ));

    expect(find.text('همراه دارو'), findsOneWidget);
    await tester.ensureVisible(find.text('شروع'));
    await tester.tap(find.text('شروع'));
    await tester.pump();
    expect(forSelf, 1);
    expect(forLovedOne, 0);

    await tester.ensureVisible(find.text('برای یکی از عزیزانم'));
    await tester.tap(find.text('برای یکی از عزیزانم'));
    await tester.pump();
    expect(forLovedOne, 1);
  });
}
