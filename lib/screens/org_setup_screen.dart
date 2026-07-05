import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/org_service.dart';

class OrgSetupScreen extends StatefulWidget {
  const OrgSetupScreen({super.key});

  @override
  State<OrgSetupScreen> createState() => _OrgSetupScreenState();
}

class _OrgSetupScreenState extends State<OrgSetupScreen> {
  final OrgService _orgService = OrgService();
  final TextEditingController _orgNameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleCreate() async {
    final name = _orgNameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter an organisation name.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _orgService.createOrganization(name);
      // AuthGate will auto-rebuild once orgId updates in Firestore.
    } catch (e) {
      setState(() => _errorMessage = 'Could not create organisation: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleJoin() async {
    final code = _inviteCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'Please enter an invite code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _orgService.joinOrganization(code);
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Organisation'),
        content: TextField(
          controller: _orgNameController,
          decoration: const InputDecoration(
            labelText: 'Organisation name',
            hintText: 'e.g. Greenfield Primary School',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _handleCreate();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showJoinDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join Organisation'),
        content: TextField(
          controller: _inviteCodeController,
          decoration: const InputDecoration(
            labelText: 'Invite code',
            hintText: '6-digit code',
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _handleJoin();
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Get Started'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.apartment, size: 64, color: Colors.indigo),
              const SizedBox(height: 16),
              Text(
                'Join or create an organisation to get started',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                Column(
                  children: [
                    FilledButton.icon(
                      onPressed: _showCreateDialog,
                      icon: const Icon(Icons.add_business),
                      label: const Text('Create Organisation'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(260, 48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _showJoinDialog,
                      icon: const Icon(Icons.group_add),
                      label: const Text('Join Organisation'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(260, 48),
                      ),
                    ),
                  ],
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}