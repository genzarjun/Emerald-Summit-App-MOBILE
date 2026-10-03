import 'dart:async';

import '../../data/sample_data.dart';
import '../backend.dart';

/// Offline stand-in for Archie (sample/demo mode). There's no model behind it:
/// it streams a canned, catalog-aware reply word-by-word so the chat UI —
/// progress steps, typing reveal, sources — can be exercised without a backend.
class SampleArchieRepository implements ArchieRepository {
  // In-memory chat history with the same limits as the database.
  final _chats = <String, ({String title, DateTime updatedAt})>{};
  final _messages = <String, List<ArchieSavedMessage>>{};
  int _nextId = 0;

  @override
  Future<List<ArchieChatSummary>> listChats() async {
    final list = [
      for (final e in _chats.entries)
        ArchieChatSummary(
            id: e.key, title: e.value.title, updatedAt: e.value.updatedAt),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<List<ArchieSavedMessage>> loadChat(String chatId) async =>
      List.of(_messages[chatId] ?? const []);

  @override
  Future<String> saveExchange({
    String? chatId,
    required String question,
    required ArchieSavedMessage answer,
  }) async {
    final id = chatId ?? 'chat-${_nextId++}';
    final messages = _messages.putIfAbsent(id, () => []);
    if (messages.where((m) => m.fromUser).length >=
        kArchieMaxQuestionsPerChat) {
      throw const ArchieChatFullException();
    }
    messages
      ..add(ArchieSavedMessage(fromUser: true, text: question))
      ..add(answer);
    _chats[id] = (
      title: _chats[id]?.title ?? archieChatTitle(question),
      updatedAt: DateTime.now(),
    );
    // Keep only the most recent chats, like the database trigger.
    final stale = (await listChats()).skip(kArchieMaxSavedChats);
    for (final c in stale) {
      await deleteChat(c.id);
    }
    return id;
  }

  @override
  Future<void> deleteChat(String chatId) async {
    _chats.remove(chatId);
    _messages.remove(chatId);
  }

  @override
  Future<List<ArchieExchange>> recentExchanges({int limit = 100}) async {
    final out = <ArchieExchange>[];
    for (final c in await listChats()) {
      final m = _messages[c.id]!;
      for (var i = 0; i + 1 < m.length; i += 2) {
        out.add(ArchieExchange(
          question: m[i].text,
          answer: m[i + 1].text,
          sourceCount: m[i + 1].sources.length,
          askedAt: c.updatedAt,
        ));
      }
    }
    return out.take(limit).toList();
  }

  @override
  Stream<ArchieEvent> ask(List<ArchieTurn> transcript) async* {
    final question = transcript.last.text.toLowerCase();

    yield const ArchieStatus('Looking through the summit schedule');
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final answer = _answerFor(question);
    for (final word in RegExp(r'\S+\s*').allMatches(answer)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      yield ArchieDelta(word.group(0)!);
    }
    yield const ArchieSources([
      ArchieSource(
        title: 'Emerald Summit',
        url: 'https://sites.google.com/view/ehs-academic-foundation/programs/emerald-summit',
      ),
    ]);
  }

  static String _answerFor(String q) {
    final disciplines = SampleData.disciplines;
    final match = disciplines.where((d) => q.contains(d.name.toLowerCase()));
    if (match.isNotEmpty) {
      final d = match.first;
      final sessions = [
        for (final s in d.sessions) '- **${s.title}** · ${s.room}',
      ].join('\n');
      return '**${d.name}** is all about ${d.tagline.toLowerCase()}. '
          'Here\'s what\'s on the demo schedule:\n\n$sessions\n\n'
          '_(Demo mode — connect the backend for live answers.)_';
    }
    final names = disciplines.map((d) => '**${d.name}**').join(', ');
    return 'Hi, I\'m Archie! 🐉 I\'m running in **demo mode** right now, so I '
        'can\'t search the web or read the live schedule. Emerald Summit \'27 '
        'happens at Emerald High in Dublin, CA in January 2027, with six '
        'disciplines: $names.\n\nTry asking me about one of them!';
  }
}
