import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/receipt_service.dart';

class ReceiptDetailScreen extends StatefulWidget {
  final String receiptId;
  final Map<String, dynamic> receiptData;
  final bool canManage; // true for manager/admin
  final bool canDelete; // true for admin (any), or uploader (own receipt)

  const ReceiptDetailScreen({
    super.key,
    required this.receiptId,
    required this.receiptData,
    required this.canManage,
    required this.canDelete,
  });

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  final ReceiptService _receiptService = ReceiptService();
  final ImagePicker _picker = ImagePicker();

  bool _isUploadingPop = false;
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _handleMarkAsPaid() async {
    final XFile? popImage = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (popImage == null) return;

    setState(() {
      _isUploadingPop = true;
      _errorMessage = null;
    });

    try {
      await _receiptService.markAsPaid(
        receiptId: widget.receiptId,
        popImageFile: File(popImage.path),
        orgId: widget.receiptData['orgId'],
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _errorMessage = 'Failed to mark as paid: $e');
    } finally {
      if (mounted) setState(() => _isUploadingPop = false);
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Receipt'),
        content: const Text(
          'This will permanently delete the receipt and its image. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await _receiptService.deleteReceipt(
        receiptId: widget.receiptId,
        orgId: widget.receiptData['orgId'],
        popImageUrl: widget.receiptData['popImageUrl'],
      );
      if (mounted) Navigator.of(context).pop(); // back to receipts log
    } catch (e) {
      setState(() => _errorMessage = 'Delete failed: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPaid = widget.receiptData['status'] == 'paid';
    final createdAt =
        (widget.receiptData['createdAt'] as Timestamp?)?.toDate();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          if (widget.canDelete)
            _isDeleting
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete receipt',
                    onPressed: _handleDelete,
                  ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.receiptData['imageUrl'],
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.receiptData['uploadedByName'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Chip(
                  label: Text(isPaid ? 'Paid' : 'Unpaid'),
                  backgroundColor:
                      isPaid ? Colors.green[50] : Colors.orange[50],
                  labelStyle: TextStyle(
                    color:
                        isPaid ? Colors.green[800] : Colors.orange[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Uploaded: ${createdAt.day}/${createdAt.month}/${createdAt.year}',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            if (isPaid && widget.receiptData['popImageUrl'] != null) ...[
              const SizedBox(height: 24),
              const Text('Proof of Payment',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  widget.receiptData['popImageUrl'],
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ),
            ],
            if (widget.canManage && !isPaid) ...[
              const SizedBox(height: 24),
              if (_isUploadingPop)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton.icon(
                  onPressed: _handleMarkAsPaid,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Mark as Paid (Upload POP)'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}