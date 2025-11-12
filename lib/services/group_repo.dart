import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'envelope_repo.dart';

class GroupRepo {
  GroupRepo(this._db, this._envelopeRepo);

  final fs.FirebaseFirestore _db;
  final EnvelopeRepo _envelopeRepo;

  bool get _inWorkspace => _envelopeRepo.inWorkspace;
  String? get _workspaceId => _envelopeRepo.workspaceId;
  String get _userId => _envelopeRepo.currentUserId!;

  fs.CollectionReference<Map<String, dynamic>> _groupsCol() {
    if (_inWorkspace) {
      return _db
          .collection('users')
          .doc(_userId)
          .collection('solo')
          .doc('data')
          .collection('groups');
    } else {
      return _db
          .collection('users')
          .doc(_userId)
          .collection('solo')
          .doc('data')
          .collection('groups');
    }
  }

  Future<String> createGroup({required String name}) async {
    final ref = _groupsCol().doc();
    await ref.set({
      'id': ref.id,
      'name': name,
      'createdAt': fs.FieldValue.serverTimestamp(),
      'updatedAt': fs.FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> renameGroup({
    required String groupId,
    required String name,
  }) async {
    await _groupsCol().doc(groupId).update({
      'name': name,
      'updatedAt': fs.FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGroup({required String groupId}) async {
    await _groupsCol().doc(groupId).delete();
  }
}
