/// Settings you can tweak while testing the app.
class AppConfig {
  AppConfig._();

  /// Files in the assets/ folder (created by the training notebook).
  static const String modelAsset = 'assets/model.tflite';
  static const String labelsAsset = 'assets/labels.txt';

  /// Detections below this confidence (0..1) are ignored.
  /// Raise it if you get false detections, lower it if real bills are missed.
  static const double minConfidence = 0.80;

  /// Ignore tiny boxes: the box must cover at least this fraction of the
  /// camera image. Stops far-away objects from being read as a bill.
  static const double minBoxAreaRatio = 0.05;

  /// Frame voting: a result is only shown once the same denomination wins
  /// [votesNeeded] of the last [voteWindow] frames. This removes flicker.
  static const int voteWindow = 8;
  static const int votesNeeded = 5;
}
