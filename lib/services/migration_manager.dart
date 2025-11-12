import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

typedef Migrator = Future<void> Function();

class MigrationManager {
  static const _kLocalVersionKey = 'app_schema_version';
  // Increment when you add a new migration.
  static const int latestSchema = 6;

  final FirebaseFirestore db;
  final String uid;

  MigrationManager(this.db, this.uid);

  Future<void> runIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_kLocalVersionKey) ?? 0;

    final migrations = <int, Migrator>{
      // 5 -> 6: backfill owner fields + workspace tags on envelopes/tx if missing
      6: () async => _backfillOwnerFields(),
    };

    // Run forward-only migrations
    for (var v = current + 1; v <= latestSchema; v++) {
      final m = migrations[v];
      if (m != null) {
        await m();
      }
    }

    await prefs.setInt(_kLocalVersionKey, latestSchema);
  }

  Future<void> _backfillOwnerFields() async {
    final user = FirebaseAuth.instance.currentUser;
    final ownerName = user?.displayName ?? (user?.email ?? 'Me');

    final root = db.collection('users').doc(uid).collection('solo').doc('data');
    final envsSnap = await root.collection('envelopes').get();
    final txSnap = await root.collection('transactions').get();

    // Batch in chunks of ~400 ops
    Future<void> chunk<T>(
      List<T> docs,
      void Function(WriteBatch b, T d) add,
    ) async {
      const maxOps = 400;
      var i = 0;
      while (i < docs.length) {
        final end = (i + maxOps > docs.length) ? docs.length : i + maxOps;
        final b = db.batch();
        for (final d in docs.sublist(i, end)) {
          add(b, d);
        }
        await b.commit();
        i = end;
      }
    }

    await chunk(envsSnap.docs, (b, d) {
      final data = d.data();
      final needsOwner =
          data['ownerId'] == null || data['ownerDisplayName'] == null;
      if (needsOwner) {
        b.update(d.reference, {'ownerId': uid, 'ownerDisplayName': ownerName});
      }
      // Optional: ensure createdAt/updatedAt exist
      if (data['createdAt'] == null) {
        b.update(d.reference, {'createdAt': FieldValue.serverTimestamp()});
      }
      b.update(d.reference, {'updatedAt': FieldValue.serverTimestamp()});
    });

    await chunk(txSnap.docs, (b, d) {
      final data = d.data();
      final needsOwner =
          data['ownerId'] == null || data['ownerDisplayName'] == null;
      if (needsOwner) {
        b.update(d.reference, {
          'ownerId': data['ownerId'] ?? uid,
          'ownerDisplayName': data['ownerDisplayName'] ?? ownerName,
        });
      }
      if (data['date'] == null) {
        b.update(d.reference, {'date': FieldValue.serverTimestamp()});
      }
    });
  }
}
