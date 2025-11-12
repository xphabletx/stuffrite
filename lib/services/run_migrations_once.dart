// lib/services/run_migrations_once.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'migration_manager.dart';

/// Safe to call on every app start and after sign-in.
/// - If no user is signed in, it returns immediately.
/// - It only runs once per (buildNumber + userId) on this device.
Future<void> runMigrationsOncePerBuild({
  required FirebaseFirestore db,
  String? explicitUid,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  final uid = explicitUid ?? user?.uid;
  if (uid == null) return;

  final info = await PackageInfo.fromPlatform();
  final prefs = await SharedPreferences.getInstance();
  final ranKey = 'migrations_ran_build_${info.buildNumber}_uid_$uid';

  if (prefs.getBool(ranKey) == true) return;

  final mgr = MigrationManager(db, uid);
  await mgr.runIfNeeded();

  await prefs.setBool(ranKey, true);
}
