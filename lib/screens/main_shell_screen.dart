import 'package:flutter/material.dart';
import 'receipts_log_screen.dart';
import 'upload_receipt_screen.dart';
import 'organisation_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    ReceiptsLogScreen(),
    SizedBox(), // Upload tab never actually shows — see _onTap below
    OrganisationScreen(),
  ];

  void _onTap(int index) {
    if (index == 1) {
      // Center button opens upload as a full-screen modal instead
      // of becoming a persistent tab.
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UploadReceiptScreen()),
      );
      return;
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: Icon(
                Icons.receipt_long,
                color: _selectedIndex == 0 ? Colors.indigo : Colors.grey,
              ),
              onPressed: () => _onTap(0),
              tooltip: 'My Receipts',
            ),
            const SizedBox(width: 48), // space for the notch/FAB
            IconButton(
              icon: Icon(
                Icons.apartment,
                color: _selectedIndex == 2 ? Colors.indigo : Colors.grey,
              ),
              onPressed: () => _onTap(2),
              tooltip: 'Organisation',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onTap(1),
        backgroundColor: Colors.indigo,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 32, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}