import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';

class ScanGymQrScreen extends StatefulWidget {
  const ScanGymQrScreen({super.key});

  @override
  State<ScanGymQrScreen> createState() => _ScanGymQrScreenState();
}

class _ScanGymQrScreenState extends State<ScanGymQrScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _extractCode(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    final code =
        uri?.queryParameters['gym_code'] ??
        uri?.queryParameters['gymCode'] ??
        uri?.queryParameters['code'];

    if (code != null && code.trim().isNotEmpty) {
      return code.trim().toUpperCase();
    }

    return value.toUpperCase();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    final code = _extractCode(raw);
    if (code == null) return;

    _handled = true;
    context.pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: Stack(
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Positioned(
              left: 18,
              top: 18,
              child: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(18),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appStrings.scanGymQr.toUpperCase(),
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      appStrings.scanGymQrMessage,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary(context),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
