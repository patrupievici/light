import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen barcode scan; codul caută produs ambalat în USDA FoodData Central (Branded).
class NutritionBarcodeScanScreen extends StatefulWidget {
  const NutritionBarcodeScanScreen({super.key});

  @override
  State<NutritionBarcodeScanScreen> createState() => _NutritionBarcodeScanScreenState();
}

class _NutritionBarcodeScanScreenState extends State<NutritionBarcodeScanScreen> {
  late final MobileScannerController _controller;
  bool _handled = false;

  static const List<BarcodeFormat> _productFormats = [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
  ];

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: _productFormats,
      detectionSpeed: DetectionSpeed.normal,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    if (capture.barcodes.isEmpty) return;

    for (final b in capture.barcodes) {
      final raw = b.rawValue ?? b.displayValue;
      if (raw == null || raw.isEmpty) continue;
      final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.length < 8) continue;

      _handled = true;
      unawaited(_controller.stop());
      if (mounted) {
        Navigator.of(context).pop<String>(digits);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            tooltip: 'Torch',
            onPressed: () => unawaited(_controller.toggleTorch()),
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (_, state, __) {
                final on = state.torchState == TorchState.on;
                return Icon(on ? AppIcons.bolt : AppIcons.bolt);
              },
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (ctx, err) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    err.errorDetails?.message ?? err.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              color: Colors.black54,
              child: const Text(
                'Point at the product barcode. We search USDA branded foods.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
