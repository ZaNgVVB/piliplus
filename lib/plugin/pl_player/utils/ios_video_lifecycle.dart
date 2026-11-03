/// iOS 退到后台前释放视频轨道，避免失效的 VideoToolbox 会话一直回退到软解。
class IOSVideoLifecycle {
  IOSVideoLifecycle({
    required this.isPlaying,
    required this.videoTrack,
    required this.setPlaying,
    required this.setVideoTrack,
    required this.onError,
  });

  final bool Function() isPlaying;
  final String Function() videoTrack;
  final Future<void> Function(bool playing) setPlaying;
  final Future<void> Function(String track) setVideoTrack;
  final void Function(Object error, StackTrace stack) onError;

  Future<void> _pending = Future.value();
  bool _background = false;
  bool _resumePlayback = false;
  String? _videoTrack;
  int _generation = 0;
  bool _disposed = false;

  Future<void> suspend({
    required bool pausePlayback,
    required bool releaseVideo,
    required bool keepVideo,
  }) {
    if (_disposed || _background || keepVideo) return _pending;
    _background = true;
    _resumePlayback |= pausePlayback && isPlaying();
    if (releaseVideo && _videoTrack == null) {
      final track = videoTrack();
      if (track.isNotEmpty && track != 'no') _videoTrack = track;
    }
    return _enqueue(background: true);
  }

  Future<void> resume() {
    if (_disposed || !_background) return _pending;
    _background = false;
    return _enqueue(background: false);
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _enqueue({required bool background}) {
    final generation = _generation;
    return _pending = _pending.then((_) async {
      if (!_isCurrent(generation)) return;
      try {
        if (background) {
          if (_resumePlayback) await setPlaying(false);
          if (!_isCurrent(generation)) return;
          if (_videoTrack != null) await setVideoTrack('no');
        } else {
          if (_background) return;
          if (_videoTrack case final track?) await setVideoTrack(track);
          if (!_isCurrent(generation) || _background) return;
          if (_resumePlayback) await setPlaying(true);
          if (!_isCurrent(generation) || _background) return;
          _videoTrack = null;
          _resumePlayback = false;
        }
      } catch (error, stack) {
        if (_isCurrent(generation)) onError(error, stack);
      }
    });
  }

  /// 换源后不能把上一段视频的轨道和播放状态恢复到新视频。
  void reset() {
    _generation++;
    _background = false;
    _resumePlayback = false;
    _videoTrack = null;
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}
