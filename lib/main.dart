import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'screens/sign_in_screen.dart';
import 'screens/org_setup_screen.dart';
import 'screens/main_shell_screen.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Keep the native splash visible until Firebase is ready.

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Firebase is ready — remove the splash and show the app.
  

  runApp(const ReceiptTrackerApp());
}

class ReceiptTrackerApp extends StatelessWidget {
  const ReceiptTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Tracker',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnapshot.data;

        if (user == null) {
          return const SignInScreen();
        }

        // Logged in — now check their Firestore doc for orgId.
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userDocSnapshot) {
            if (userDocSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!userDocSnapshot.hasData || !userDocSnapshot.data!.exists) {
              // Doc not created yet (race condition right after sign-up) —
              // show a brief loader, it'll rebuild once the doc lands.
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final data =
                userDocSnapshot.data!.data() as Map<String, dynamic>;
            final orgId = data['orgId'];

            if (orgId == null) {
              return const OrgSetupScreen();
            }

            return const MainShellScreen();
          },
        );
      },
    );
  }
}