// Pure unit tests for [WatchPartyState] and its merge/drop helpers.

import 'package:awatv_mobile/src/features/watch_party/watch_party_state.dart';
import 'package:awatv_mobile/src/shared/remote/remote_channel.dart'
    show RemoteConnectionState;
import 'package:awatv_mobile/src/shared/remote/watch_party_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WatchPartyState.empty', () {
    test('puts the local user in the members list', () {
      final s = WatchPartyState.empty(
        partyId: 'p1',
        localUserId: 'u1',
        localUserName: 'Alex',
        isHost: true,
      );
      expect(s.members, hasLength(1));
      expect(s.members.first.userId, 'u1');
      expect(s.members.first.isHost, isTrue);
    });

    test('starts in connecting state', () {
      final s = WatchPartyState.empty(
        partyId: 'p1',
        localUserId: 'u1',
        localUserName: 'Alex',
        isHost: false,
      );
      expect(s.connection, RemoteConnectionState.connecting);
    });

    test('chat is empty', () {
      final s = WatchPartyState.empty(
        partyId: 'p',
        localUserId: 'u',
        localUserName: 'A',
        isHost: false,
      );
      expect(s.chat, isEmpty);
    });
  });

  group('host getter', () {
    test('returns null when no host present', () {
      const s = WatchPartyState(
        partyId: 'p',
        localUserId: 'u',
        localUserName: 'A',
        isHost: false,
        connection: RemoteConnectionState.connected,
        members: <PartyMember>[
          PartyMember(userId: '1', userName: 'a', isHost: false),
          PartyMember(userId: '2', userName: 'b', isHost: false),
        ],
        chat: <PartyChat>[],
      );
      expect(s.host, isNull);
    });

    test('returns the host member', () {
      const s = WatchPartyState(
        partyId: 'p',
        localUserId: 'u',
        localUserName: 'A',
        isHost: false,
        connection: RemoteConnectionState.connected,
        members: <PartyMember>[
          PartyMember(userId: '1', userName: 'guest', isHost: false),
          PartyMember(userId: 'host', userName: 'H', isHost: true),
        ],
        chat: <PartyChat>[],
      );
      expect(s.host, isNotNull);
      expect(s.host!.userId, 'host');
    });
  });

  group('others getter', () {
    test('excludes the local user', () {
      const s = WatchPartyState(
        partyId: 'p',
        localUserId: 'me',
        localUserName: 'Me',
        isHost: false,
        connection: RemoteConnectionState.connected,
        members: <PartyMember>[
          PartyMember(userId: 'me', userName: 'Me', isHost: false),
          PartyMember(userId: 'other', userName: 'Other', isHost: false),
        ],
        chat: <PartyChat>[],
      );
      expect(s.others.map((PartyMember m) => m.userId), <String>['other']);
    });
  });

  group('canControl', () {
    test('only true when connected', () {
      final connecting = WatchPartyState.empty(
        partyId: 'p',
        localUserId: 'u',
        localUserName: 'A',
        isHost: true,
      );
      expect(connecting.canControl, isFalse);

      final connected = connecting.copyWith(
        connection: RemoteConnectionState.connected,
      );
      expect(connected.canControl, isTrue);
    });
  });

  group('mergeMember', () {
    test('appends a brand-new member', () {
      const existing = <PartyMember>[
        PartyMember(userId: '1', userName: 'A', isHost: true),
      ];
      const newMember = PartyMember(
        userId: '2',
        userName: 'B',
        isHost: false,
      );
      final next = mergeMember(existing, newMember, nowMs: 1234);
      expect(next, hasLength(2));
      expect(next.last.userId, '2');
      expect(next.last.lastSeenMs, 1234);
    });

    test('updates an existing member without duplicating', () {
      const existing = <PartyMember>[
        PartyMember(
          userId: '1',
          userName: 'A',
          isHost: true,
        ),
      ];
      const update = PartyMember(
        userId: '1',
        userName: 'A',
        isHost: true,
        isPlaying: true,
      );
      final next = mergeMember(existing, update, nowMs: 9999);
      expect(next, hasLength(1));
      expect(next.first.isPlaying, isTrue);
      expect(next.first.lastSeenMs, 9999);
    });
  });

  group('dropMember', () {
    test('removes another member by id', () {
      const existing = <PartyMember>[
        PartyMember(userId: '1', userName: 'A', isHost: true),
        PartyMember(userId: '2', userName: 'B', isHost: false),
      ];
      final next = dropMember(existing, '2', localUserId: '1');
      expect(next, hasLength(1));
      expect(next.first.userId, '1');
    });

    test('marks local user offline rather than removing', () {
      const existing = <PartyMember>[
        PartyMember(
          userId: 'me',
          userName: 'Me',
          isHost: true,
        ),
        PartyMember(
          userId: 'other',
          userName: 'O',
          isHost: false,
        ),
      ];
      final next = dropMember(existing, 'me', localUserId: 'me');
      expect(next, hasLength(2));
      final selfRow = next.firstWhere((PartyMember m) => m.userId == 'me');
      expect(selfRow.online, isFalse);
    });

    test('is a no-op when id not present', () {
      const existing = <PartyMember>[
        PartyMember(userId: '1', userName: 'A', isHost: true),
      ];
      final next = dropMember(existing, 'nope', localUserId: '1');
      // Result should match the original list shape.
      expect(next, hasLength(existing.length));
    });
  });

  group('WatchPartyUnavailable', () {
    test('toString includes the reason', () {
      const ex = WatchPartyUnavailable('Premium gerekli');
      expect(ex.toString(), contains('Premium gerekli'));
    });
  });

  group('copyWith', () {
    test('keeps the original when no overrides supplied', () {
      final original = WatchPartyState.empty(
        partyId: 'p',
        localUserId: 'u',
        localUserName: 'A',
        isHost: true,
      );
      final copy = original.copyWith();
      expect(copy.partyId, original.partyId);
      expect(copy.localUserId, original.localUserId);
      expect(copy.connection, original.connection);
    });

    test('updates connection only', () {
      final original = WatchPartyState.empty(
        partyId: 'p',
        localUserId: 'u',
        localUserName: 'A',
        isHost: true,
      );
      final copy = original.copyWith(
        connection: RemoteConnectionState.connected,
      );
      expect(copy.connection, RemoteConnectionState.connected);
      expect(copy.partyId, original.partyId);
    });
  });
}
