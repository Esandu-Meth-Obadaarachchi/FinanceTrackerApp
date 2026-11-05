import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_session.dart';
import '../services/ai_service.dart';
import '../state/app_state.dart';
import '../theme/app_text.dart';
import '../theme/palette.dart';
import '../theme/theme_controller.dart';
import '../utils/formatters.dart';
import '../utils/responsive.dart';

/// Opens the assistant, re-providing [AppState] for the pushed route.
void openAssistant(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const AssistantScreen(),
      ),
    ),
  );
}

/// Ask questions about your own money.
///
/// The answer comes from an agent that calls tools over a snapshot of this
/// device's data, so it quotes real figures rather than inventing them. The
/// tools it used are shown under each answer: with money, being able to see
/// *how* it got there matters more than the reply sounding confident.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<ChatMessage> _messages = [];
  bool _busy = false;

  /// Id of the open conversation. Null until the first message is sent, so an
  /// empty chat is never stored.
  String? _chatId;

  /// True once this conversation exists in Firestore. Until then a save goes
  /// through createChat, which enforces the five-chat cap.
  bool _created = false;

  /// The latest saved chat is reopened once, the first time history loads.
  bool _restored = false;

  /// Saves run one after another so two quick ones cannot both think they are
  /// creating the chat.
  Future<void> _saving = Future.value();

  /// Echoed straight back to the backend each turn. Carries the agent's
  /// unfinished intent across a clarification.
  Map<String, dynamic> _state = const {};

  /// Proposals already applied, so a second tap cannot write twice.
  final Set<String> _applied = {};

  /// Proposals the user waved away. Kept apart from [_applied] so a cancelled
  /// card never claims it saved something.
  final Set<String> _dismissed = {};

  static const _starters = [
    'How much did I spend on food this month?',
    'What do I still owe, and who owes me?',
    'Am I over budget on anything?',
    'What pending income is still outstanding?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _persist() {
    if (_messages.isEmpty) return;
    final app = context.read<AppState>();
    _chatId ??= app.newChatId();
    final firstUser = _messages.firstWhere((m) => m.role == 'user',
        orElse: () => _messages.first);
    final chat = ChatSession(
      id: _chatId!,
      title: chatTitleFrom(firstUser.text),
      messages: List.of(_messages),
      state: _state,
      applied: {..._applied},
      dismissed: {..._dismissed},
    );
    _saving = _saving.then((_) async {
      try {
        await app.saveChat(chat, isNew: !_created);
        _created = true;
      } catch (_) {
        // History is a convenience; a failed save must never break the chat.
      }
    });
  }

  void _load(ChatSession c) {
    _chatId = c.id;
    _created = true;
    _messages
      ..clear()
      ..addAll(c.messages);
    _state = c.state;
    _applied
      ..clear()
      ..addAll(c.applied);
    _dismissed
      ..clear()
      ..addAll(c.dismissed);
  }

  void _newChat() {
    if (_busy) return;
    setState(() {
      _chatId = null;
      _created = false;
      _messages.clear();
      _state = const {};
      _applied.clear();
      _dismissed.clear();
    });
  }

  void _openChat(ChatSession c) {
    if (_busy) return;
    setState(() => _load(c));
    _scrollDown();
  }

  void _deleteChat(String id) {
    context.read<AppState>().deleteChat(id);
    if (id == _chatId) _newChat();
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _busy) return;

    final app = context.read<AppState>();
    setState(() {
      _messages.add(ChatMessage('user', question));
      _busy = true;
      _input.clear();
    });
    _scrollDown();

    try {
      // Only prior turns travel as history; the snapshot is rebuilt each
      // time so the agent always sees current figures.
      final history = [
        for (final m in _messages.take(_messages.length - 1))
          (role: m.role, content: m.text),
      ];
      final reply = await AiService.instance
          .ask(question, app, history: history, state: _state);
      if (!mounted) return;
      setState(() {
        _state = reply.state;
        _messages.add(ChatMessage(
          'assistant',
          reply.answer,
          tools: reply.toolCalls,
          provider: reply.provider,
          question: reply.question,
          proposal: reply.proposal,
        ));
      });
      _persist();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage('assistant',
            'I could not reach the assistant.\n\n$e'));
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;

    // Pick up where the last conversation left off, once history has loaded
    // and only if the user has not already started typing a new one.
    final app = context.watch<AppState>();
    if (!_restored && app.chatsReady) {
      _restored = true;
      if (_messages.isEmpty && app.chats.isNotEmpty) _load(app.chats.first);
    }

    final wide = context.isWide;

    // The chat itself. Its width, not the window's, decides how the column is
    // centred, because the sidebar takes a slice of the window on desktop.
    final chatPane = Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => _messages.isEmpty
                ? _starterList(colors, box.maxWidth)
                : ListView(
                    controller: _scroll,
                    padding: _insets(box.maxWidth, top: 16),
                    children: [
                      for (final m in _messages) _bubble(m, colors),
                      if (_busy) _thinking(colors),
                    ],
                  ),
          ),
        ),
        _composer(colors),
      ],
    );

    Widget sidebar({required bool inDrawer}) => _ChatSidebar(
          currentId: _chatId,
          busy: _busy,
          inDrawer: inDrawer,
          onNew: _newChat,
          onOpen: _openChat,
          onDelete: _deleteChat,
        );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colors.bg,
      // On a phone the same list slides in from the right instead.
      endDrawer: wide
          ? null
          : Drawer(
              backgroundColor: colors.card,
              width: 300,
              child: sidebar(inDrawer: true),
            ),
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.text),
        title: Text('Assistant',
            style: sans(size: 18, weight: FontWeight.w800, color: colors.text)),
        actions: wide
            ? null
            : [
                IconButton(
                  tooltip: 'New chat',
                  onPressed: _busy || _messages.isEmpty ? null : _newChat,
                  icon: Icon(Icons.add_comment_outlined,
                      color: _busy || _messages.isEmpty
                          ? colors.muted
                          : colors.text),
                ),
                IconButton(
                  tooltip: 'Past chats',
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  icon: Icon(Icons.history, color: colors.text),
                ),
                const SizedBox(width: 4),
              ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: colors.border),
        ),
      ),
      body: wide
          ? Row(
              children: [
                Container(
                  width: 280,
                  decoration: BoxDecoration(
                    color: colors.card,
                    border: Border(right: BorderSide(color: colors.border)),
                  ),
                  child: sidebar(inDrawer: false),
                ),
                Expanded(child: chatPane),
              ],
            )
          : chatPane,
    );
  }

  /// [centredInsets] measured against the chat pane rather than the window.
  EdgeInsets _insets(double paneWidth, {double top = 14}) {
    final side = ((paneWidth - 760) / 2).clamp(16.0, double.infinity);
    return EdgeInsets.fromLTRB(side, top, side, 32);
  }

  Widget _starterList(Palette colors, double paneWidth) {
    return ListView(
      padding: _insets(paneWidth, top: 28),
      children: [
        Icon(Icons.auto_awesome, size: 32, color: colors.sub),
        const SizedBox(height: 12),
        Text('Ask about your money',
            textAlign: TextAlign.center,
            style:
                sans(size: 18, weight: FontWeight.w700, color: colors.text)),
        const SizedBox(height: 6),
        Text(
          'Answers come from your own entries, not guesswork.',
          textAlign: TextAlign.center,
          style: sans(size: 13, color: colors.sub),
        ),
        const SizedBox(height: 24),
        for (final s in _starters)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => _send(s),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: colors.card,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(s,
                          style: sans(size: 13.5, color: colors.text)),
                    ),
                    Icon(Icons.north_east, size: 14, color: colors.sub),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _apply(AgentProposal p) async {
    if (_applied.contains(p.id)) return;
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _applied.add(p.id));
    try {
      await AiService.applyProposal(p, app);
      if (!mounted) return;
      _persist();
      messenger.showSnackBar(SnackBar(
          content: Text(p.isDelete ? 'Deleted' : 'Saved')));
    } catch (e) {
      if (!mounted) return;
      // Let them try again — the failure was not their doing.
      setState(() => _applied.remove(p.id));
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Widget _bubble(ChatMessage m, Palette colors) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF3DEBA8).withValues(alpha: 0.13)
              : colors.card,
          border: Border.all(
              color: isUser ? Colors.transparent : colors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text,
                style: sans(size: 14, color: colors.text, height: 1.45)),
            if (m.question != null && m.question!.options.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in m.question!.options)
                    GestureDetector(
                      onTap: _busy ? null : () => _send(o),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3DEBA8).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(o,
                            style: sans(
                                size: 12.5,
                                weight: FontWeight.w600,
                                color: const Color(0xFF3DEBA8))),
                      ),
                    ),
                ],
              ),
            ],
            if (m.proposal != null) ...[
              const SizedBox(height: 12),
              _proposalCard(m.proposal!, colors),
            ],
            if (m.tools.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in m.tools.toSet())
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.elevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(t.replaceAll('_', ' '),
                          style: mono(size: 10, color: colors.sub)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The confirmation card. Nothing has been written when this appears.
  ///
  /// An edit or a delete shows what is being replaced or removed, not only
  /// what it becomes: the risk with those is not the write itself but
  /// approving one without seeing what it overwrites.
  Widget _proposalCard(AgentProposal p, Palette colors) {
    final done = _applied.contains(p.id);
    final cancelled = _dismissed.contains(p.id);
    final tone = p.isDelete ? const Color(0xFFFF5C7A) : const Color(0xFF3DEBA8);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.elevated,
        border: Border.all(color: tone.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                p.isDelete
                    ? Icons.delete_outline
                    : p.isEdit
                        ? Icons.edit_outlined
                        : Icons.add_circle_outline,
                size: 15,
                color: tone,
              ),
              const SizedBox(width: 7),
              Text(
                p.isDelete
                    ? 'Delete this entry?'
                    : p.isEdit
                        ? 'Change this entry?'
                        : 'Add this entry?',
                style: sans(
                    size: 13, weight: FontWeight.w700, color: colors.text),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (p.isEdit && p.changes.isNotEmpty)
            for (final c in p.changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(c,
                    style: mono(size: 12.5, color: colors.text)),
              )
          else
            Text(p.summary,
                style: mono(
                    size: 13.5, weight: FontWeight.w700, color: colors.text)),

          if (p.isDelete && p.before.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${p.before['note'] ?? ''} · ${p.before['category'] ?? ''}',
              style: sans(size: 12, color: colors.sub),
            ),
          ],

          for (final w in p.warnings) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 13, color: Color(0xFFFFB547)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(w,
                      style:
                          sans(size: 11.5, color: const Color(0xFFFFB547))),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),
          if (cancelled)
            Row(
              children: [
                Icon(Icons.close, size: 15, color: colors.sub),
                const SizedBox(width: 7),
                Text('Cancelled', style: sans(size: 13, color: colors.sub)),
              ],
            )
          else if (done)
            Row(
              children: [
                Icon(Icons.check_circle, size: 15, color: tone),
                const SizedBox(width: 7),
                Text(p.isDelete ? 'Deleted' : 'Saved',
                    style: sans(
                        size: 13, weight: FontWeight.w600, color: tone)),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _apply(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(p.actionLabel,
                            style: sans(
                                size: 13,
                                weight: FontWeight.w700,
                                color: tone)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() => _dismissed.add(p.id));
                    _persist();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.inputBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Cancel',
                        style: sans(size: 13, color: colors.sub)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _thinking(Palette colors) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF3DEBA8)),
            ),
            const SizedBox(width: 10),
            Text('Looking through your entries…',
                style: sans(size: 13, color: colors.sub)),
          ],
        ),
      ),
    );
  }

  Widget _composer(Palette colors) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: ContentWidth(
        maxWidth: 760,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                onSubmitted: _send,
                textInputAction: TextInputAction.send,
                style: sans(size: 14, color: colors.text),
                cursorColor: const Color(0xFF3DEBA8),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Ask about your money…',
                  hintStyle: sans(size: 14, color: colors.muted),
                  filled: true,
                  fillColor: colors.inputBg,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.inputBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.inputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF3DEBA8)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _send(_input.text),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: _busy ? null : Brand.addButton,
                  color: _busy ? colors.inputBg : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.arrow_upward,
                  size: 19,
                  color: _busy ? colors.muted : const Color(0xFF0B0D14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The list of saved conversations, in the manner of Claude or ChatGPT: a
/// permanent column beside the chat on a desktop, a drawer on a phone.
///
/// Only the [kMaxChats] most recent are kept, so starting another quietly
/// removes the one that has gone longest without being used.
class _ChatSidebar extends StatelessWidget {
  const _ChatSidebar({
    required this.currentId,
    required this.busy,
    required this.inDrawer,
    required this.onNew,
    required this.onOpen,
    required this.onDelete,
  });

  final String? currentId;
  final bool busy;

  /// A drawer has to close itself once a choice is made; a sidebar stays put.
  final bool inDrawer;

  final VoidCallback onNew;
  final void Function(ChatSession) onOpen;
  final void Function(String id) onDelete;

  static String _ago(DateTime? t) {
    if (t == null) return 'just now';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return fmtDateShort(dateKeyOf(t));
  }

  void _closeDrawer(BuildContext context) {
    if (inDrawer) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final chats = context.watch<AppState>().chats;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: GestureDetector(
              onTap: busy
                  ? null
                  : () {
                      _closeDrawer(context);
                      onNew();
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  gradient: busy ? null : Brand.addButton,
                  color: busy ? colors.inputBg : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add,
                        size: 18,
                        color: busy ? colors.muted : const Color(0xFF0B0D14)),
                    const SizedBox(width: 6),
                    Text('New chat',
                        style: sans(
                            size: 13.5,
                            weight: FontWeight.w700,
                            color:
                                busy ? colors.muted : const Color(0xFF0B0D14))),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Text('RECENT',
                style: label(colors.sub)),
          ),
          Expanded(
            child: chats.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Your conversations will appear here.',
                        style: sans(size: 12.5, color: colors.sub, height: 1.4)),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    children: [
                      for (final c in chats)
                        _row(context, colors, c, c.id == currentId),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            child: Text(
              'The $kMaxChats most recent chats are kept.',
              style: sans(size: 11.5, color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Palette colors, ChatSession c, bool current) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: busy
            ? null
            : () {
                _closeDrawer(context);
                onOpen(c);
              },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
          decoration: BoxDecoration(
            color: current
                ? const Color(0xFF3DEBA8).withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(
                            size: 13.5,
                            weight: current ? FontWeight.w700 : FontWeight.w500,
                            color: colors.text)),
                    const SizedBox(height: 2),
                    Text(_ago(c.updatedAt),
                        style: sans(size: 11, color: colors.sub)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete chat',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : () => onDelete(c.id),
                icon: Icon(Icons.delete_outline, size: 18, color: colors.sub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
