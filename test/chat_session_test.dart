// Saved assistant conversations: round-tripping and the five-chat limit.

import 'package:financialtracker/models/chat_session.dart';
import 'package:financialtracker/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

ChatSession chat(String id, {DateTime? at, int messages = 1}) => ChatSession(
      id: id,
      title: id,
      messages: [for (var i = 0; i < messages; i++) ChatMessage('user', 'm$i')],
      updatedAt: at,
    );

DateTime day(int d) => DateTime(2026, 11, d);

void main() {
  group('round trip', () {
    test('a proposal card survives being saved and reloaded', () {
      const proposal = AgentProposal(
        id: 'prop_1',
        kind: 'add_transaction',
        fields: {'amount': 5000.0, 'accountId': 'a2'},
        summary: 'Rs 5,000 · Employment Income · Cash',
        warnings: ['Looks like a duplicate'],
      );
      final saved = ChatSession(
        id: 'c1',
        title: 'Add salary',
        messages: const [
          ChatMessage('user', 'add 5000 salary'),
          ChatMessage('assistant', 'Check these details',
              tools: ['get_accounts'], provider: 'anthropic', proposal: proposal),
        ],
        state: const {'pending': {'field': 'account'}},
        applied: const {'prop_1'},
        dismissed: const {'prop_0'},
      );

      final back = ChatSession.fromMap('c1', saved.toMap(), day(1));
      final card = back.messages[1].proposal!;

      expect(card.id, 'prop_1');
      expect(card.fields['amount'], 5000.0);
      expect(card.warnings, ['Looks like a duplicate']);
      expect(back.messages[1].tools, ['get_accounts']);
      expect(back.applied, {'prop_1'});
      expect(back.dismissed, {'prop_0'});
      expect(back.state['pending'], {'field': 'account'});
    });

    test('a clarification keeps its tappable options', () {
      final saved = ChatSession(
        id: 'c1',
        title: 't',
        messages: const [
          ChatMessage('assistant', 'Which account?',
              question: AgentQuestion(
                  text: 'Which account?', options: ['Cash', 'Bank'], field: 'account')),
        ],
      );
      final q = ChatSession.fromMap('c1', saved.toMap(), null)
          .messages
          .single
          .question!;
      expect(q.options, ['Cash', 'Bank']);
      expect(q.field, 'account');
    });

    test('a half-written document loads instead of throwing', () {
      final s = ChatSession.fromMap('c1', const {}, null);
      expect(s.messages, isEmpty);
      expect(s.applied, isEmpty);
    });

    test('only the most recent messages are stored', () {
      final long = chat('c1', messages: kMaxChatMessages + 25);
      final stored = long.toMap()['messages'] as List;
      expect(stored.length, kMaxChatMessages);
      // The oldest were dropped, not the newest.
      expect((stored.last as Map)['text'], 'm${kMaxChatMessages + 24}');
    });
  });

  group('chatIdsToEvict', () {
    test('under the limit nothing is deleted', () {
      final four = [for (var i = 1; i <= 4; i++) chat('c$i', at: day(i))];
      expect(chatIdsToEvict(four), isEmpty);
    });

    test('at the limit the least recently updated goes', () {
      final five = [
        chat('c3', at: day(3)),
        chat('c1', at: day(1)),
        chat('c5', at: day(5)),
        chat('c2', at: day(2)),
        chat('c4', at: day(4)),
      ];
      expect(chatIdsToEvict(five), ['c1']);
    });

    test('a chat kept in use outlives one created later but left alone', () {
      // c1 was created first but updated last, so c2 is the stale one.
      final five = [
        chat('c1', at: day(20)),
        chat('c2', at: day(2)),
        chat('c3', at: day(3)),
        chat('c4', at: day(4)),
        chat('c5', at: day(5)),
      ];
      expect(chatIdsToEvict(five), ['c2']);
    });

    test('an unsynced chat counts as the newest and is never evicted first', () {
      final five = [
        chat('pending'),
        chat('c1', at: day(1)),
        chat('c2', at: day(2)),
        chat('c3', at: day(3)),
        chat('c4', at: day(4)),
      ];
      expect(chatIdsToEvict(five), ['c1']);
    });

    test('over the limit trims enough to leave room for one more', () {
      final seven = [for (var i = 1; i <= 7; i++) chat('c$i', at: day(i))];
      expect(chatIdsToEvict(seven), ['c1', 'c2', 'c3']);
    });
  });

  group('chatTitleFrom', () {
    test('long openers are shortened with an ellipsis', () {
      final t = chatTitleFrom('How much did I spend on food and groceries this month?');
      expect(t.length, lessThanOrEqualTo(40));
      expect(t.endsWith('…'), isTrue);
    });

    test('whitespace is collapsed and blanks get a fallback', () {
      expect(chatTitleFrom('  add   salary \n 5000 '), 'add salary 5000');
      expect(chatTitleFrom('   '), 'New chat');
    });
  });
}
