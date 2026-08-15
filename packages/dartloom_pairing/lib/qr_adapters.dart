import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'pairing_contracts.dart';

class FlutterQrCodePresenter implements QrPresenter {
  FlutterQrCodePresenter(this.context);

  final BuildContext context;

  @override
  Future<void> show(String invitation) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pair device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: invitation, size: 240),
            const SizedBox(height: 12),
            SelectableText(invitation),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class MobileScannerQrScanner implements QrScanner {
  MobileScannerQrScanner(this.context);

  final BuildContext context;

  @override
  Future<String?> scan() async {
    if (!context.mounted) return null;
    final result = Completer<String?>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scan pairing QR'),
        content: SizedBox(
          width: 320,
          height: 320,
          child: MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.isNotEmpty) {
                  if (!result.isCompleted) result.complete(value);
                  Navigator.of(dialogContext).pop();
                  return;
                }
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!result.isCompleted) result.complete(null);
    return result.future;
  }
}
