import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'receipt_parser.dart';

class ReceiptService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadReceipt({
    required File imageFile,
    required String orgId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final displayName =
        userDoc.data()?['displayName'] ?? user.email ?? 'Unknown';

    final receiptRef = _db.collection('receipts').doc();
    final storagePath = 'receipts/$orgId/${receiptRef.id}.jpg';
    final storageRef = _storage.ref().child(storagePath);

    await storageRef.putFile(imageFile);
    final imageUrl = await storageRef.getDownloadURL();

    await receiptRef.set({
      'orgId': orgId,
      'uploadedBy': user.uid,
      'uploadedByName': displayName,
      'imageUrl': imageUrl,
      'status': 'unpaid',
      'popImageUrl': null,
      'paidBy': null,
      'paidAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'extractedText': null,
      'date': null,
      'totalAmount': null,
      'currency': null,
      'lineItems': null,
      'ocrReviewed': false,
    });

    return receiptRef.id;
  }

  Future<void> updateExtractedText({
    required String receiptId,
    required String extractedText,
  }) async {
    await _db.collection('receipts').doc(receiptId).update({
      'extractedText': extractedText,
    });
  }

  Future<void> updateParsedFields({
    required String receiptId,
    required DateTime? date,
    required double? totalAmount,
    required String? currency,
    required List<ParsedLineItem> lineItems,
  }) async {
    await _db.collection('receipts').doc(receiptId).update({
      'date': date != null ? Timestamp.fromDate(date) : null,
      'totalAmount': totalAmount,
      'currency': currency,
      'lineItems': lineItems
          .map((item) => {
                'description': item.description,
                'price': item.price,
              })
          .toList(),
      'ocrReviewed': true,
    });
  }

  /// Fully deletes a receipt: removes the receipt image from Storage,
  /// the POP image if one exists, and then the Firestore doc.
  /// Storage deletes are best-effort — if a file is already missing we
  /// continue rather than throwing, so a half-deleted receipt can still
  /// be cleaned up on a retry.
  Future<void> deleteReceipt({
    required String receiptId,
    required String orgId,
    required String? popImageUrl,
  }) async {
    // Delete receipt image from Storage.
    try {
      final receiptImageRef =
          _storage.ref().child('receipts/$orgId/$receiptId.jpg');
      await receiptImageRef.delete();
    } on FirebaseException catch (e) {
      // object-not-found is fine — already gone, carry on.
      if (e.code != 'object-not-found') rethrow;
    }

    // Delete POP image if one was uploaded.
    if (popImageUrl != null) {
      try {
        final popRef = _storage.ref().child('pop/$orgId/$receiptId.jpg');
        await popRef.delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
    }

    // Delete Firestore doc last — if Storage deletes fail above this
    // won't be reached, keeping the doc as a reference to retry with.
    await _db.collection('receipts').doc(receiptId).delete();
  }

  Future<void> markAsPaid({
    required String receiptId,
    required File popImageFile,
    required String orgId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');

    final popPath = 'pop/$orgId/$receiptId.jpg';
    final popRef = _storage.ref().child(popPath);

    await popRef.putFile(popImageFile);
    final popImageUrl = await popRef.getDownloadURL();

    await _db.collection('receipts').doc(receiptId).update({
      'status': 'paid',
      'popImageUrl': popImageUrl,
      'paidBy': user.uid,
      'paidAt': FieldValue.serverTimestamp(),
    });
  }
}