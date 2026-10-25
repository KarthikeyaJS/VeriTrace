import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// One printable QR label.
class QrLabel {
  const QrLabel({required this.productId, required this.payload, this.name});
  final String productId;
  final String payload;
  final String? name;
}

/// Renders a white PNG with the QR code plus product ID and name underneath.
Future<Uint8List> renderQrLabelPng(QrLabel label) async {
  const width = 800.0;
  const pad = 48.0;
  const textHeight = 150.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, width, width + textHeight), Paint()..color = Colors.white);

  final qr = QrPainter(
    data: label.payload,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    gapless: true,
  );
  canvas.save();
  canvas.translate(pad, pad);
  qr.paint(canvas, const Size(width - 2 * pad, width - 2 * pad));
  canvas.restore();

  final text = TextPainter(
    text: TextSpan(children: [
      TextSpan(text: '${label.productId}\n', style: const TextStyle(color: Colors.black, fontSize: 44, fontWeight: FontWeight.bold)),
      if (label.name != null) TextSpan(text: '${label.name}\n', style: const TextStyle(color: Color(0xFF333333), fontSize: 32)),
      const TextSpan(text: 'Scan with VeriTrace', style: TextStyle(color: Color(0xFF666666), fontSize: 26)),
    ]),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 4,
    ellipsis: '…',
  )..layout(maxWidth: width - 2 * pad);
  text.paint(canvas, Offset((width - text.width) / 2, width - pad / 2));

  final image = await recorder.endRecording().toImage(width.toInt(), (width + textHeight).toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Shares the QR label as a PNG via the Android share sheet.
Future<void> shareQrPng(QrLabel label) async {
  final bytes = await renderQrLabelPng(label);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/veritrace_${label.productId}.png');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'image/png')],
    subject: 'VeriTrace QR — ${label.productId}',
    text: 'VeriTrace QR label for ${label.productId}${label.name != null ? ' (${label.name})' : ''}',
  ));
}

/// Builds an A4 sheet of QR labels (3 x 7 per page) with product ID and name.
Future<Uint8List> buildLabelSheetPdf(List<QrLabel> labels, PdfPageFormat format) async {
  const perPage = 21; // 3 columns x 7 rows of fixed-size labels
  const margin = 20.0;
  final cellWidth = (PdfPageFormat.a4.width - 2 * margin) / 3;
  final cellHeight = (PdfPageFormat.a4.height - 2 * margin) / 7;
  final doc = pw.Document(title: 'VeriTrace QR labels', creator: 'VeriTrace');
  for (var start = 0; start < labels.length; start += perPage) {
    final chunk = labels.sublist(start, (start + perPage).clamp(0, labels.length));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(margin),
      build: (context) => pw.Wrap(
        children: [
          for (final l in chunk)
            pw.Container(
              width: cellWidth,
              height: cellHeight,
              padding: const pw.EdgeInsets.all(3),
              child: pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Row(children: [
                  pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: l.payload, width: 80, height: 80),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                      pw.Text(l.productId, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      if (l.name != null) pw.Text(_ascii(l.name!), maxLines: 3, style: const pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(height: 4),
                      pw.Text('Scan with VeriTrace', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
                    ]),
                  ),
                ]),
              ),
            ),
        ],
      ),
    ));
  }
  return doc.save();
}

/// The built-in PDF font is Latin-1 only; replace anything else so labels never fail to render.
String _ascii(String s) => s.replaceAll('—', '-').replaceAll('–', '-').replaceAll(RegExp(r'[^\x20-\xFF]'), '?');

/// Opens the Android print dialog (which can also save as PDF).
Future<void> printLabelSheet(List<QrLabel> labels, {String name = 'VeriTrace labels'}) =>
    Printing.layoutPdf(name: name, onLayout: (format) => buildLabelSheetPdf(labels, format));
