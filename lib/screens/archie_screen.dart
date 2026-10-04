import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../backend/backend.dart';
import '../backend/service_locator.dart';
import '../theme.dart';

const _archieAsset = 'assets/branding/archie.png';

/// Archie's own palette, Gemini-style: black with a faint emerald glow,
/// green cards and navy chat bubbles in dark mode (matching the app's dark
/// theme) and a soft mint-white in light mode. [of] picks the one matching the app's current theme.
class _ArchieColors {
  const _ArchieColors({
    required this.brightness,
    required this.background,
    required this.glow,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.text,
    required this.textStrong,
    required this.textDim,
    required this.mint,
    required this.onMint,
    required this.userBubble,
    required this.error,
    required this.greeting,
    required this.shadow,
  });

  final Brightness brightness;
  final Color background;
  final Color glow;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color text;

  /// Bold text in answers — a touch brighter/darker than [text].
  final Color textStrong;
  final Color textDim;

  /// The accent: links, progress, the send button.
  final Color mint;
  final Color onMint;
  final Color userBubble;
  final Color error;

  /// The gradient the user's name is painted in on the welcome screen.
  final List<Color> greeting;
  final Color shadow;

  static const dark = _ArchieColors(
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    glow: Color(0xFF0E7A57),
    surface: EmeraldTheme.nightSurface,
    surfaceHigh: Color(0xFF1B3B2F),
    border: EmeraldTheme.nightBorder,
    text: EmeraldTheme.nightText,
    textStrong: Colors.white,
    textDim: EmeraldTheme.nightTextDim,
    mint: EmeraldTheme.mint,
    onMint: Color(0xFF000000),
    userBubble: Color(0xFF26457E),
    error: Color(0xFFF2A39B),
    greeting: [Color(0xFF9BF6CB), Color(0xFF3CC48A)],
    shadow: Color(0x59000000),
  );

  static const light = _ArchieColors(
    brightness: Brightness.light,
    background: Color(0xFFF3F8F5),
    glow: Color(0xFF8FDDB8),
    surface: Colors.white,
    surfaceHigh: Color(0xFFE4F0E9),
    border: Color(0xFFD2E3D9),
    text: EmeraldTheme.ink,
    textStrong: Color(0xFF0A1410),
    textDim: Color(0xFF5A7065),
    mint: EmeraldTheme.emerald,
    onMint: Colors.white,
    userBubble: EmeraldTheme.emerald,
    error: Color(0xFFB3261E),
    greeting: [Color(0xFF1FA572), EmeraldTheme.deepEmerald],
    shadow: Color(0x1A0A5F43),
  );

  static _ArchieColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Status-bar icons that read on [background].
  SystemUiOverlayStyle get overlayStyle => brightness == Brightness.dark
      ? SystemUiOverlayStyle.light
      : SystemUiOverlayStyle.dark;
}

/// "Archie" tab — the in-app AI assistant (dragon mascot in shades).
///
/// Modeled on FTC Bonfire's "Sparky": a welcome screen with clickable
/// conversation starters, live progress steps while Archie searches/reads,
/// a streamed answer revealed with a smooth typing animation, and the web
/// sources it cited. Answers come from [ArchieRepository] (the `archie-chat`
/// Edge Function on the live backend), grounded in the live summit catalog,
/// the user's own schedule, official sites, and web search.
///
/// The conversation lives in memory for the app session (the tab stays alive
/// in the [IndexedStack]); "New chat" clears it.
class ArchieScreen extends StatefulWidget {
  const ArchieScreen({super.key});

  @override
  State<ArchieScreen> createState() => _ArchieScreenState();

  static ThemeData _archieTheme(_ArchieColors c) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: EmeraldTheme.emerald,
          brightness: c.brightness,
        ).copyWith(
          primary: c.mint,
          onPrimary: c.onMint,
          surface: c.background,
          onSurface: c.text,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.mint,
        selectionHandleColor: c.mint,
      ),
    );
  }

  /// [base] with the bottom navigation bar restyled to sit flush under
  /// Archie's screen. [RootNav] applies it while this tab is selected.
  static ThemeData navBarTheme(ThemeData base) {
    final c = base.brightness == Brightness.dark
        ? _ArchieColors.dark
        : _ArchieColors.light;
    final labels = base.navigationBarTheme.labelTextStyle;
    return base.copyWith(
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.surfaceHigh,
        iconTheme: WidgetStatePropertyAll(IconThemeData(color: c.textDim)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => (labels?.resolve(states) ?? const TextStyle()).copyWith(
            color: states.contains(WidgetState.selected) ? c.text : c.textDim,
          ),
        ),
      ),
    );
  }
}

class _ArchieScreenState extends State<ArchieScreen>
    with TickerProviderStateMixin {
  final _messages = <_ChatMessage>[];
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  /// Drives the typewriter reveal of the answer currently being written.
  late final Ticker _typer = createTicker(_onTypeTick);
  Duration _lastTick = Duration.zero;
  double _pendingChars = 0;

  /// When the last typing haptic fired (in [_typer] time).
  Duration _lastHaptic = Duration.zero;

  /// The answer being streamed / revealed, if any.
  _ChatMessage? _active;
  StreamSubscription<ArchieEvent>? _subscription;

  /// Follow the answer as it grows, unless the user scrolled up to read.
  bool _followBottom = true;

  /// Fixed per screen so the starter picks don't reshuffle on every rebuild.
  final int _starterSeed = math.Random().nextInt(1 << 20);

  /// The open conversation's saved-chat handle (id is null until its first
  /// exchange is saved). Replaced on New chat / opening a saved chat, so a
  /// save still in flight lands on the conversation it came from.
  _Conversation _conversation = _Conversation();

  /// Saves run one at a time, so a chat's first save (which creates it)
  /// finishes before the next exchange is saved into it.
  Future<void> _saveQueue = Future.value();

  /// The server reported this chat is at its question limit.
  bool _chatFull = false;

  bool get _busy => _active != null;

  int get _questionCount => _messages.where((m) => m.fromUser).length;

  /// No more questions in this chat — the user must start a new one.
  bool get _atLimit =>
      _chatFull || _questionCount >= kArchieMaxQuestionsPerChat;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _typer.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Conversation
  // -------------------------------------------------------------------------

  void _send(String raw) {
    final text = raw.trim();
    if (text.isEmpty || _busy || _atLimit) return;
    HapticFeedback.lightImpact();

    // Everything said so far (minus failed replies) gives Archie context.
    final transcript = [
      for (final m in _messages)
        if (!m.failed && m.text.trim().isNotEmpty)
          ArchieTurn(fromUser: m.fromUser, text: m.text),
      ArchieTurn(fromUser: true, text: text),
    ];

    final reply = _ChatMessage.archie();
    setState(() {
      _messages
        ..add(_ChatMessage.user(text))
        ..add(reply);
      _active = reply;
      _input.clear();
      _followBottom = true;
    });
    _scrollToBottom(animate: true);

    _subscription = archieRepository
        .ask(transcript)
        .listen(
          (event) {
            if (!mounted) return;
            setState(() {
              switch (event) {
                case ArchieStatus(:final text):
                  reply.steps.add(text);
                case ArchieDelta(:final text):
                  reply.text += text;
                  _startTyping();
                case ArchieSources(:final sources):
                  reply.sources = sources;
                case ArchieFailure(:final message):
                  reply
                    ..failed = reply.text.isEmpty
                    ..error = message;
              }
            });
            _scrollToBottom();
          },
          onDone: () => _finishStream(reply),
          onError: (Object _) {
            reply
              ..failed = reply.text.isEmpty
              ..error = 'Something went wrong. Please try again.';
            _finishStream(reply);
          },
          cancelOnError: true,
        );
  }

  void _finishStream(_ChatMessage reply) {
    _subscription = null;
    if (!mounted) return;
    setState(() => reply.streamDone = true);
    // Otherwise the typer settles it once the text is fully revealed.
    if (!reply.typing) _settle(reply);
    _scrollToBottom();
  }

  /// The reply is final (fully shown, stream over, or stopped): free the
  /// composer and save the exchange to the user's history.
  void _settle(_ChatMessage reply) {
    _typer.stop();
    if (mounted) setState(() => _active = null);
    if (reply.failed || reply.text.trim().isEmpty) return;
    final index = _messages.indexOf(reply);
    if (index < 1) return;
    final question = _messages[index - 1].text;
    final conversation = _conversation;
    final answer = ArchieSavedMessage(
      fromUser: false,
      text: reply.text,
      sources: reply.sources,
      steps: List.of(reply.steps),
    );
    _saveQueue = _saveQueue.then((_) async {
      try {
        conversation.id = await archieRepository.saveExchange(
          chatId: conversation.id,
          question: question,
          answer: answer,
        );
      } on ArchieChatFullException {
        if (mounted && identical(conversation, _conversation)) {
          setState(() => _chatFull = true);
        }
      } catch (e) {
        // The chat on screen is unaffected, but say so once per conversation
        // rather than failing silently (an earlier silent failure hid a bug).
        debugPrint('Archie: could not save exchange: $e');
        if (mounted && !conversation.warnedSaveFailed) {
          conversation.warnedSaveFailed = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Couldn't save this chat to your history."),
            ),
          );
        }
      }
    });
  }

  /// Stop button: cut the stream and keep only what's already on screen.
  void _stop() {
    final reply = _active;
    if (reply == null) return;
    HapticFeedback.selectionClick();
    _subscription?.cancel();
    _subscription = null;
    _typer.stop();
    setState(() {
      reply
        ..text = reply.text.substring(0, reply.revealed).trimRight()
        ..revealed = reply.text.length
        ..streamDone = true
        ..stopped = true;
      if (reply.text.isEmpty) reply.failed = true;
    });
    _settle(reply);
  }

  void _retry(_ChatMessage failed) {
    final index = _messages.indexOf(failed);
    if (index < 1 || _busy) return;
    final question = _messages[index - 1].text;
    setState(() => _messages.removeRange(index - 1, index + 1));
    _send(question);
  }

  void _newChat({bool haptic = true}) {
    if (haptic) HapticFeedback.selectionClick();
    _cancelStream();
    setState(() {
      _messages.clear();
      _active = null;
      _conversation = _Conversation();
      _chatFull = false;
    });
  }

  void _cancelStream() {
    _subscription?.cancel();
    _subscription = null;
    _typer.stop();
  }

  // -------------------------------------------------------------------------
  // Saved history
  // -------------------------------------------------------------------------

  Future<void> _openChat(ArchieChatSummary chat) async {
    _cancelStream();
    try {
      final saved = await archieRepository.loadChat(chat.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(saved.map(_ChatMessage.saved));
        _active = null;
        _conversation = _Conversation(chat.id);
        _chatFull = false;
        _followBottom = true;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open that chat.")));
    }
  }

  void _showHistory() {
    HapticFeedback.selectionClick();
    _focus.unfocus();
    final c = _ArchieColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Theme(
        data: ArchieScreen._archieTheme(c),
        child: _HistorySheet(
          currentChatId: _conversation.id,
          onOpen: (chat) {
            Navigator.of(sheetContext).pop();
            _openChat(chat);
          },
          onNewChat: () {
            Navigator.of(sheetContext).pop();
            _newChat();
          },
          onDeleted: (id) {
            if (id == _conversation.id) _newChat(haptic: false);
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Typewriter — reveals streamed text at a steady, readable pace (ChatGPT-
  // style) instead of in network-sized bursts, speeding up when it falls
  // behind so it never lags the stream by much.
  // -------------------------------------------------------------------------

  void _startTyping() {
    if (_typer.isActive) return;
    _lastTick = Duration.zero;
    _lastHaptic = Duration.zero;
    _pendingChars = 0;
    _typer.start();
  }

  void _onTypeTick(Duration elapsed) {
    final reply = _active;
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (reply == null) {
      _typer.stop();
      return;
    }
    final backlog = reply.text.length - reply.revealed;
    if (backlog <= 0) {
      if (reply.streamDone) _settle(reply);
      return;
    }
    _pendingChars += (60 + backlog * 3) * dt;
    var step = _pendingChars.floor();
    if (step == 0) return;
    _pendingChars -= step;
    var next = math.min(reply.text.length, reply.revealed + step);
    // Never split an emoji's surrogate pair mid-reveal.
    if (next < reply.text.length) {
      final unit = reply.text.codeUnitAt(next - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) next++;
    }
    final started = reply.revealed == 0;
    setState(() => reply.revealed = next);
    _typingHaptic(elapsed, started: started, finished: reply.settled);
    if (reply.settled) _settle(reply);
    _scrollToBottom();
  }

  /// Haptics that follow the typing: a light tap as the answer begins, soft
  /// ticks while it types (throttled so it reads as a texture, not a buzz), and
  /// a light tap when it finishes.
  void _typingHaptic(
    Duration elapsed, {
    required bool started,
    required bool finished,
  }) {
    if (started || finished) {
      HapticFeedback.lightImpact();
      _lastHaptic = elapsed;
    } else if (elapsed - _lastHaptic >= const Duration(milliseconds: 90)) {
      HapticFeedback.selectionClick();
      _lastHaptic = elapsed;
    }
  }

  // -------------------------------------------------------------------------
  // Scrolling
  // -------------------------------------------------------------------------

  void _scrollToBottom({bool animate = false}) {
    if (!_followBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  bool _onScroll(ScrollNotification n) {
    // Only user drags change follow mode; our own jumps don't.
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      _followBottom = n.metrics.extentAfter < 48;
    } else if (n is ScrollEndNotification) {
      _followBottom = n.metrics.extentAfter < 48;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Follows the app's Light / Dark / System appearance.
    final c = _ArchieColors.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.overlayStyle,
      child: Theme(
        data: ArchieScreen._archieTheme(c),
        child: Scaffold(
          backgroundColor: c.background,
          // The RootNav scaffold already lifts its body above the keyboard.
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              const Positioned.fill(child: _GlowBackground()),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _Header(
                      showNewChat: _messages.isNotEmpty,
                      onNewChat: _newChat,
                      onHistory: _showHistory,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _focus.unfocus(),
                        behavior: HitTestBehavior.translucent,
                        child: _messages.isEmpty
                            ? _Welcome(
                                firstName: appState.userName.split(' ').first,
                                starters: _starters(),
                                onStarter: _send,
                              )
                            : NotificationListener<ScrollNotification>(
                                onNotification: _onScroll,
                                child: ListView.builder(
                                  controller: _scroll,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    24,
                                  ),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, i) {
                                    final m = _messages[i];
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 18),
                                      child: m.fromUser
                                          ? _UserBubble(text: m.text)
                                          : _ArchieReply(
                                              message: m,
                                              active: identical(m, _active),
                                              onRetry: () => _retry(m),
                                            ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ),
                    if (_atLimit && !_busy)
                      _ChatFullNotice(onNewChat: _newChat)
                    else
                      _Composer(
                        controller: _input,
                        focusNode: _focus,
                        busy: _busy,
                        questionsLeft:
                            kArchieMaxQuestionsPerChat - _questionCount,
                        onSend: () => _send(_input.text),
                        onStop: _stop,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The three conversation starters on the welcome screen, top to bottom:
  /// one tailored to whether the user has a schedule yet, one evergreen, and
  /// one about a random discipline from the live catalog. Edit this list to
  /// change them (each is an icon + the exact question that gets sent).
  List<_Starter> _starters() {
    final rng = math.Random(_starterSeed);
    final disciplines = appState.disciplines;
    return [
      appState.mySessions.isNotEmpty
          ? const _Starter(
              Icons.schedule,
              "What's on my schedule, and where do I need to be?",
            )
          : const _Starter(
              Icons.auto_awesome,
              'What is Emerald Summit, and what can I do there?',
            ),
      const _Starter(
        Icons.event_seat_outlined,
        'Which sessions still have open seats?',
      ),
      disciplines.isNotEmpty
          ? () {
              final d = disciplines[rng.nextInt(disciplines.length)];
              return _Starter(
                Icons.explore_outlined,
                'What happens in ${d.name}, and which session should I try?',
              );
            }()
          : const _Starter(
              Icons.school_outlined,
              'Tell me about Emerald High School',
            ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class _ChatMessage {
  _ChatMessage.user(this.text)
    : fromUser = true,
      revealed = text.length,
      streamDone = true;

  _ChatMessage.archie()
    : fromUser = false,
      text = '',
      revealed = 0,
      streamDone = false;

  /// A message reopened from saved history — already complete.
  _ChatMessage.saved(ArchieSavedMessage m)
    : fromUser = m.fromUser,
      text = m.text,
      revealed = m.text.length,
      streamDone = true {
    steps.addAll(m.steps);
    sources = m.sources;
  }

  final bool fromUser;

  /// Everything received so far (markdown for Archie).
  String text;

  /// How many characters of [text] the typewriter has revealed.
  int revealed;

  final List<String> steps = [];
  List<ArchieSource> sources = const [];
  bool streamDone;
  bool stopped = false;

  /// The reply produced no answer at all (shown as an error with Retry).
  bool failed = false;
  String? error;

  bool get typing => revealed < text.length;
  bool get settled => streamDone && !typing;
}

/// The saved-chat handle for one on-screen conversation.
class _Conversation {
  _Conversation([this.id]);

  /// Null until the conversation's first exchange is saved.
  String? id;

  /// A save failed and the user has been told (once).
  bool warnedSaveFailed = false;
}

class _Starter {
  const _Starter(this.icon, this.text);
  final IconData icon;
  final String text;
}

// ---------------------------------------------------------------------------
// Chrome: background, header, composer
// ---------------------------------------------------------------------------

/// The night background with a soft glow rising from the bottom, à la Gemini.
class _GlowBackground extends StatelessWidget {
  const _GlowBackground();

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, 0.9),
          radius: 1.25,
          colors: [c.glow.withValues(alpha: .30), c.background],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.showNewChat,
    required this.onNewChat,
    required this.onHistory,
  });

  final bool showNewChat;
  final VoidCallback onNewChat;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const ArchieAvatar(size: 32),
            const SizedBox(width: 10),
            Text(
              'Archie',
              style: TextStyle(
                color: c.text,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Your chats',
              onPressed: onHistory,
              icon: Icon(Icons.history, color: c.text),
            ),
            // Takes no space when hidden, so History sits flush right on the
            // welcome screen; it slides over when New chat appears.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: showNewChat
                  ? IconButton(
                      tooltip: 'New chat',
                      onPressed: onNewChat,
                      icon: Icon(Icons.add_comment_outlined, color: c.text),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Gemini-style pill input with a send / stop button.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.questionsLeft,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;

  /// Questions still allowed in this chat; the hint mentions it near the end.
  final int questionsLeft;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    final canSend = !busy && controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 4, 6, 4),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: c.border),
              boxShadow: [
                BoxShadow(
                  color: c.shadow,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      style: TextStyle(color: c.text, fontSize: 16.5),
                      decoration: InputDecoration(
                        hintText: questionsLeft <= 3
                            ? 'Ask Archie · $questionsLeft left in this chat'
                            : 'Ask Archie',
                        hintStyle: TextStyle(color: c.textDim, fontSize: 16.5),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, a) =>
                      ScaleTransition(scale: a, child: child),
                  child: busy
                      ? _RoundButton(
                          key: const ValueKey('stop'),
                          tooltip: 'Stop',
                          icon: Icons.stop_rounded,
                          background: c.text,
                          foreground: c.background,
                          onPressed: onStop,
                        )
                      : _RoundButton(
                          key: const ValueKey('send'),
                          tooltip: 'Send',
                          icon: Icons.arrow_upward_rounded,
                          background: canSend ? c.mint : c.surfaceHigh,
                          foreground: canSend ? c.background : c.textDim,
                          onPressed: canSend ? onSend : null,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const _PrivacyNote(),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, color: foreground, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

/// The notice under the composer: accuracy + how chats are used.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    return Text(
      'Archie can make mistakes. Chats are saved to your account and '
      'reviewed anonymously to improve Archie.',
      textAlign: TextAlign.center,
      style: TextStyle(color: c.textDim, fontSize: 11, height: 1.3),
    );
  }
}

/// Replaces the composer once a chat reaches its question limit.
class _ChatFullNotice extends StatelessWidget {
  const _ChatFullNotice({required this.onNewChat});

  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'This conversation is too long. Please start a new chat.',
                style: TextStyle(color: c.text, fontSize: 14.5, height: 1.35),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 42),
                backgroundColor: c.mint,
                foregroundColor: c.background,
              ),
              onPressed: onNewChat,
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              label: const Text('New chat'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Your chats": the user's saved conversations (up to
/// [kArchieMaxSavedChats]), to reopen or delete.
class _HistorySheet extends StatefulWidget {
  const _HistorySheet({
    required this.currentChatId,
    required this.onOpen,
    required this.onNewChat,
    required this.onDeleted,
  });

  final String? currentChatId;
  final ValueChanged<ArchieChatSummary> onOpen;
  final VoidCallback onNewChat;
  final ValueChanged<String> onDeleted;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  List<ArchieChatSummary>? _chats;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final chats = await archieRepository.listChats();
      if (mounted) setState(() => _chats = chats);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _delete(ArchieChatSummary chat) async {
    final c = _ArchieColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surfaceHigh,
        title: const Text('Delete this chat?'),
        content: Text('"${chat.title}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _chats?.removeWhere((c) => c.id == chat.id));
    try {
      await archieRepository.deleteChat(chat.id);
      widget.onDeleted(chat.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete that chat.")),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    final chats = _chats;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your chats',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onNewChat,
                    icon: const Icon(Icons.add_comment_outlined, size: 18),
                    label: const Text('New chat'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Archie keeps your $kArchieMaxSavedChats most recent chats — '
                'starting another removes the oldest. Organizers review '
                'questions and answers anonymously (never your name) to '
                'improve Archie.',
                style: TextStyle(color: c.textDim, fontSize: 12.5, height: 1.4),
              ),
            ),
            if (_failed)
              Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Couldn't load your chats.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textDim),
                ),
              )
            else if (chats == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (chats.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Text(
                  'No saved chats yet. Ask Archie something and it will '
                  'show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textDim),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: chats.length,
                  itemBuilder: (context, i) {
                    final chat = chats[i];
                    final current = chat.id == widget.currentChatId;
                    return ListTile(
                      contentPadding: const EdgeInsets.only(left: 20, right: 8),
                      leading: Icon(
                        current ? Icons.chat_bubble : Icons.chat_bubble_outline,
                        color: current ? c.mint : c.textDim,
                        size: 20,
                      ),
                      title: Text(
                        chat.title.isEmpty ? 'Untitled chat' : chat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.text),
                      ),
                      subtitle: Text(
                        _relativeTime(chat.updatedAt),
                        style: TextStyle(color: c.textDim, fontSize: 12.5),
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete chat',
                        icon: Icon(Icons.delete_outline, color: c.textDim),
                        onPressed: () => _delete(chat),
                      ),
                      onTap: () => widget.onOpen(chat),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Just now", "5 min ago", "3 hr ago", "Yesterday", "Mon", or "Jan 14".
String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays < 2) return 'Yesterday';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  if (diff.inDays < 7) return days[t.weekday - 1];
  return '${months[t.month - 1]} ${t.day}';
}

// ---------------------------------------------------------------------------
// Welcome — greeting + conversation starters
// ---------------------------------------------------------------------------

class _Welcome extends StatefulWidget {
  const _Welcome({
    required this.firstName,
    required this.starters,
    required this.onStarter,
  });

  final String firstName;
  final List<_Starter> starters;
  final ValueChanged<String> onStarter;

  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> with TickerProviderStateMixin {
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  /// Archie floats gently while waiting for a question.
  late final _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _intro.dispose();
    _bob.dispose();
    super.dispose();
  }

  /// Fade + rise for the item whose entrance runs from [start] to [end] (0–1).
  Widget _entrance(double start, double end, Widget child) {
    final a = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .15),
          end: Offset.zero,
        ).animate(a),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.firstName.isEmpty ? 'there' : widget.firstName;
    final c = _ArchieColors.of(context);
    final greetingStyle = _greetingStyle.copyWith(color: c.text);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _entrance(
                0,
                .45,
                AnimatedBuilder(
                  animation: _bob,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(
                      0,
                      -6 * Curves.easeInOut.transform(_bob.value),
                    ),
                    child: child,
                  ),
                  child: const ArchieAvatar(size: 88, glow: true),
                ),
              ),
              const SizedBox(height: 18),
              _entrance(
                .12,
                .55,
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Hi '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) =>
                              LinearGradient(colors: c.greeting)
                                  .createShader(bounds),
                          child: Text(name, style: greetingStyle),
                        ),
                      ),
                      const TextSpan(text: ",\nwhat's the move?"),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: greetingStyle,
                ),
              ),
              const SizedBox(height: 10),
              _entrance(
                .2,
                .6,
                Text(
                  'Ask me anything about Emerald Summit or Emerald High.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textDim, fontSize: 14.5),
                ),
              ),
              const SizedBox(height: 20),
              _entrance(.25, .65, Divider(color: c.border, height: 1)),
              const SizedBox(height: 18),
              for (final (i, s) in widget.starters.indexed)
                _entrance(
                  .3 + i * .1,
                  .7 + i * .1,
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StarterCard(
                      starter: s,
                      onTap: () => widget.onStarter(s.text),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static const _greetingStyle = TextStyle(
    fontSize: 28,
    height: 1.25,
    fontWeight: FontWeight.w300,
    letterSpacing: -.3,
  );
}

class _StarterCard extends StatelessWidget {
  const _StarterCard({required this.starter, required this.onTap});

  final _Starter starter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: c.mint.withValues(alpha: .12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(starter.icon, size: 20, color: c.mint),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  starter.text,
                  style: TextStyle(color: c.text, fontSize: 15, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: c.userBubble,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(6),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: SelectableText(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchieReply extends StatelessWidget {
  const _ArchieReply({
    required this.message,
    required this.active,
    required this.onRetry,
  });

  final _ChatMessage message;

  /// Still streaming or still being typed out.
  final bool active;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    final m = message;
    final shown = m.text.substring(0, m.revealed);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ArchieAvatar(size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Steps(steps: m.steps, working: active && shown.isEmpty),
              if (shown.isNotEmpty)
                MarkdownBody(
                  // A trailing dot marks the typing position, like ChatGPT.
                  data: active ? '$shown ●' : shown,
                  selectable: !active,
                  styleSheet: _markdownStyle(context),
                  onTapLink: (_, href, _) => _openLink(context, href),
                ),
              if (m.failed || (m.error != null && m.settled))
                _ErrorRow(
                  message:
                      m.error ??
                      (m.stopped ? 'Stopped.' : 'No answer this time.'),
                  onRetry: m.stopped ? null : onRetry,
                ),
              if (m.settled && !m.failed && m.stopped)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Stopped',
                    style: TextStyle(
                      color: c.textDim,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (m.settled && m.sources.isNotEmpty) _Sources(m.sources),
              if (m.settled && !m.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: IconButton(
                    tooltip: 'Copy',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: c.textDim,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: m.text));
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          const SnackBar(
                            content: Text('Copied'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final c = _ArchieColors.of(context);
    final body = TextStyle(color: c.text, fontSize: 15.5, height: 1.5);
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: body,
      listBullet: body,
      strong: TextStyle(fontWeight: FontWeight.w700, color: c.textStrong),
      em: const TextStyle(fontStyle: FontStyle.italic),
      a: TextStyle(
        color: c.mint,
        decoration: TextDecoration.underline,
        decorationColor: c.mint,
      ),
      h1: body.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      h2: body.copyWith(fontSize: 17.5, fontWeight: FontWeight.w700),
      h3: body.copyWith(fontSize: 16.5, fontWeight: FontWeight.w600),
      blockSpacing: 10,
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: c.mint,
        backgroundColor: c.surfaceHigh,
      ),
      codeblockDecoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.border, width: 3)),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
    );
  }
}

/// Sparky-style progress: "Thinking…" with live steps while Archie works,
/// then a collapsible summary of what it did once the answer starts.
class _Steps extends StatefulWidget {
  const _Steps({required this.steps, required this.working});

  final List<String> steps;
  final bool working;

  @override
  State<_Steps> createState() => _StepsState();
}

class _StepsState extends State<_Steps> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    final steps = widget.steps;
    if (widget.working) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Row(
          children: [
            const _PulsingDots(),
            const SizedBox(width: 10),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  steps.isEmpty ? 'Thinking…' : '${steps.last}…',
                  key: ValueKey(steps.length),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.mint,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (steps.isEmpty) return const SizedBox.shrink();

    final searches = steps.where((s) => s.startsWith('Searching')).length;
    final reads = steps.where((s) => s.startsWith('Reading')).length;
    final summary = [
      if (searches > 0) 'Searched the web${searches > 1 ? ' ×$searches' : ''}',
      if (reads > 0) 'read $reads page${reads > 1 ? 's' : ''}',
      if (searches == 0 && reads == 0)
        '${steps.length} step${steps.length > 1 ? 's' : ''}',
    ].join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.travel_explore, size: 15, color: c.textDim),
                  const SizedBox(width: 6),
                  Text(
                    summary[0].toUpperCase() + summary.substring(1),
                    style: TextStyle(
                      color: c.textDim,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: c.textDim,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topLeft,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Container(
                    margin: const EdgeInsets.only(top: 4, left: 6),
                    padding: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: c.border, width: 2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in steps)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.check_circle,
                                    size: 13,
                                    color: c.mint,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s,
                                    style: TextStyle(
                                      color: c.textDim,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity:
                    .3 +
                    .7 *
                        (.5 +
                            .5 * math.sin((_c.value - i * .18) * 2 * math.pi)),
                child: CircleAvatar(radius: 3.5, backgroundColor: c.mint),
              ),
            ),
        ],
      ),
    );
  }
}

class _Sources extends StatelessWidget {
  const _Sources(this.sources);
  final List<ArchieSource> sources;

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sources',
            style: TextStyle(
              color: c.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: .4,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in sources)
                Material(
                  color: c.surfaceHigh,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openLink(context, s.url),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.public, size: 14, color: c.mint),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 190),
                            child: Text(
                              s.title.isEmpty ? _host(s.url) : s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.text, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _host(String url) =>
      Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: c.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: c.error, fontSize: 14, height: 1.35),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

Future<void> _openLink(BuildContext context, String? href) async {
  final uri = href == null ? null : Uri.tryParse(href);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
  }
}

// ---------------------------------------------------------------------------
// Archie's face — used in the header, beside replies, and in the tab bar.
// ---------------------------------------------------------------------------

/// The Archie mascot in a soft mint disc (Sparky-style avatar). [glow] adds an
/// emerald halo for the large welcome-screen version.
class ArchieAvatar extends StatelessWidget {
  const ArchieAvatar({super.key, required this.size, this.glow = false});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final c = _ArchieColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-.3, -.4),
          colors: [Color(0xFFF2FFF8), Color(0xFFB9EDD3)],
        ),
        boxShadow: [
          if (glow)
            BoxShadow(
              color: c.mint.withValues(alpha: .35),
              blurRadius: size * .45,
              spreadRadius: size * .04,
            ),
        ],
      ),
      padding: EdgeInsets.all(size * .08),
      child: Image.asset(_archieAsset, filterQuality: FilterQuality.medium),
    );
  }
}

/// The bottom-bar icon for the Archie tab: the mascot's face, ringed in the
/// brand color when selected.
class ArchieNavIcon extends StatelessWidget {
  const ArchieNavIcon({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: const ArchieAvatar(size: 24),
    );
  }
}
