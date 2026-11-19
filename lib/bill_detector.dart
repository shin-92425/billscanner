import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart'
    show Accelerator, CameraFrame, FrameFormat, FramePlane, YoloModel, YoloResult;

import 'app_config.dart';

/// Thin wrapper around flutter_vision's YoloModel.
class BillDetector {
  YoloModel? _model;

  bool get isLoaded => _model != null;

  /// The hardware the model really runs on (cpu / gpu / npu).
  String get accelerator => _model == null ? '-' : '${_model!.accelerator}';

  /// Loads assets/model.tflite and assets/labels.txt.
  /// Throws if the files are missing or do not match.
  Future<void> load() async {
    _model = await YoloModel.load(
      modelPath: AppConfig.modelAsset,
      labelsPath: AppConfig.labelsAsset,
      accelerator: Accelerator.gpu, // falls back to CPU automatically
    );
  }

  /// Runs the model on one camera frame.
  /// Returns null if the previous frame is still being processed (the frame
  /// is skipped on purpose to keep the result real time).
  Future<YoloResult?> detect(
    CameraImage image,
    CameraController controller,
  ) async {
    final model = _model;
    if (model == null) return null;

    final camera = controller.description;
    final isAndroid = Platform.isAndroid;

    return model.detectFrame(
      CameraFrame(
        width: image.width,
        height: image.height,
        format: isAndroid ? FrameFormat.nv21 : FrameFormat.bgra8888,
        planes: [
          for (final p in image.planes)
            FramePlane(
              bytes: p.bytes,
              bytesPerRow: p.bytesPerRow,
              bytesPerPixel: p.bytesPerPixel ?? 1,
            ),
        ],
        // Android delivers frames in the sensor orientation; iOS already
        // delivers them upright.
        rotation: isAndroid
            ? CameraFrame.rotationFor(
                sensorOrientation: camera.sensorOrientation,
                deviceOrientation: CameraFrame.degreesFor(
                  controller.value.deviceOrientation.name,
                ),
                frontCamera: camera.lensDirection == CameraLensDirection.front,
              )
            : 0,
      ),
    );
  }

  Future<void> dispose() async {
    final model = _model;
    _model = null;
    await model?.dispose();
  }
}
