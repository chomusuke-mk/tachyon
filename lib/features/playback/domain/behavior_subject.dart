import 'dart:async';

/// A pure Dart broadcast stream that holds the current value and delivers it
/// immediately to new listeners upon subscription (Replay-1 semantics).
///
/// Provides a zero-dependency broadcast subject compatible with standard
/// Dart [Stream] contracts.
class BehaviorSubject<T> extends Stream<T> {
  T _value;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  BehaviorSubject(T initialValue) : _value = initialValue;

  /// Synchronously returns the most recently emitted value.
  T get value => _value;

  /// Emits a new event to all active listeners and updates [value].
  void add(T event) {
    if (_controller.isClosed) return;
    _value = event;
    _controller.add(event);
  }

  /// Emits an error event to active listeners.
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_controller.isClosed) return;
    _controller.addError(error, stackTrace);
  }

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controllerSub = _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    final wrapper = _BehaviorSubjectSubscription<T>(controllerSub, onData);

    if (onData != null) {
      scheduleMicrotask(() {
        if (!_controller.isClosed && !wrapper.isCancelled) {
          wrapper._onData?.call(_value);
        }
      });
    }
    return wrapper;
  }

  /// Closes the internal StreamController.
  Future<void> close() => _controller.close();

  /// Whether the stream controller is closed.
  bool get isClosed => _controller.isClosed;
}

class _BehaviorSubjectSubscription<T> implements StreamSubscription<T> {
  final StreamSubscription<T> _sub;
  bool isCancelled = false;
  void Function(T event)? _onData;

  _BehaviorSubjectSubscription(this._sub, this._onData);

  @override
  Future<void> cancel() {
    isCancelled = true;
    return _sub.cancel();
  }

  @override
  void onData(void Function(T data)? handleData) {
    _onData = handleData;
    _sub.onData(handleData);
  }

  @override
  void onError(Function? handleError) => _sub.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _sub.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _sub.pause(resumeSignal);

  @override
  void resume() => _sub.resume();

  @override
  bool get isPaused => _sub.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _sub.asFuture(futureValue);
}
