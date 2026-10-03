import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import 'supabase_config.dart';

/// Archie backed by the `archie-chat` Edge Function
/// (supabase/functions/archie-chat). The function streams Server-Sent Events —
/// one JSON object per `data:` line — which are mapped 1:1 onto [ArchieEvent]s.
///
/// Uses a raw streamed HTTP request rather than `functions.invoke`, which
/// buffers the whole response and would defeat the live typing effect.
class SupabaseArchieRepository implements ArchieRepository {
  SupabaseArchieRepository(this._client);

  final SupabaseClient _client;

  static final Uri _endpoint = Uri.parse(
    '${SupabaseConfig.supabaseUrl}/functions/v1/archie-chat',
  );

  @override
  Stream<ArchieEvent> ask(List<ArchieTurn> transcript) {
    final http.Client httpClient = http.Client();
    late final StreamController<ArchieEvent> controller;
    StreamSubscription<String>? lines;

    Future<void> run() async {
      try {
        var session = _client.auth.currentSession;
        if (session != null && session.isExpired) {
          session = (await _client.auth.refreshSession()).session;
        }
        if (session == null) {
          controller.add(const ArchieFailure('Sign in to chat with Archie.'));
          await controller.close();
          return;
        }

        final request = http.Request('POST', _endpoint)
          ..headers.addAll({
            'Authorization': 'Bearer ${session.accessToken}',
            'apikey': SupabaseConfig.supabasePublishableKey,
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode({
            'messages': [
              for (final t in transcript)
                {'role': t.fromUser ? 'user' : 'assistant', 'content': t.text},
            ],
          });

        final response = await httpClient.send(request);
        if (response.statusCode != 200) {
          final body = await response.stream.bytesToString();
          controller.add(
            ArchieFailure(_errorMessage(response.statusCode, body)),
          );
          await controller.close();
          return;
        }

        lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (line) {
                if (!line.startsWith('data:')) return;
                final event = _parse(line.substring(5).trim());
                if (event != null) controller.add(event);
              },
              onError: (Object _) {
                controller.add(
                  const ArchieFailure(
                    'Lost the connection to Archie. Please try again.',
                  ),
                );
                controller.close();
              },
              onDone: controller.close,
              cancelOnError: true,
            );
      } catch (_) {
        if (!controller.isClosed) {
          controller.add(
            const ArchieFailure(
              "Couldn't reach Archie. Check your connection and try again.",
            ),
          );
          await controller.close();
        }
      }
    }

    controller = StreamController<ArchieEvent>(
      onListen: run,
      // Cancelling (the Stop button) tears down the request, which aborts
      // generation server-side.
      onCancel: () async {
        await lines?.cancel();
        httpClient.close();
      },
    );
    return controller.stream;
  }

  // ---- Saved history (archie_history_setup.sql) ---------------------------

  @override
  Future<List<ArchieChatSummary>> listChats() async {
    final rows = await _client
        .from('archie_chats')
        .select('id, title, updated_at')
        .order('updated_at', ascending: false)
        .limit(kArchieMaxSavedChats);
    return [
      for (final r in rows)
        ArchieChatSummary(
          id: r['id'] as String,
          title: (r['title'] ?? '') as String,
          updatedAt: DateTime.parse(r['updated_at'] as String).toLocal(),
        ),
    ];
  }

  @override
  Future<List<ArchieSavedMessage>> loadChat(String chatId) async {
    final rows = await _client
        .from('archie_messages')
        .select('role, content, sources, steps')
        .eq('chat_id', chatId)
        .order('id');
    return [
      for (final r in rows)
        ArchieSavedMessage(
          fromUser: r['role'] == 'user',
          text: (r['content'] ?? '') as String,
          sources: [
            for (final s in (r['sources'] as List? ?? const []))
              ArchieSource(
                title: (s['title'] ?? '') as String,
                url: (s['url'] ?? '') as String,
              ),
          ],
          steps: [for (final s in (r['steps'] as List? ?? const [])) '$s'],
        ),
    ];
  }

  @override
  Future<String> saveExchange({
    String? chatId,
    required String question,
    required ArchieSavedMessage answer,
  }) async {
    try {
      // One atomic RPC: creates the chat if needed and saves both messages in
      // a single transaction, so a failure never leaves an empty chat.
      return await _client.rpc(
        'archie_save_exchange',
        params: {
          'p_chat_id': chatId,
          'p_title': archieChatTitle(question),
          'p_question': question,
          'p_answer': answer.text,
          'p_sources': [
            for (final s in answer.sources) {'title': s.title, 'url': s.url},
          ],
          'p_steps': answer.steps,
        },
      ) as String;
    } on PostgrestException catch (e) {
      if (e.message.contains('archie_chat_full')) {
        throw const ArchieChatFullException();
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteChat(String chatId) =>
      _client.from('archie_chats').delete().eq('id', chatId);

  @override
  Future<List<ArchieExchange>> recentExchanges({int limit = 100}) async {
    final rows = await _client.rpc(
      'archie_recent_exchanges',
      params: {'p_limit': limit},
    ) as List;
    return [
      for (final r in rows)
        ArchieExchange(
          question: (r['question'] ?? '') as String,
          answer: (r['answer'] ?? '') as String,
          sourceCount: (r['source_count'] ?? 0) as int,
          askedAt: DateTime.parse(r['asked_at'] as String).toLocal(),
        ),
    ];
  }

  static ArchieEvent? _parse(String data) {
    if (data.isEmpty) return null;
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    return switch (json['type']) {
      'status' => ArchieStatus((json['text'] ?? '') as String),
      'delta' => ArchieDelta((json['text'] ?? '') as String),
      'sources' => ArchieSources([
        for (final s in (json['sources'] as List? ?? const []))
          ArchieSource(
            title: (s['title'] ?? '') as String,
            url: (s['url'] ?? '') as String,
          ),
      ]),
      'error' => ArchieFailure(
        (json['message'] ?? 'Something went wrong.') as String,
      ),
      _ => null, // 'done' and unknown types: the stream closing ends the answer
    };
  }

  static String _errorMessage(int status, String body) {
    if (status == 401) return 'Sign in to chat with Archie.';
    if (status == 404) {
      return "Archie isn't set up on this server yet (the archie-chat "
          'function is not deployed).';
    }
    try {
      final message = (jsonDecode(body) as Map<String, dynamic>)['error'];
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {}
    return 'Archie ran into a problem ($status). Please try again.';
  }
}
