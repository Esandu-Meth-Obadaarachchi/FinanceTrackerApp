import '../services/ai_service.dart';

/// Conversations kept per user. Creating one past this deletes the least
/// recently updated, so the list never grows and old chats age out on their own.
const kMaxChats = 5;

/// Messages kept per conversation. A Firestore document tops out at 1 MiB, and
/// a chat that long has stopped being useful context to the model anyway.
const kMaxChatMessages = 100;

/// One turn in a saved conversation.
class ChatMessage {
  const ChatMessage(
    this.role,
    this.text, {
    this.tools = const [],
    this.provider = '',
    this.question,
    this.proposal,
  });

  final String role; // user | assistant
  final String text;
  final List<String> tools;
  final String provider;

  /// Set when the agent asked something back.
  final AgentQuestion? question;

  /// Set when the agent wanted to write. Nothing is saved until Apply.
  final AgentProposal? proposal;

  Map<String, dynamic> toMap() => {
        'role': role,
        'text': text,
        'tools': tools,
        'provider': provider,
        if (question != null) 'question': question!.toJson(),
        if (proposal != null) 'proposal': proposal!.toJson(),
      };

  factory ChatMessage.fromMap(Map<String, dynamic> m) {
    final q = m['question'];
    final p = m['proposal'];
    return ChatMessage(
      m['role'] as String? ?? 'assistant',
      m['text'] as String? ?? '',
      tools: [for (final t in (m['tools'] as List? ?? [])) t.toString()],
      provider: m['provider'] as String? ?? '',
      question: q is Map ? AgentQuestion.fromJson(q.cast<String, dynamic>()) : null,
      proposal: p is Map ? AgentProposal.fromJson(p.cast<String, dynamic>()) : null,
    );
  }
}

/// A saved assistant conversation: `users/{uid}/chats/{chatId}`.
///
/// Carries everything needed to pick the conversation up exactly where it was:
/// the agent's echoed [state] (a half-finished clarification), and which
/// proposal cards were applied or cancelled, so reopening a chat never offers
/// a second Apply on something already saved.
class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    this.state = const {},
    this.applied = const {},
    this.dismissed = const {},
    this.updatedAt,
  });

  final String id;
  final String title;
  final List<ChatMessage> messages;
  final Map<String, dynamic> state;
  final Set<String> applied;
  final Set<String> dismissed;

  /// Server-set. Null only for a write that has not reached the server yet.
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() {
    final kept = messages.length > kMaxChatMessages
        ? messages.sublist(messages.length - kMaxChatMessages)
        : messages;
    return {
      'title': title,
      'messages': [for (final m in kept) m.toMap()],
      'state': state,
      'applied': applied.toList(),
      'dismissed': dismissed.toList(),
    };
  }

  factory ChatSession.fromMap(
      String id, Map<String, dynamic> m, DateTime? updatedAt) {
    return ChatSession(
      id: id,
      title: m['title'] as String? ?? 'Chat',
      messages: [
        for (final x in (m['messages'] as List? ?? []))
          if (x is Map) ChatMessage.fromMap(x.cast<String, dynamic>()),
      ],
      state: (m['state'] as Map?)?.cast<String, dynamic>() ?? const {},
      applied: {for (final a in (m['applied'] as List? ?? [])) a.toString()},
      dismissed: {for (final d in (m['dismissed'] as List? ?? [])) d.toString()},
      updatedAt: updatedAt,
    );
  }
}

/// A short list title taken from the opening question.
String chatTitleFrom(String firstUserMessage, {int max = 40}) {
  final t = firstUserMessage.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return 'New chat';
  return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
}

/// Which saved chats to delete so that adding one more stays within [max].
///
/// Least recently *updated* goes first, not oldest created: a conversation
/// still in use should never be the one that ages out. A chat with no
/// timestamp yet is a write still in flight, so it counts as the newest.
List<String> chatIdsToEvict(List<ChatSession> existing, {int max = kMaxChats}) {
  final excess = existing.length - (max - 1);
  if (excess <= 0) return const [];
  final sorted = [...existing]..sort((a, b) {
      final x = a.updatedAt, y = b.updatedAt;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
  return [for (final c in sorted.take(excess)) c.id];
}
