import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/services/receipt_parser.dart';

void main() {
  group('ReceiptParser', () {
    test('parses the Grosse Scheidegg sample receipt', () {
      const sample = '''Rech. Nr. 4572
Bar Ber ghotel Grosse Scheidegg
3818 Grinde lwald
1xGloki
Fami lie R. Müller
2xLatte Macchiato
1xSchweinschnitze l à
1xChässpätzli à
30.07. 2007/ 13:29:17 Tisch 7/01
4.50 CHF
5.00
22. 00
Total : CHF
CHF 18.50
CHF Incl. 7. 6% MwSt
54.50 CHF:
CHF Entspricht in Euro 36.33 EUR
Es bediente Sie: Ursula
3.85 MwSt
Nr.: 430 234
Tel.: 033 853 67 16
Fax. : 033 853 67 19
9. 00
5.00
22. 00
E-mail: grossescheidegg@bluewin. ch
54, 50
18.50''';

      final result = ReceiptParser.parse(sample);

      // Print full output so you can eyeball it in the test console too.
      // ignore: avoid_print
      print(result);

      // Date: should correctly parse 30.07.2007 despite the stray space
      // OCR inserted after the second separator ("30.07. 2007").
      expect(result.date, isNotNull);
      expect(result.date!.day, 30);
      expect(result.date!.month, 7);
      expect(result.date!.year, 2007);

      // Total: should pick 54.50, not the decoy 18.50 that sits between
      // the "Total" label and the real total in the OCR text.
      expect(result.totalAmount, isNotNull);
      expect(result.totalAmount, closeTo(54.50, 0.001));
      expect(result.currency, 'CHF');

      // Line items: should find all 4 items from the receipt.
      expect(result.lineItems.length, 4);
      expect(result.lineItems[0].description, contains('Gloki'));
      expect(result.lineItems[1].description, contains('Latte Macchiato'));
      expect(result.lineItems[2].description, contains('Schweinschnitze'));
      expect(result.lineItems[3].description, contains('Chässpätzli'));

      // Every line item should have been assigned some price (even if
      // the specific pairing isn't guaranteed correct, given the
      // separated item/price blocks in this receipt's layout).
      for (final item in result.lineItems) {
        expect(item.price, isNotNull,
            reason: '${item.description} should have a price assigned');
      }
    });

    test('returns nulls gracefully on empty text', () {
      final result = ReceiptParser.parse('');
      expect(result.date, isNull);
      expect(result.totalAmount, isNull);
      expect(result.lineItems, isEmpty);
    });

    test('handles a simple clean receipt with no OCR noise', () {
      const sample = '''Coffee Shop
01.03.2024
2xCappuccino 8.00
1xCroissant 3.50
Total: 11.50 EUR''';

      final result = ReceiptParser.parse(sample);

      expect(result.date, isNotNull);
      expect(result.date!.day, 1);
      expect(result.date!.month, 3);
      expect(result.date!.year, 2024);

      expect(result.totalAmount, closeTo(11.50, 0.001));
      expect(result.currency, 'EUR');
      expect(result.lineItems.length, 2);
    });
  });
}