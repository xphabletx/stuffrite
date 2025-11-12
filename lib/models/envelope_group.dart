// Defines the EnvelopeGroup data structure.
import 'package:cloud_firestore/cloud_firestore.dart';

class EnvelopeGroup {
  final String id;
  String name;
  final String userId; // The UID of the person who created the group

  EnvelopeGroup({required this.id, required this.name, required this.userId});

  EnvelopeGroup copyWith({String? id, String? name, String? userId}) {
    return EnvelopeGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      userId: userId ?? this.userId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'userId': userId,
      // no 'id' field inside doc data; Firestore doc id is the source of truth
    };
  }

  factory EnvelopeGroup.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('EnvelopeGroup ${doc.id} has no data');
    }
    return EnvelopeGroup(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      userId: (data['userId'] as String?) ?? '',
    );
  }
}
