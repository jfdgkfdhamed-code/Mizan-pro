import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Result shown on the camera scanner after each scan.
class ScanFeedback {
  final String text;
  final bool ok;

  /// Close the scanner page afterwards (e.g. to go and fix the stock).
  final bool close;
  const ScanFeedback(this.text, this.ok, {this.close = false});
}

/// Listens to a USB / Bluetooth barcode scanner.
///
/// Such scanners behave like a keyboard: they "type" the digits very fast and press
/// Enter. A human typing is much slower, so keys arriving less than [maxGapMs]
/// apart and ending with Enter are treated as a scan. Normal typing is never blocked.
class UsbScannerListener {
  final bool Function() isEnabled;
  final void Function(String code) onScan;
  final int maxGapMs;
  final int minLength;

  UsbScannerListener({
    required this.isEnabled,
    required this.onScan,
    this.maxGapMs = 120,
    this.minLength = 4,
  });

  final StringBuffer _buf = StringBuffer();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void attach() => HardwareKeyboard.instance.addHandler(_handle);
  void detach() => HardwareKeyboard.instance.removeHandler(_handle);

  bool _handle(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    if (!isEnabled()) {
      _buf.clear();
      return false;
    }
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds > maxGapMs) _buf.clear();
    _last = now;

    if (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _buf.toString();
      _buf.clear();
      if (code.length >= minLength) {
        onScan(code);
        return true; // it was a scan, not a normal "Enter" key press
      }
      return false;
    }
    final ch = e.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32) {
      _buf.write(ch);
    }
    return false;
  }
}

/// Phone-camera barcode scanner page.
///
/// * [onCode] == null  -> single scan: the page closes and returns the code.
/// * [onCode] != null  -> continuous scan (used by the POS): the page stays open,
///   every code is handled by [onCode] and its feedback is shown at the bottom.
class BarcodeScannerPage extends StatefulWidget {
  final String title;
  final Future<ScanFeedback?> Function(BuildContext context, String code)? onCode;
  final Widget? footer;

  const BarcodeScannerPage({
    super.key,
    required this.title,
    this.onCode,
    this.footer,
  });

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 400,
  );

  bool _busy = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  ScanFeedback? _feedback;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Restarts the camera (useful right after the permission was just granted).
  Future<void> _retry() async {
    try {
      await _controller.stop();
    } catch (_) {}
    try {
      await _controller.start();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    String? code;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        code = v.trim();
        break;
      }
    }
    if (code == null) return;

    final handler = widget.onCode;
    if (handler == null) {
      _busy = true;
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, code);
      return;
    }

    // Continuous mode: ignore the same code if it is still in front of the camera.
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt).inMilliseconds < 1800) return;
    _lastCode = code;
    _lastAt = now;

    _busy = true;
    HapticFeedback.mediumImpact();
    ScanFeedback? fb;
    try {
      fb = await handler(context, code);
    } finally {
      _busy = false;
      _lastAt = DateTime.now();
    }
    if (!mounted) return;
    setState(() => _feedback = fb);
    if (fb != null && fb.close) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fb = _feedback;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'الفلاش',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Align(
              alignment: const Alignment(0, -0.75),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'تعذر تشغيل الكاميرا',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    // The real reason, so it can be diagnosed.
                    Text(
                      'رمز الخطأ: ${error.errorCode.name}'
                      '${(error.errorDetails?.message ?? '').isEmpty ? '' : '\n${error.errorDetails!.message}'}',
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          color: Colors.amberAccent, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'إذا منحت الإذن للتو فاضغط «إعادة المحاولة».\n'
                      'وإلا افتح إعدادات الهاتف ← التطبيقات ← الميزان برو ← الأذونات ← الكاميرا.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, height: 1.6, fontSize: 12.5),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Aiming frame
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 3),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fb != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: fb.ok ? Colors.green.shade700 : Colors.red.shade700,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(fb.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  if (widget.footer != null) widget.footer!,
                  if (widget.onCode == null)
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('وجّه الكاميرا نحو الباركود',
                          style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
