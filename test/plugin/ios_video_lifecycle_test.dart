import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/utils/ios_video_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

class _Player {
  bool playing = true;
  String track = '2';
  final calls = <String>[];
  final errors = <Object>[];
  Completer<void>? pauseGate;
  Completer<void>? detachGate;
  bool failRestore = false;

  late final lifecycle = IOSVideoLifecycle(
    isPlaying: () => playing,
    videoTrack: () => track,
    setPlaying: (value) async {
      calls.add(value ? 'play' : 'pause');
      playing = value;
      if (!value) await pauseGate?.future;
    },
    setVideoTrack: (value) async {
      calls.add('video:$value');
      if (failRestore && value != 'no') throw StateError('restore failed');
      track = value;
      if (value == 'no') await detachGate?.future;
    },
    onError: (error, stack) => errors.add(error),
  );

  Future<void> background({
    bool pause = true,
    bool releaseVideo = true,
    bool pip = false,
  }) => lifecycle.suspend(
    pausePlayback: pause,
    releaseVideo: releaseVideo,
    keepVideo: pip,
  );
}

void main() {
  test(
    'recreates the video track before automatically resuming playback',
    () async {
      final player = _Player();
      await player.background();
      expect(player.playing, isFalse);
      expect(player.track, 'no');

      await player.lifecycle.resume();
      expect(player.track, '2');
      expect(player.playing, isTrue);
      expect(player.calls, ['pause', 'video:no', 'video:2', 'play']);
    },
  );

  test(
    'recreates the decoder for a manually paused video without playing it',
    () async {
      final player = _Player()..playing = false;
      await player.background();
      await player.lifecycle.resume();

      expect(player.track, '2');
      expect(player.playing, isFalse);
      expect(player.calls, ['video:no', 'video:2']);
    },
  );

  test(
    'keeps background audio playing while the video track is released',
    () async {
      final player = _Player();
      await player.background(pause: false);
      expect(player.track, 'no');
      expect(player.playing, isTrue);

      await player.lifecycle.resume();
      expect(player.track, '2');
      expect(player.playing, isTrue);
      expect(player.calls, ['video:no', 'video:2']);
    },
  );

  test('leaves active or armed picture in picture playback alone', () async {
    final player = _Player();
    await player.background(pip: true);
    await player.lifecycle.resume();

    expect(player.track, '2');
    expect(player.playing, isTrue);
    expect(player.calls, isEmpty);
  });

  test('does not change the track when video recovery is disabled', () async {
    final player = _Player();
    await player.background(releaseVideo: false);
    await player.lifecycle.resume();

    expect(player.track, '2');
    expect(player.playing, isTrue);
    expect(player.calls, ['pause', 'play']);
  });

  test('does not enable video for audio only playback', () async {
    final player = _Player()..track = 'no';
    await player.background(pause: false);
    await player.lifecycle.resume();

    expect(player.track, 'no');
    expect(player.calls, isEmpty);
  });

  test(
    'handles repeated background and foreground notifications once',
    () async {
      final player = _Player();
      await Future.wait([
        player.background(),
        player.background(),
        player.background(),
      ]);
      await Future.wait([player.lifecycle.resume(), player.lifecycle.resume()]);

      expect(player.calls, ['pause', 'video:no', 'video:2', 'play']);
    },
  );

  test(
    'does not restore video while a rapid app switch leaves it in background',
    () async {
      final player = _Player()..detachGate = Completer<void>();
      final firstBackground = player.background();
      await Future<void>.delayed(Duration.zero);
      final foreground = player.lifecycle.resume();
      final secondBackground = player.background();
      player.detachGate!.complete();
      await Future.wait([firstBackground, foreground, secondBackground]);

      expect(player.track, 'no');
      expect(player.playing, isFalse);
      expect(player.calls, isNot(contains('play')));

      await player.lifecycle.resume();
      expect(player.track, '2');
      expect(player.playing, isTrue);
    },
  );

  test('does not restore the previous media after a source change', () async {
    final player = _Player()..detachGate = Completer<void>();
    final background = player.background();
    await Future<void>.delayed(Duration.zero);
    player.lifecycle.reset();
    player
      ..track = '7'
      ..playing = false;
    player.detachGate!.complete();
    await background;
    await player.lifecycle.resume();

    expect(player.track, '7');
    expect(player.playing, isFalse);
    expect(player.calls, ['pause', 'video:no']);
  });

  test('cancels a pending transition when the player is disposed', () async {
    final player = _Player()..pauseGate = Completer<void>();
    final background = player.background();
    await Future<void>.delayed(Duration.zero);
    player.lifecycle.dispose();
    player.pauseGate!.complete();
    await background;
    await player.lifecycle.resume();

    expect(player.track, '2');
    expect(player.calls, ['pause']);
    expect(player.errors, isEmpty);
  });

  test(
    'cancels a queued transition before it can affect a new source',
    () async {
      final player = _Player();
      final background = player.background();
      player.lifecycle.reset();
      await background;
      await player.lifecycle.resume();

      expect(player.track, '2');
      expect(player.playing, isTrue);
      expect(player.calls, isEmpty);
    },
  );

  test(
    'reports a restore error and can recover on the next app switch',
    () async {
      final player = _Player()..failRestore = true;
      await player.background();
      await player.lifecycle.resume();
      expect(player.errors, hasLength(1));
      expect(player.playing, isFalse);

      player.failRestore = false;
      await player.background();
      await player.lifecycle.resume();
      expect(player.track, '2');
      expect(player.playing, isTrue);
    },
  );
}
