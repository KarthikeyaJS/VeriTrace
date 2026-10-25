import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/qr_input.dart';

/// Camera QR scanner with torch toggle. Accepts VeriTrace payloads and bare product IDs.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);
  bool _handled = false;
  String? _invalidMessage;
  Timer? _clearTimer;

  @override
  void dispose() {
    _clearTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null) return;
    if (!QrInput.isVeriTrace(raw)) {
      setState(() => _invalidMessage = 'This is not a VeriTrace QR code. Look for the VeriTrace label on the product.');
      _clearTimer?.cancel();
      _clearTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _invalidMessage = null);
      });
      return;
    }
    _handled = true;
    context.pushReplacement(Uri(path: '/verify', queryParameters: {'payload': raw.trim()}).toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan product QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              if (!state.isInitialized || !state.isRunning || state.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: on ? 'Turn torch off' : 'Turn torch on',
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                onPressed: _controller.toggleTorch,
              );
            },
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _CameraError(error: error),
        ),
        const _Viewfinder(),
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_invalidMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: const Color(0xFFFFF4DC), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Color(0xFFB26A00)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_invalidMessage!, style: const TextStyle(color: Colors.black87))),
                ]),
              ),
            const Text('Point the camera at the QR code on the product label', style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.pushReplacement('/'),
              icon: const Icon(Icons.keyboard, color: Colors.white),
              label: const Text('Enter product ID instead', style: TextStyle(color: Colors.white)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white, size: 48),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'Camera permission is needed to scan QR codes. Allow camera access in Settings → Apps → VeriTrace → Permissions, or enter the product ID manually.'
                  : 'The camera could not start (${error.errorCode.name}). You can enter the product ID manually instead.',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ),
    );
  }
}
