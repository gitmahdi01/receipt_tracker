import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/receipt_service.dart';
import 'receipt_detail_screen.dart';

class MemberReceiptsScreen extends StatelessWidget {
  final String memberId;
  final String memberName;
  final String orgId;

  const MemberReceiptsScreen({
    super.key,
    required this.memberId,
    required this.memberName,
    required this.orgId,
  });

  @override
  Widget build(BuildContext context) {
    final receiptService = ReceiptService();

    final query = FirebaseFirestore.instance
        .collection('receipts')
        .where('orgId', isEqualTo: orgId)
        .where('uploadedBy', isEqualTo: memberId)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: Text("$memberName's Receipts")),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text('No receipts uploaded yet.',
                  style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final status = data['status'] ?? 'unpaid';
              final isPaid = status == 'paid';
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

              return GestureDetector(
                onLongPress: () async {
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
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed != true || !context.mounted) return;

                  try {
                    await receiptService.deleteReceipt(
                      receiptId: doc.id,
                      orgId: data['orgId'],
                      popImageUrl: data['popImageUrl'],
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Delete failed: $e')),
                      );
                    }
                  }
                },
                child: Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReceiptDetailScreen(
                            receiptId: doc.id,
                            receiptData: data,
                            canManage: true,
                            // Manager/admin viewing this screen can always
                            // delete — this screen is not reachable by
                            // regular users.
                            canDelete: true,
                          ),
                        ),
                      );
                    },
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        data['imageUrl'],
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.receipt_long),
                      ),
                    ),
                    title: Text(
                      createdAt != null
                          ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                          : 'Receipt',
                    ),
                    trailing: Chip(
                      label: Text(
                        isPaid ? 'Paid' : 'Unpaid',
                        style: TextStyle(
                          color: isPaid
                              ? Colors.green[800]
                              : Colors.orange[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor:
                          isPaid ? Colors.green[50] : Colors.orange[50],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}