// Pure data tests for [MultiStreamState] and [MultiStreamSlot]. These
// don't depend on Riverpod or media engine — fast unit-grade.

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/multistream/multi_stream_state.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Channel ch(String suffix) => Channel(
        id: 'src::$suffix',
        sourceId: 'src',
        name: 'Channel $suffix',
        streamUrl: 'http://stream.test/$suffix',
        kind: ChannelKind.live,
      );

  MultiStreamSlot slotFor(String suffix) => MultiStreamSlot(
        channel: ch(suffix),
        source: MediaSource(url: 'http://stream.test/$suffix'),
      );

  group('MultiStreamState defaults', () {
    test('default has empty slot list and active=0', () {
      const state = MultiStreamState();
      expect(state.slots, isEmpty);
      expect(state.activeSlotIndex, 0);
      expect(state.masterMuted, isFalse);
    });

    test('isFull is false until 4 slots', () {
      var s = const MultiStreamState();
      for (var i = 0; i < 4; i++) {
        expect(s.isFull, isFalse);
        s = s.copyWith(slots: <MultiStreamSlot>[
          ...s.slots,
          slotFor('$i'),
        ]);
      }
      expect(s.isFull, isTrue);
    });

    test('isFull is true at slot count == kMaxSlots', () {
      final s = MultiStreamState(
        slots: <MultiStreamSlot>[
          slotFor('a'),
          slotFor('b'),
          slotFor('c'),
          slotFor('d'),
        ],
      );
      expect(s.isFull, isTrue);
      expect(MultiStreamState.kMaxSlots, 4);
    });
  });

  group('safeActiveIndex / activeSlot', () {
    test('returns 0 for empty slots', () {
      const s = MultiStreamState();
      expect(s.safeActiveIndex, 0);
      expect(s.activeSlot, isNull);
    });

    test('clamps over-large index to last slot', () {
      final s = MultiStreamState(
        slots: <MultiStreamSlot>[slotFor('a'), slotFor('b')],
        activeSlotIndex: 50,
      );
      expect(s.safeActiveIndex, 1);
      expect(s.activeSlot!.channel.id, 'src::b');
    });

    test('clamps negative index to 0', () {
      final s = MultiStreamState(
        slots: <MultiStreamSlot>[slotFor('a'), slotFor('b')],
        activeSlotIndex: -3,
      );
      expect(s.safeActiveIndex, 0);
      expect(s.activeSlot!.channel.id, 'src::a');
    });

    test('valid index is returned verbatim', () {
      final s = MultiStreamState(
        slots: <MultiStreamSlot>[slotFor('a'), slotFor('b'), slotFor('c')],
        activeSlotIndex: 2,
      );
      expect(s.safeActiveIndex, 2);
      expect(s.activeSlot!.channel.id, 'src::c');
    });
  });

  group('copyWith', () {
    test('replaces slots only', () {
      const initial = MultiStreamState();
      final next = initial.copyWith(slots: <MultiStreamSlot>[slotFor('x')]);
      expect(next.slots, hasLength(1));
      expect(next.activeSlotIndex, 0);
      expect(next.masterMuted, isFalse);
    });

    test('replaces masterMuted only', () {
      const initial = MultiStreamState();
      final next = initial.copyWith(masterMuted: true);
      expect(next.masterMuted, isTrue);
      expect(next.slots, isEmpty);
    });
  });

  group('MultiStreamSlot equality', () {
    test('equal when channel id + source url match', () {
      final a = slotFor('one');
      final b = slotFor('one');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when channel id differs', () {
      expect(slotFor('one'), isNot(equals(slotFor('two'))));
    });
  });

  group('allSources', () {
    test('returns the primary source first when no fallbacks', () {
      final slot = slotFor('one');
      expect(slot.allSources, hasLength(1));
      expect(slot.allSources.first.url, slot.source.url);
    });

    test('returns primary then fallbacks in order', () {
      final slot = MultiStreamSlot(
        channel: ch('two'),
        source: const MediaSource(url: 'http://primary'),
        fallbacks: const <MediaSource>[
          MediaSource(url: 'http://fallback-1'),
          MediaSource(url: 'http://fallback-2'),
        ],
      );
      expect(slot.allSources.map((MediaSource m) => m.url),
          <String>['http://primary', 'http://fallback-1', 'http://fallback-2']);
    });
  });
}
