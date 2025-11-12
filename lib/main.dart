// lib/main.dart
import 'package:flutter/material.dart';

// Firebase core + options
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Auth + Firestore
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Repo + UI
import 'services/envelope_repo.dart';
import 'services/workspace_session.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';

// Persist last workspace choice
import 'package:shared_preferences/shared_preferences.dart';

const String kPrefsKeyWorkspace = 'last_workspace_id';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const EnvelopeLiteApp());
}

class EnvelopeLiteApp extends StatefulWidget {
  const EnvelopeLiteApp({super.key});
  @override
  State<EnvelopeLiteApp> createState() => _EnvelopeLiteAppState();
}

class _EnvelopeLiteAppState extends State<EnvelopeLiteApp> {
  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        onPrimary: Colors.white,
        secondary: Colors.black,
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        error: Colors.black, // keep error accents non-red for this screen
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.black, width: 1.6),
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          side: const BorderSide(color: Colors.black, width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Colors.black,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(color: Colors.black12, thickness: 1),
    );

    return MaterialApp(
      title: 'Team Envelopes',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const _AuthGate(child: _RepoGate()),
    );
  }
}

/// Waits for Firebase user; shows SignInScreen if signed out.
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.child});
  final Widget child;
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Stream<User?> _auth$;

  @override
  void initState() {
    super.initState();
    _auth$ = FirebaseAuth.instance.authStateChanges();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth$,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) return const SignInScreen();
        return widget.child;
      },
    );
  }
}

/// Builds EnvelopeRepo with Solo/Workspace context based on saved prefs.
class _RepoGate extends StatefulWidget {
  const _RepoGate();
  @override
  State<_RepoGate> createState() => _RepoGateState();
}

class _RepoGateState extends State<_RepoGate> {
  Future<EnvelopeRepo> _buildRepo() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWorkspaceId = prefs.getString(kPrefsKeyWorkspace);
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return EnvelopeRepo.firebase(
      FirebaseFirestore.instance,
      workspaceId: (savedWorkspaceId != null && savedWorkspaceId.isNotEmpty)
          ? savedWorkspaceId
          : null,
      userId: userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EnvelopeRepo>(
      future: _buildRepo(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return Scaffold(
            body: Center(
              child: Text('Error initializing repository: ${snap.error}'),
            ),
          );
        }
        final repo = snap.data!;
        return WorkspaceSession(
          workspaceId: repo.workspaceId,
          child: HomeScreen(repo: repo),
        );
      },
    );
  }
}
