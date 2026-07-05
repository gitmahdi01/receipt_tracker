import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';


class ShareService {
  static Future<void> shareFile(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Receipt Export',
      ),
    );
  }
}
class ExportService {
  /// Fetches receipts for the org within the date range (inclusive),
  /// ordered by createdAt ascending for a clean timeline in the export.
  static Future<List<Map<String, dynamic>>> fetchReceipts({
    required String orgId,
    required DateTime from,
    required DateTime to,
  }) async {
    // 'to' is set to end-of-day so receipts uploaded on that day are included.
    final toEndOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59);

    final snapshot = await FirebaseFirestore.instance
        .collection('receipts')
        .where('orgId', isEqualTo: orgId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(toEndOfDay))
        .orderBy('createdAt', descending: false)
        .get();

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();
  }

  // ─── Excel export ────────────────────────────────────────────────────────────

  static Future<File> exportExcel({
    required String orgName,
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> receipts,
  }) async {
    final excel = Excel.createExcel();

    // Remove the default empty sheet Excel creates.
    excel.delete('Sheet1');

    _buildSummarySheet(excel, orgName, from, to, receipts);
    _buildLineItemsSheet(excel, receipts);

    final bytes = excel.save();
    if (bytes == null) throw Exception('Failed to generate Excel file');

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        '${_sanitise(orgName)}_receipts_${_dateStr(from)}_to_${_dateStr(to)}.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  static void _buildSummarySheet(
    Excel excel,
    String orgName,
    DateTime from,
    DateTime to,
    List<Map<String, dynamic>> receipts,
  ) {
    final sheet = excel['Summary'];

    // Title rows
    sheet.appendRow([
      TextCellValue('$orgName — Receipt Summary'),
    ]);
    sheet.appendRow([
      TextCellValue(
          'Period: ${_fmt(from)} to ${_fmt(to)}'),
    ]);
    sheet.appendRow([TextCellValue('')]);

    // Header row
    sheet.appendRow([
      TextCellValue('Receipt ID'),
      TextCellValue('Uploaded By'),
      TextCellValue('Upload Date'),
      TextCellValue('Receipt Date'),
      TextCellValue('Total Amount'),
      TextCellValue('Currency'),
      TextCellValue('Status'),
      TextCellValue('OCR Reviewed'),
    ]);

    // Data rows
    for (final r in receipts) {
      final uploadedAt = (r['createdAt'] as Timestamp?)?.toDate();
      final receiptDate = (r['date'] as Timestamp?)?.toDate();
      sheet.appendRow([
        TextCellValue(r['id'] ?? ''),
        TextCellValue(r['uploadedByName'] ?? ''),
        TextCellValue(uploadedAt != null ? _fmt(uploadedAt) : ''),
        TextCellValue(receiptDate != null ? _fmt(receiptDate) : ''),
        r['totalAmount'] != null
            ? DoubleCellValue((r['totalAmount'] as num).toDouble())
            : TextCellValue(''),
        TextCellValue(r['currency'] ?? ''),
        TextCellValue(r['status'] ?? ''),
        TextCellValue((r['ocrReviewed'] == true) ? 'Yes' : 'No'),
      ]);
    }
  }

  static void _buildLineItemsSheet(
    Excel excel,
    List<Map<String, dynamic>> receipts,
  ) {
    final sheet = excel['Line Items'];

    sheet.appendRow([
      TextCellValue('Receipt ID'),
      TextCellValue('Uploaded By'),
      TextCellValue('Upload Date'),
      TextCellValue('Item Description'),
      TextCellValue('Item Price'),
      TextCellValue('Currency'),
    ]);

    for (final r in receipts) {
      final uploadedAt = (r['createdAt'] as Timestamp?)?.toDate();
      final lineItems = r['lineItems'] as List<dynamic>? ?? [];

      if (lineItems.isEmpty) {
        // Receipt has no parsed line items — still include a row so the
        // receipt appears in this sheet, just with empty item columns.
        sheet.appendRow([
          TextCellValue(r['id'] ?? ''),
          TextCellValue(r['uploadedByName'] ?? ''),
          TextCellValue(uploadedAt != null ? _fmt(uploadedAt) : ''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(r['currency'] ?? ''),
        ]);
      } else {
        for (final item in lineItems) {
          final itemMap = item as Map<String, dynamic>;
          sheet.appendRow([
            TextCellValue(r['id'] ?? ''),
            TextCellValue(r['uploadedByName'] ?? ''),
            TextCellValue(uploadedAt != null ? _fmt(uploadedAt) : ''),
            TextCellValue(itemMap['description'] ?? ''),
            itemMap['price'] != null
                ? DoubleCellValue((itemMap['price'] as num).toDouble())
                : TextCellValue(''),
            TextCellValue(r['currency'] ?? ''),
          ]);
        }
      }
    }
  }

  // ─── PDF export ──────────────────────────────────────────────────────────────

  static Future<File> exportPdf({
    required String orgName,
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> receipts,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => _pdfHeader(ctx, orgName, from, to),
        footer: (ctx) => _pdfFooter(ctx),
        build: (ctx) => [
          if (receipts.isEmpty)
            pw.Text('No receipts found for this period.',
                style: pw.TextStyle(color: PdfColors.grey))
          else ...[
            _pdfSummaryTable(receipts),
            pw.SizedBox(height: 24),
            pw.Text('Line Items',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            _pdfLineItemsTable(receipts),
          ],
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        '${_sanitise(orgName)}_receipts_${_dateStr(from)}_to_${_dateStr(to)}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static pw.Widget _pdfHeader(
      pw.Context ctx, String orgName, DateTime from, DateTime to) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '$orgName — Receipt History',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Period: ${_fmt(from)} to ${_fmt(to)}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.Divider(thickness: 1, color: PdfColors.grey400),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static pw.Widget _pdfFooter(pw.Context ctx) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text(
          'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
        ),
      ],
    );
  }

  static pw.Widget _pdfSummaryTable(List<Map<String, dynamic>> receipts) {
    final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold);
    const cellPad = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Summary',
            style:
                pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.5),
            1: const pw.FlexColumnWidth(1.8),
            2: const pw.FlexColumnWidth(1.8),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                pw.Padding(padding: cellPad, child: pw.Text('Uploaded By', style: headerStyle)),
                pw.Padding(padding: cellPad, child: pw.Text('Upload Date', style: headerStyle)),
                pw.Padding(padding: cellPad, child: pw.Text('Receipt Date', style: headerStyle)),
                pw.Padding(padding: cellPad, child: pw.Text('Total', style: headerStyle)),
                pw.Padding(padding: cellPad, child: pw.Text('Status', style: headerStyle)),
              ],
            ),
            ...receipts.map((r) {
              final uploadedAt = (r['createdAt'] as Timestamp?)?.toDate();
              final receiptDate = (r['date'] as Timestamp?)?.toDate();
              final total = r['totalAmount'] != null
                  ? '${(r['totalAmount'] as num).toStringAsFixed(2)} ${r['currency'] ?? ''}'
                  : '—';
              return pw.TableRow(
                children: [
                  pw.Padding(padding: cellPad, child: pw.Text(r['uploadedByName'] ?? '', style: const pw.TextStyle(fontSize: 9))),
                  pw.Padding(padding: cellPad, child: pw.Text(uploadedAt != null ? _fmt(uploadedAt) : '—', style: const pw.TextStyle(fontSize: 9))),
                  pw.Padding(padding: cellPad, child: pw.Text(receiptDate != null ? _fmt(receiptDate) : '—', style: const pw.TextStyle(fontSize: 9))),
                  pw.Padding(padding: cellPad, child: pw.Text(total, style: const pw.TextStyle(fontSize: 9))),
                  pw.Padding(padding: cellPad, child: pw.Text(r['status'] ?? '—', style: const pw.TextStyle(fontSize: 9))),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _pdfLineItemsTable(List<Map<String, dynamic>> receipts) {
    final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold);
    const cellPad = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4);

    // Flatten all line items across all receipts.
    final rows = <pw.TableRow>[];
    for (final r in receipts) {
      final uploadedAt = (r['createdAt'] as Timestamp?)?.toDate();
      final lineItems = r['lineItems'] as List<dynamic>? ?? [];
      if (lineItems.isEmpty) continue;
      for (final item in lineItems) {
        final itemMap = item as Map<String, dynamic>;
        final price = itemMap['price'] != null
            ? '${(itemMap['price'] as num).toStringAsFixed(2)} ${r['currency'] ?? ''}'
            : '—';
        rows.add(pw.TableRow(
          children: [
            pw.Padding(padding: cellPad, child: pw.Text(r['uploadedByName'] ?? '', style: const pw.TextStyle(fontSize: 9))),
            pw.Padding(padding: cellPad, child: pw.Text(uploadedAt != null ? _fmt(uploadedAt) : '—', style: const pw.TextStyle(fontSize: 9))),
            pw.Padding(padding: cellPad, child: pw.Text(itemMap['description'] ?? '', style: const pw.TextStyle(fontSize: 9))),
            pw.Padding(padding: cellPad, child: pw.Text(price, style: const pw.TextStyle(fontSize: 9))),
          ],
        ));
      }
    }

    if (rows.isEmpty) {
      return pw.Text('No line item data available.',
          style: const pw.TextStyle(color: PdfColors.grey, fontSize: 9));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1.8),
        2: const pw.FlexColumnWidth(3),
        3: const pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(padding: cellPad, child: pw.Text('Uploaded By', style: headerStyle)),
            pw.Padding(padding: cellPad, child: pw.Text('Upload Date', style: headerStyle)),
            pw.Padding(padding: cellPad, child: pw.Text('Item', style: headerStyle)),
            pw.Padding(padding: cellPad, child: pw.Text('Price', style: headerStyle)),
          ],
        ),
        ...rows,
      ],
    );
  }


  // ─── Share ───────────────────────────────────────────────────────────────────

  static Future<void> shareFile(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Please find the attached receipt.',
        subject: 'Receipt Export',
        files: [XFile(file.path)],
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _sanitise(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
}