import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/widgets/type_to_confirm_dialog.dart';

/// Pumps a button that opens the dialog for [name]; its answer lands in
/// [onResult].
Future<void> pumpOpener(WidgetTester tester, String name,
    void Function(bool) onResult) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => onResult(await confirmByTypingName(
          context,
          title: 'Delete?',
          message: 'Gone for good.',
          name: name,
        )),
        child: const Text('open'),
      ),
    ),
  ));
}

Future<void> openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

FilledButton deleteButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'));

void main() {
  testWidgets('Delete stays disabled until the exact name is typed',
      (tester) async {
    await pumpOpener(tester, 'Robotics 101', (_) {});
    await openDialog(tester);
    expect(deleteButton(tester).onPressed, isNull);

    for (final wrong in ['robotics 101', 'Robotics 10', 'Robotics 1011']) {
      await tester.enterText(find.byType(TextField), wrong);
      await tester.pump();
      expect(deleteButton(tester).onPressed, isNull, reason: wrong);
    }

    await tester.enterText(find.byType(TextField), 'Robotics 101');
    await tester.pump();
    expect(deleteButton(tester).onPressed, isNotNull);
  });

  testWidgets('Cancel declines; typing the name and pressing Delete confirms',
      (tester) async {
    bool? result;
    await pumpOpener(tester, 'CivicVerse', (r) => result = r);

    await openDialog(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'CivicVerse');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
