/// Parses raw OCR text from a receipt into structured fields.
///
/// This is intentionally best-effort: real receipts vary wildly in layout,
/// and OCR introduces its own noise (broken decimals like "22. 00", lines
/// split mid-word, line items separated from their prices). The goal here
/// is "close enough that a human editing the result is faster than typing
/// from scratch" — not perfect extraction. Always pair this with a
/// confirm/edit UI before saving anything as final.
library;

class ParsedLineItem {
  final String description;
  final double? price;

  ParsedLineItem({required this.description, this.price});

  @override
  String toString() =>
      price != null ? '$description - ${price!.toStringAsFixed(2)}' : description;
}

class ParsedReceipt {
  final DateTime? date;
  final double? totalAmount;
  final String? currency;
  final List<ParsedLineItem> lineItems;

  ParsedReceipt({
    required this.date,
    required this.totalAmount,
    required this.currency,
    required this.lineItems,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('Date: ${date ?? "unknown"}');
    buffer.writeln('Total: ${totalAmount ?? "unknown"} ${currency ?? ""}');
    buffer.writeln('Line items:');
    for (final item in lineItems) {
      buffer.writeln('  - $item');
    }
    return buffer.toString();
  }
}

class ReceiptParser {
  // Matches DD.MM.YYYY or DD/MM/YYYY, tolerant of OCR swapping . and /,
  // and tolerant of stray whitespace around separators (e.g. OCR reading
  // "30.07. 2007" with a space after the second separator).
  static final RegExp _dateRegex =
      RegExp(r'(\d{1,2})\s?[.\/]\s?(\d{1,2})\s?[.\/]\s?(\d{2,4})');

  // Matches a currency amount that has an actual decimal point with two
  // digits after it (e.g. "4.50", "22. 00" with OCR's stray space). This
  // is a deliberately strict requirement: without it, the regex also
  // matches bare integers like phone numbers, reference numbers, and
  // timestamps (verified against real OCR output — "Rech. Nr. 4572" and
  // "Tel.: 033 853 67 16" both produced false "amounts" before this
  // requirement was added). Optional currency symbol/code on either side.
  static final RegExp _amountRegex = RegExp(
    r'(CHF|EUR|USD|\$|€)?\s*(\d{1,3})\s?[.,]\s?(\d{2})\s*(CHF|EUR|USD|\$|€)?',
    caseSensitive: false,
  );

  // Matches a quantity-prefixed line item, e.g. "1xGloki", "2x Latte Macchiato".
  static final RegExp _lineItemRegex =
      RegExp(r'^(\d+)\s*[xX]\s*(.+)$');

  static ParsedReceipt parse(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final date = _extractDate(lines);
    final dateLineIndex = _findDateLineIndex(lines);
    final allAmounts = _extractAllAmounts(lines, skipLineIndex: dateLineIndex);
    final total = _extractTotal(lines, allAmounts);
    final lineItems = _extractLineItems(lines, allAmounts, total);

    return ParsedReceipt(
      date: date,
      totalAmount: total?.value,
      currency: total?.currency,
      lineItems: lineItems,
    );
  }

  static int? _findDateLineIndex(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (_dateRegex.hasMatch(lines[i])) return i;
    }
    return null;
  }

  static DateTime? _extractDate(List<String> lines) {
    for (final line in lines) {
      final match = _dateRegex.firstMatch(line);
      if (match == null) continue;

      final day = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      var year = int.tryParse(match.group(3)!);
      if (day == null || month == null || year == null) continue;
      if (day > 31 || month > 12) continue; // sanity check, skip false hits

      if (year < 100) year += 2000; // handle 2-digit years just in case

      try {
        return DateTime(year, month, day);
      } catch (_) {
        continue; // invalid date (e.g. Feb 30), skip
      }
    }
    return null;
  }

  /// Finds every currency amount in the text, in order of appearance,
  /// keeping track of which line each came from so later steps can
  /// reason about position (e.g. "near the word Total").
  ///
  /// Several guards keep this from misfiring, verified against real OCR
  /// output: lines that are themselves a line-item line ("1xGloki") are
  /// skipped since their only number is a quantity, not a price; matches
  /// followed by x/X or % are skipped for the same reason (quantity
  /// marker / percentage, not a price); and the line containing the
  /// receipt's date is skipped, since a date like "30.07" structurally
  /// matches the price pattern too.
  static List<_AmountMatch> _extractAllAmounts(List<String> lines,
      {int? skipLineIndex}) {
    final results = <_AmountMatch>[];

    for (var i = 0; i < lines.length; i++) {
      if (i == skipLineIndex) continue;
      if (_lineItemRegex.hasMatch(lines[i])) continue;

      for (final match in _amountRegex.allMatches(lines[i])) {
        final whole = match.group(2);
        final frac = match.group(3);
        if (whole == null || frac == null) continue;

        // Skip if this number is immediately followed by x/X (a quantity
        // marker like "1x") or a % sign (a percentage like tax rate,
        // not a price).
        final afterMatch = lines[i].substring(match.end).trimLeft();
        if (afterMatch.startsWith('x') ||
            afterMatch.startsWith('X') ||
            afterMatch.startsWith('%')) {
          continue;
        }

        final value = double.tryParse('$whole.$frac');
        if (value == null) continue;

        final currency = (match.group(1) ?? match.group(4))?.toUpperCase();

        results.add(_AmountMatch(
          value: value,
          currency: _normalizeCurrency(currency),
          lineIndex: i,
        ));
      }
    }
    return results;
  }

  static String? _normalizeCurrency(String? raw) {
    if (raw == null) return null;
    switch (raw.toUpperCase()) {
      case '\$':
        return 'USD';
      case '€':
        return 'EUR';
      default:
        return raw.toUpperCase();
    }
  }

  /// Looks for a line containing "total" and grabs the most likely amount
  /// nearby. OCR often splits the "Total" label from its value across
  /// several lines, sometimes with decoy figures (subtotals, tax amounts)
  /// in between — so rather than taking the very next amount found, this
  /// looks across a small window and prefers the largest one, since the
  /// final total is almost always the largest figure on a receipt.
  static _AmountMatch? _extractTotal(
      List<String> lines, List<_AmountMatch> allAmounts) {
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].toLowerCase().contains('total')) continue;

      final nearby = allAmounts
          .where((a) => a.lineIndex >= i && a.lineIndex <= i + 4)
          .toList();
      if (nearby.isNotEmpty) {
        return nearby.reduce((a, b) => a.value > b.value ? a : b);
      }
    }

    // Fallback: if no "Total" label found at all, assume the largest
    // amount on the receipt is the total (common heuristic).
    if (allAmounts.isEmpty) return null;
    return allAmounts.reduce((a, b) => a.value > b.value ? a : b);
  }

  /// Matches "NxDescription" line items to nearby prices on a best-effort
  /// positional basis. Known limitation: many receipts (including the
  /// sample this was built against) print all line items in one block
  /// and all prices in a separate block further down, so this won't
  /// always pair them correctly — that's expected, not a bug to chase.
  static List<ParsedLineItem> _extractLineItems(
    List<String> lines,
    List<_AmountMatch> allAmounts,
    _AmountMatch? total,
  ) {
    final items = <ParsedLineItem>[];
    final usedAmountIndices = <int>{};

    // Exclude the total's own amount from being assigned to a line item.
    if (total != null) {
      final idx = allAmounts.indexOf(total);
      if (idx != -1) usedAmountIndices.add(idx);
    }

    final itemLines = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (_lineItemRegex.hasMatch(lines[i])) itemLines.add(i);
    }

    for (var n = 0; n < itemLines.length; n++) {
      final lineIndex = itemLines[n];
      final match = _lineItemRegex.firstMatch(lines[lineIndex])!;
      final quantity = match.group(1);
      final description = match.group(2)!.trim();

      // First, check if a price sits on this same line.
      double? price;
      final sameLineAmount = allAmounts.indexWhere(
          (a) => a.lineIndex == lineIndex && !usedAmountIndices.contains(allAmounts.indexOf(a)));
      if (sameLineAmount != -1) {
        price = allAmounts[sameLineAmount].value;
        usedAmountIndices.add(sameLineAmount);
      } else {
        // Otherwise, best-effort: take the nth unused amount overall,
        // assuming items and prices appear in the same relative order
        // even if separated into different blocks of text.
        for (var a = 0; a < allAmounts.length; a++) {
          if (!usedAmountIndices.contains(a)) {
            price = allAmounts[a].value;
            usedAmountIndices.add(a);
            break;
          }
        }
      }

      items.add(ParsedLineItem(
        description: '${quantity}x $description',
        price: price,
      ));
    }

    return items;
  }
}

class _AmountMatch {
  final double value;
  final String? currency;
  final int lineIndex;

  _AmountMatch({required this.value, required this.currency, required this.lineIndex});
}