import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/org_service.dart';
import 'member_receipts_screen.dart';
import 'export_screen.dart';

class OrganisationScreen extends StatefulWidget {
  const OrganisationScreen({super.key});

  @override
  State<OrganisationScreen> createState() => _OrganisationScreenState();
}

class _OrganisationScreenState extends State<OrganisationScreen> {
  final AuthService _authService = AuthService();
  final OrgService _orgService = OrgService();
  String? _orgId;
  String? _role;
  String _orgName = '';
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
      _isLoading = false;
    });
  }

  Future<void> _confirmRemove(String memberId, String memberName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
            'Remove $memberName from this organisation? Their existing receipts will remain, but they will lose access.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _orgService.removeMember(memberId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$memberName removed.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to remove: $e')),
          );
        }
      }
    }
  }

  Future<void> _toggleManagerRole(
      String memberId, String memberName, String currentRole) async {
    final newRole = currentRole == 'manager' ? 'user' : 'manager';
    try {
      await _orgService.updateMemberRole(memberId: memberId, newRole: newRole);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newRole == 'manager'
                  ? '$memberName promoted to Manager.'
                  : '$memberName set back to User.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update role: $e')),
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
    final isAdmin = _role == 'admin';
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Organisation'),
        actions: [
          // Export button — only visible to manager/admin.
          // orgName is populated from the Firestore stream when it fires.
          if (isManagerOrAdmin)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export receipt history',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExportScreen(
                      orgId: _orgId!,
                      orgName: _orgName,
                    ),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('organizations')
            .doc(_orgId)
            .snapshots(),
        builder: (context, orgSnapshot) {
          if (!orgSnapshot.hasData || !orgSnapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final orgData = orgSnapshot.data!.data() as Map<String, dynamic>;
          final orgName = orgData['name'] ?? '';
          // Cache so the AppBar export button can use it.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) { if (mounted && _orgName != orgName) setState(() => _orgName = orgName); },
          );

          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            orgName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          // Second entry point to export, directly on the
                          // org card, for discoverability.
                          if (isManagerOrAdmin)
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ExportScreen(
                                      orgId: _orgId!,
                                      orgName: orgName,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.download_outlined,
                                  size: 16),
                              label: const Text('Export'),
                              style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Invite code: ',
                              style: TextStyle(color: Colors.grey)),
                          Text(
                            orgData['inviteCode'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Members',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('orgId', isEqualTo: _orgId)
                      .snapshots(),
                  builder: (context, membersSnapshot) {
                    if (!membersSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final members = membersSnapshot.data!.docs;

                    return ListView.builder(
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final memberData =
                            members[index].data() as Map<String, dynamic>;
                        final memberId = members[index].id;
                        final memberRole = memberData['role'] ?? 'user';
                        final memberName =
                            memberData['displayName'] ?? 'Unknown';
                        final isSelf = memberId == currentUid;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: memberData['photoUrl'] != null &&
                                    memberData['photoUrl'] != ''
                                ? NetworkImage(memberData['photoUrl'])
                                : null,
                            child: (memberData['photoUrl'] == null ||
                                    memberData['photoUrl'] == '')
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(memberName),
                          subtitle: Text(memberData['email'] ?? ''),
                          onTap: isManagerOrAdmin
                              ? () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => MemberReceiptsScreen(
                                        memberId: memberId,
                                        memberName: memberName,
                                        orgId: _orgId!,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(memberRole),
                                backgroundColor: memberRole == 'admin'
                                    ? Colors.indigo[50]
                                    : memberRole == 'manager'
                                        ? Colors.blue[50]
                                        : Colors.grey[200],
                              ),
                              SizedBox(
                                width: 40,
                                child: (isAdmin &&
                                        !isSelf &&
                                        memberRole != 'admin')
                                    ? PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'toggle_manager') {
                                            _toggleManagerRole(memberId,
                                                memberName, memberRole);
                                          } else if (value == 'remove') {
                                            _confirmRemove(
                                                memberId, memberName);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'toggle_manager',
                                            child: Text(
                                                memberRole == 'manager'
                                                    ? 'Remove Manager role'
                                                    : 'Make Manager'),
                                          ),
                                          const PopupMenuItem(
                                            value: 'remove',
                                            child: Text(
                                                'Remove from organisation'),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}