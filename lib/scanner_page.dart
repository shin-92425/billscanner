import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vision/flutter_vision.dart' show Detection, YoloResult;

import 'app_config.dart';
import 'bill_detector.dart';
import 'bill_info.dart';
import 'detection_painter.dart';
import 'setup_help.dart';
import 'stable_vote.dart';

/// The one and only screen: live camera + detection overlay + result card.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  final BillDetector _detector = BillDetector();
  final StableVote _vote = StableVote(
    windowSize: AppConfig.voteWindow,
    votesNeeded: AppConfig.votesNeeded,
  );

  // These update on every frame, so they use notifiers instead of setState
  // (only the overlay / result card rebuild, not the whole screen).
  final ValueNotifier<ScanFrame?> _frame = ValueNotifier<ScanFrame?>(null);
  final ValueNotifier<VoteResult?> _confirmed =
      ValueNotifier<VoteResult?>(null);
  final ValueNotifier<double> _fps = ValueNotifier<double>(0);

  CameraController? _controller;
  bool _loading = true;
  bool _starting = false;
  bool _modelProblem = false;
  bool _torchOn = false;
  bool _disposed = false;
  String? _error;
  String? _lastAnnounced;

  int _frameCount = 0;
  final Stopwatch _fpsWatch = Stopwatch();

  // ---------------------------------------------------------------- lifecycle

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    _shutdown(controller);
    _frame.dispose();
    _confirmed.dispose();
    _fps.dispose();
    super.dispose();
  }

  Future<void> _shutdown(CameraController? controller) async {
    try {
      if (controller != null) {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        await controller.dispose();
      }
    } catch (_) {
      // Nothing useful to do while shutting down.
    }
    await _detector.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    final isBackground = state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    if (isBackground) {
      // Release the camera when the app is not visible.
      if (_controller?.value.isInitialized == true) _stopCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_starting && !_modelProblem && _error == null) {
        _startCamera();
      }
    }
  }

  // ------------------------------------------------------------------- setup

  Future<void> _init() async {
    if (!_detector.isLoaded) {
      try {
        await _detector.load();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _modelProblem = true;
          _error = e.toString();
        });
        return;
      }
    }
    await _startCamera();
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
      _modelProblem = false;
    });
    _init();
  }

  Future<void> _startCamera() async {
    if (_starting || _controller != null || _disposed) return;
    _starting = true;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('no_camera', 'No camera was found on this device.');
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup:
            Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize(); // asks for camera permission if needed

      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream(_onFrame);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      _controller = null;
      try {
        await controller?.dispose();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyCameraError(e);
      });
    } finally {
      _starting = false;
    }
  }

  Future<void> _stopCamera() async {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    if (mounted) setState(() => _torchOn = false);
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    } catch (_) {}
    if (_disposed) return;
    _vote.reset();
    _frame.value = null;
    _confirmed.value = null;
    _lastAnnounced = null;
  }

  String _friendlyCameraError(Object e) {
    if (e is CameraException) {
      if (e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted') {
        return 'Camera permission was denied. Allow camera access for this '
            'app in the phone Settings, then tap Try again.';
      }
      return 'Camera error: ${e.description ?? e.code}';
    }
    return 'Could not start the camera: $e';
  }

  // --------------------------------------------------------------- detection

  Future<void> _onFrame(CameraImage image) async {
    final controller = _controller;
    if (controller == null || _disposed) return;

    try {
      final result = await _detector.detect(image, controller);
      if (result == null || _disposed) return; // null = frame skipped
      _updateFps();
      _handleResult(result);
    } catch (e) {
      // One bad frame (or the model closing while a frame runs) must not
      // crash the app.
      debugPrint('Frame skipped: $e');
    }
  }

  void _handleResult(YoloResult result) {
    final imageArea = result.imageSize.width * result.imageSize.height;

    // With one bill at a time we only care about the most confident box.
    Detection? best;
    for (final d in result.detections) {
      if (d.confidence < AppConfig.minConfidence) continue;
      final double ratio =
          imageArea <= 0 ? 0.0 : (d.box.width * d.box.height) / imageArea;
      if (ratio < AppConfig.minBoxAreaRatio) continue;
      if (best == null || d.confidence > best.confidence) best = d;
    }

    final vote = _vote.add(
      best == null ? null : VoteObservation(best.label, best.confidence),
    );

    if (vote != null && vote.label != _lastAnnounced) {
      _lastAnnounced = vote.label;
      HapticFeedback.mediumImpact();
    } else if (vote == null && best == null) {
      _lastAnnounced = null;
    }

    _frame.value = ScanFrame(imageSize: result.imageSize, best: best);
    _confirmed.value = vote;
  }

  void _updateFps() {
    _frameCount++;
    if (!_fpsWatch.isRunning) _fpsWatch.start();
    final ms = _fpsWatch.elapsedMilliseconds;
    if (ms >= 1000) {
      _fps.value = _frameCount * 1000 / ms;
      _frameCount = 0;
      _fpsWatch
        ..reset()
        ..start();
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flashlight is not available on this camera.')),
      );
    }
  }

  // ---------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.black, body: _buildBody());
  }

  Widget _buildBody() {
    if (_modelProblem) {
      return SetupHelp(error: _error ?? 'Unknown error', onRetry: _retry);
    }
    if (_error != null) {
      return SafeArea(child: _message(_error!));
    }

    final controller = _controller;
    if (_loading || controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    // The preview size is reported in landscape; the UI is portrait-only,
    // so use the smaller side as the width.
    final previewSize = controller.value.previewSize!;
    final w = math.min(previewSize.width, previewSize.height);
    final h = math.max(previewSize.width, previewSize.height);

    return Stack(
      fit: StackFit.expand,
      children: [
        // BoxFit.cover here must match BoxFit.cover in DetectionPainter.
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: w,
              height: h,
              child: CameraPreview(controller),
            ),
          ),
        ),
        Positioned.fill(
          child: ValueListenableBuilder<ScanFrame?>(
            valueListenable: _frame,
            builder: (context, frame, _) => CustomPaint(
              painter: DetectionPainter(frame),
            ),
          ),
        ),
        _topBar(),
        Align(alignment: Alignment.bottomCenter, child: _resultCard()),
      ],
    );
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _retry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const _Chip(text: 'Bill Scanner'),
              const Spacer(),
              ValueListenableBuilder<double>(
                valueListenable: _fps,
                builder: (context, fps, _) => _Chip(
                  text: '${_detector.accelerator} \u00B7 ${fps.toStringAsFixed(0)} fps',
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Flashlight',
                onPressed: _toggleTorch,
                icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultCard() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<VoteResult?>(
          valueListenable: _confirmed,
          builder: (context, vote, _) {
            if (vote == null) {
              return const _ResultCard(
                color: Color(0xFF263238),
                title: 'Point the camera at a bill',
                subtitle:
                    'Hold it flat and fill most of the frame. Good light helps.',
              );
            }
            final info = billInfoFor(vote.label);
            return _ResultCard(
              color: info.color,
              title: '${info.symbol}  ${info.name}',
              subtitle: '${(vote.confidence * 100).round()}% confident',
            );
          },
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final fg = color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    // liveRegion: screen readers (TalkBack) announce the new result.
    return Semantics(
      liveRegion: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: fg,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
