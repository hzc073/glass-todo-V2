import 'dart:async';

class TimeTrackingRefreshBus {
  TimeTrackingRefreshBus._();

  static final TimeTrackingRefreshBus instance = TimeTrackingRefreshBus._();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;

  void notify() {
    if (_controller.isClosed) return;
    _controller.add(null);
  }
}

