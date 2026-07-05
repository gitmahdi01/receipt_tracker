import 'package:flutter/material.dart';
import '../services/receipt_service.dart';
import '../services/receipt_parser.dart';

class ReceiptReviewScreen extends StatefulWidget {
  final String receiptId;
  final ParsedReceipt parsed;

  const ReceiptReviewScreen({
    super.key,
    required this.receiptId,
    required this.parsed,
  });

  @override
  State<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends State<ReceiptReviewScreen> {
  final ReceiptService _receiptService = ReceiptService();

  // Editable state — pre-filled from OCR parser output.
  late DateTime? _date;
  late TextEditingController _totalController;
  late TextEditingController _currencyController;
  late List<_EditableLineItem> _lineItems;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _date = widget.parsed.date;
    _totalController = TextEditingController(
      text: widget.parsed.totalAmount?.toStringAsFixed(2) ?? '',
    );
    _currencyController = TextEditingController(
      text: widget.parsed.currency ?? '',
    );
    _lineItems = widget.parsed.lineItems
        .map((item) => _EditableLineItem(
              descController: TextEditingController(text: item.description),
              priceController: TextEditingController(
                text: item.price?.toStringAsFixed(2) ?? '',
              ),
            ))
        .toList();
  }

  @override
  void dispose() {
    _totalController.dispose();
    _currencyController.dispose();
    for (final item in _lineItems) {
      item.descController.dispose();
      item.priceController.dispose();
    }
    super.dispose();
  }

  void _addLineItem() {
    setState(() {
      _lineItems.add(_EditableLineItem(
        descController: TextEditingController(),
        priceController: TextEditingController(),
      ));
    });
  }

  void _removeLineItem(int index) {
    setState(() {
      _lineItems[index].descController.dispose();
      _lineItems[index].priceController.dispose();
      _lineItems.removeAt(index);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final total = double.tryParse(_totalController.text.trim());
      final currency = _currencyController.text.trim().isEmpty
          ? null
          : _currencyController.text.trim().toUpperCase();

      final lineItems = _lineItems
          .where((item) => item.descController.text.trim().isNotEmpty)
          .map((item) => ParsedLineItem(
                description: item.descController.text.trim(),
                price: double.tryParse(item.priceController.text.trim()),
              ))
          .toList();

      await _receiptService.updateParsedFields(
        receiptId: widget.receiptId,
        date: _date,
        totalAmount: total,
        currency: currency,
        lineItems: lineItems,
      );

      if (mounted) {
        // Pop all the way back to the receipts log (upload screen was
        // replaced by this screen, so one pop returns to the shell).
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Receipt'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // OCR accuracy notice — sets expectations upfront.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.amber[700]),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'These fields were read automatically from the receipt. '
                    'Please check and correct anything that looks wrong before saving. '
                    'The original photo is always kept as the source of truth.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Date
          _SectionLabel('Date'),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    _date == null
                        ? 'Tap to set date'
                        : '${_date!.day.toString().padLeft(2, '0')}.'
                            '${_date!.month.toString().padLeft(2, '0')}.'
                            '${_date!.year}',
                    style: TextStyle(
                      fontSize: 15,
                      color: _date == null ? Colors.grey : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Total + currency side by side
          _SectionLabel('Total Amount'),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 90,
                child: TextFormField(
                  controller: _currencyController,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    hintText: 'CHF',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      null, // hide the character counter
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _totalController,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    hintText: '0.00',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Line items
          Row(
            children: [
              const Expanded(child: _SectionLabel('Line Items')),
              TextButton.icon(
                onPressed: _addLineItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add item'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_lineItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No line items found. Tap "Add item" to add one manually.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),

          ..._lineItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 5,
                    child: TextFormField(
                      controller: item.descController,
                      decoration: InputDecoration(
                        labelText: 'Item ${index + 1}',
                        hintText: 'Description',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: item.priceController,
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        hintText: '0.00',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => _removeLineItem(index),
                    tooltip: 'Remove item',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 32),

          if (_errorMessage != null) ...[
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],

          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save Receipt'),
          ),

          const SizedBox(height: 12),

          // Discard link — backs out without saving structured fields.
          // extractedText + photo are already saved on the doc.
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Skip for now — keep photo only',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _EditableLineItem {
  final TextEditingController descController;
  final TextEditingController priceController;

  _EditableLineItem({
    required this.descController,
    required this.priceController,
  });
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );
  }
}