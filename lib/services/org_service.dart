import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrgService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _generateInviteCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  Future<void> createOrganization(String orgName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');

    final inviteCode = _generateInviteCode();
    final orgRef = _db.collection('organizations').doc();

    await orgRef.set({
      'name': orgName,
      'ownerId': user.uid,
      'inviteCode': inviteCode,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(user.uid).update({ 
      'orgId': orgRef.id,
      'role': 'admin',
    });
  }

  Future<void> joinOrganization(String inviteCode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');

    final query = await _db
        .collection('organizations')
        .where('inviteCode', isEqualTo: inviteCode.trim())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Invalid invite code. Please check and try again.');
    }

    final orgDoc = query.docs.first;

    await _db.collection('users').doc(user.uid).update({
      'orgId': orgDoc.id,
      'role': 'user',
    });
  }

  Future<void> updateMemberRole({
    required String memberId,
    required String newRole,
  }) async {
    await _db.collection('users').doc(memberId).update({'role': newRole});
  }

  Future<void> removeMember(String memberId) async {
    await _db.collection('users').doc(memberId).delete();
  }
}