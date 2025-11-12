// Defines the Envelope data structure, which is shared and used by the repository.
import 'package:cloud_firestore/cloud_firestore.dart';

class Envelope {
  final String id;
  String name;
  final String userId; // The UID of the person who created the envelope
  double currentAmount;
  double? targetAmount; // Optional target
  String? groupId;

  // NOTE: isShared is determined by the workspace model, but included for simplicity
  final bool isShared;

  Envelope({
    required this.id,
    required this.name,
    required this.userId,
    this.currentAmount = 0.0,
    this.targetAmount,
    this.groupId,
    this.isShared = true,
  });

  Envelope copyWith({
    String? id,
    String? name,
    String? userId,
    double? currentAmount,
    double? targetAmount,
    String? groupId,
    bool? isShared,
  }) {
    return Envelope(
      id: id ?? this.id,
      name: name ?? this.name,
      userId: userId ?? this.userId,
      currentAmount: currentAmount ?? this.currentAmount,
      targetAmount: targetAmount ?? this.targetAmount,
      groupId: groupId ?? this.groupId,
      isShared: isShared ?? this.isShared,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'userId': userId,
      'currentAmount': currentAmount,
      'targetAmount': targetAmount,
      'groupId': groupId,
      'isShared': isShared,
    };
  }

  factory Envelope.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Envelope ${doc.id} has no data');
    }

    double _toDouble(dynamic v, {double fallback = 0.0}) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    return Envelope(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      userId: (data['userId'] as String?) ?? '',
      currentAmount: _toDouble(data['currentAmount'], fallback: 0.0),
      targetAmount: (data['targetAmount'] == null)
          ? null
          : _toDouble(data['targetAmount']),
      groupId: data['groupId'] as String?,
      isShared: (data['isShared'] as bool?) ?? true,
    );
  }
}
