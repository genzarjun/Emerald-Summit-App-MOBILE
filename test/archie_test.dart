import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/backend.dart';
import 'package:emerald_summit/backend/sample/sample_archie_repository.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/screens/archie_screen.dart';

/// Hands the test a controller per question so it can drive the stream.
/// History (save/list/load/delete) is the in-memory sample implementation.
class _FakeArchie extends SampleArchieRepository {
  final asked = <List<ArchieTurn>>[];
  late StreamController<ArchieEvent> current;

  @override
  Stream<ArchieEvent> ask(List<ArchieTurn> transcript) {
    asked.add(transcript);
    current = StreamController<ArchieEvent>();
    return current.stream;
  }
}

void main() {
  late _FakeArchie fake;

  setUp(() async {
    await getIt.reset();
    await configureBackend(); // sample backend (no credentials in tests)
    await appState.loadCatalog();
    fake = _FakeArchie();
    getIt
      ..unregister<ArchieRepository>()
      ..registerSingleton<ArchieRepository>(fake);
  });

  /// Runs [frames] frames of [step] each. A single `pump(duration)` is one
  /// frame, and the typewriter's ticker reveals text frame by frame.
  Future<void> frames(
    WidgetTester tester, {
    int frames = 40,
    Duration step = const Duration(milliseconds: 50),
  }) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(step);
    }
  }

  Future<void> pumpArchie(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ArchieScreen()));
    await tester.pump(const Duration(seconds: 2)); // welcome entrance
  }

  testWidgets('welcome shows the greeting and three starters', (tester) async {
    await pumpArchie(tester);
    expect(find.textContaining("what's the move?"), findsOneWidget);
    expect(
      find.text('What is Emerald Summit, and what can I do there?'),
      findsOneWidget,
    );
    expect(find.text('Which sessions still have open seats?'), findsOneWidget);
    expect(find.textContaining('which session should I try?'), findsOneWidget);
    expect(find.textContaining('park'), findsNothing);
  });

  testWidgets('header: History sits flush right until New chat appears', (
    tester,
  ) async {
    await pumpArchie(tester);
    final screenWidth = tester.getSize(find.byType(ArchieScreen)).width;
    expect(find.byTooltip('New chat'), findsNothing);
    // Flush with the header's right padding — not a button-width (48px) in.
    expect(
      tester.getRect(find.byTooltip('Your chats')).right,
      greaterThan(screenWidth - 24),
    );

    await tester.tap(find.text('Which sessions still have open seats?'));
    await frames(tester, frames: 10);
    expect(find.byTooltip('New chat'), findsOneWidget);
    expect(
      tester.getRect(find.byTooltip('Your chats')).right,
      lessThan(screenWidth - 40),
    );
    fake.current.close();
    await frames(tester);
  });

  testWidgets('tapping a starter streams steps, types out the answer, '
      'then shows sources', (tester) async {
    await pumpArchie(tester);
    await tester.tap(find.text('Which sessions still have open seats?'));
    await tester.pump();

    expect(
      fake.asked.single.single.text,
      'Which sessions still have open seats?',
    );
    expect(find.text('Thinking…'), findsOneWidget);

    fake.current.add(const ArchieStatus('Searching the web for “seats”'));
    await tester.pump();
    expect(find.text('Searching the web for “seats”…'), findsOneWidget);

    const answer = 'Plenty of room in **Robotics 101** and the CAD lab.';
    fake.current.add(const ArchieDelta(answer));
    await frames(tester, frames: 4, step: const Duration(milliseconds: 40));

    // Mid-reveal: some, but not all, of the answer is on screen.
    final partial = _visibleText(tester);
    expect(partial, isNotEmpty);
    expect(partial.contains('CAD lab.'), isFalse);

    fake.current
      ..add(
        const ArchieSources([
          ArchieSource(title: 'Emerald Summit', url: 'https://example.com'),
        ]),
      )
      ..close();
    await frames(tester);

    expect(_visibleText(tester), contains('CAD lab.'));
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Emerald Summit'), findsOneWidget);
    expect(find.text('Searched the web'), findsOneWidget);
  });

  testWidgets('haptics tick while the answer types out', (tester) async {
    final haptics = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String?);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpArchie(tester);
    await tester.tap(find.text('Which sessions still have open seats?'));
    await tester.pump();
    haptics.clear(); // ignore the send tap

    fake.current
      ..add(ArchieDelta('Lots of seats left in several sessions. ' * 6))
      ..close();
    await frames(tester, frames: 60);

    expect(haptics.first, 'HapticFeedbackType.lightImpact'); // answer begins
    expect(haptics.last, 'HapticFeedbackType.lightImpact'); // answer done
    expect(
      haptics.where((h) => h == 'HapticFeedbackType.selectionClick'),
      isNotEmpty,
    ); // ticks while typing
  });

  testWidgets('follow-up questions resend the transcript', (tester) async {
    await pumpArchie(tester);
    await tester.tap(find.text('Which sessions still have open seats?'));
    await tester.pump();
    fake.current
      ..add(const ArchieDelta('Lots.'))
      ..close();
    await frames(tester);

    await tester.enterText(find.byType(TextField), 'Which is first?');
    await tester.pump(); // enable Send for the new text
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    final turns = fake.asked.last;
    expect(turns.map((t) => (t.fromUser, t.text)).toList(), [
      (true, 'Which sessions still have open seats?'),
      (false, 'Lots.'),
      (true, 'Which is first?'),
    ]);
    fake.current.close();
    await frames(tester);
  });

  testWidgets('Stop keeps what was shown and re-enables sending', (
    tester,
  ) async {
    await pumpArchie(tester);
    await tester.tap(find.text('Which sessions still have open seats?'));
    await tester.pump();
    fake.current.add(ArchieDelta('word ' * 200));
    await frames(tester, frames: 4);

    await tester.tap(find.byTooltip('Stop'));
    await frames(tester, frames: 10);

    expect(find.text('Stopped'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(fake.current.hasListener, isFalse); // request torn down
  });

  group('saved history', () {
    testWidgets('a finished answer is saved and can be reopened', (
      tester,
    ) async {
      await pumpArchie(tester);
      await tester.tap(find.text('Which sessions still have open seats?'));
      await tester.pump();
      fake.current
        ..add(const ArchieDelta('Robotics 101 has room.'))
        ..close();
      await frames(tester);

      final chats = await fake.listChats();
      expect(chats.single.title, 'Which sessions still have open seats?');

      // New chat, then reopen it from "Your chats".
      await tester.tap(find.byTooltip('New chat'));
      await frames(tester, frames: 10);
      expect(find.textContaining("what's the move?"), findsOneWidget);

      await tester.tap(find.byTooltip('Your chats'));
      await frames(tester, frames: 10);
      await tester.tap(
        find.widgetWithText(ListTile, 'Which sessions still have open seats?'),
      );
      await frames(tester, frames: 10);
      expect(_visibleText(tester), contains('Robotics 101 has room.'));
    });

    testWidgets('deleting a chat removes it', (tester) async {
      await fake.saveExchange(
        question: 'Old question',
        answer: const ArchieSavedMessage(fromUser: false, text: 'Old answer'),
      );
      await pumpArchie(tester);
      await tester.tap(find.byTooltip('Your chats'));
      await frames(tester, frames: 10);
      await tester.tap(find.byTooltip('Delete chat'));
      await frames(tester, frames: 10);
      await tester.tap(find.text('Delete'));
      await frames(tester, frames: 10);

      expect(await fake.listChats(), isEmpty);
      expect(find.text('Old question'), findsNothing);
    });

    testWidgets('a chat at the question limit asks for a new chat', (
      tester,
    ) async {
      String? id;
      for (var i = 0; i < kArchieMaxQuestionsPerChat; i++) {
        id = await fake.saveExchange(
          chatId: id,
          question: 'Question $i',
          answer: ArchieSavedMessage(fromUser: false, text: 'Answer $i'),
        );
      }
      await pumpArchie(tester);
      await tester.tap(find.byTooltip('Your chats'));
      await frames(tester, frames: 10);
      await tester.tap(find.text('Question 0'));
      await frames(tester, frames: 10);

      expect(
        find.text('This conversation is too long. Please start a new chat.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'New chat'));
      await frames(tester, frames: 10);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('history limits (sample backend mirrors the database)', () {
    test('keeps only the most recent chats', () async {
      final repo = SampleArchieRepository();
      for (var i = 0; i <= kArchieMaxSavedChats; i++) {
        await repo.saveExchange(
          question: 'Chat $i',
          answer: const ArchieSavedMessage(fromUser: false, text: 'ok'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final chats = await repo.listChats();
      expect(chats, hasLength(kArchieMaxSavedChats));
      expect(chats.map((c) => c.title), isNot(contains('Chat 0')));
    });

    test('rejects questions past the per-chat limit', () async {
      final repo = SampleArchieRepository();
      String? id;
      for (var i = 0; i < kArchieMaxQuestionsPerChat; i++) {
        id = await repo.saveExchange(
          chatId: id,
          question: 'Q$i',
          answer: const ArchieSavedMessage(fromUser: false, text: 'A'),
        );
      }
      expect(
        () => repo.saveExchange(
          chatId: id,
          question: 'one too many',
          answer: const ArchieSavedMessage(fromUser: false, text: 'A'),
        ),
        throwsA(isA<ArchieChatFullException>()),
      );
    });
  });
}

/// All text rendered in the conversation list. Markdown renders as RichText
/// while typing and as (selectable) EditableText once settled.
String _visibleText(WidgetTester tester) {
  final list = find.byType(ListView);
  return [
    for (final r in tester.widgetList<RichText>(
      find.descendant(of: list, matching: find.byType(RichText)),
    ))
      r.text.toPlainText(),
    for (final e in tester.widgetList<EditableText>(
      find.descendant(of: list, matching: find.byType(EditableText)),
    ))
      e.controller.text,
  ].join(' ');
}
