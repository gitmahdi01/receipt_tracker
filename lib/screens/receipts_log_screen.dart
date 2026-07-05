import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/receipt_service.dart';
import 'receipt_detail_screen.dart';

class ReceiptsLogScreen extends StatefulWidget {
  const ReceiptsLogScreen({super.key});

  @override
  State<ReceiptsLogScreen> createState() => _ReceiptsLogScreenState();
}

class _ReceiptsLogScreenState extends State<ReceiptsLogScreen> {
  final AuthService _authService = AuthService();
  final ReceiptService _receiptService = ReceiptService();

  String? _orgId;
  String? _role;
  String? _currentUid;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final data = await _authService.getCurrentUserData();
    setState(() {
      _orgId = data?['orgId'];
      _role = data?['role'];
      _currentUid = _authService.currentUser?.uid;
      _isLoading = false;
    });
  }

  /// Admin can delete any receipt.
  /// Manager/user can only delete receipts they uploaded themselves.
  bool _canDelete(Map<String, dynamic> data) {
    if (_role == 'admin') return true;
    return data['uploadedBy'] == _currentUid;
  }

  Future<void> _confirmAndDelete({
    required BuildContext context,
    required String receiptId,
    required Map<String, dynamic> data,
  }) async {
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

    if (confirmed != true || !context.mounted) return;

    try {
      await _receiptService.deleteReceipt(
        receiptId: receiptId,
        orgId: data['orgId'],
        popImageUrl: data['popImageUrl'],
      );
      // List updates automatically via StreamBuilder — no setState needed.
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isManagerOrAdmin = _role == 'manager' || _role == 'admin';

    final query = isManagerOrAdmin
        ? FirebaseFirestore.instance
            .collection('receipts')
            .where('orgId', isEqualTo: _orgId)
            .orderBy('createdAt', descending: true)
        : FirebaseFirestore.instance
            .collection('receipts')
            .where('orgId', isEqualTo: _orgId)
            .where('uploadedBy', isEqualTo: _currentUid)
            .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
          title: Text(isManagerOrAdmin ? 'All Receipts' : 'My Receipts')),
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
              final canDelete = _canDelete(data);

              return GestureDetector(
                onLongPress: canDelete
                    ? () => _confirmAndDelete(
                          context: context,
                          receiptId: doc.id,
                          data: data,
                        )
                    : null,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReceiptDetailScreen(
                            receiptId: doc.id,
                            receiptData: data,
                            canManage: isManagerOrAdmin,
                            canDelete: canDelete,
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
                      isManagerOrAdmin
                          ? (data['uploadedByName'] ?? 'Unknown')
                          : 'Receipt',
                    ),
                    subtitle: Text(
                      createdAt != null
                          ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                          : '',
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