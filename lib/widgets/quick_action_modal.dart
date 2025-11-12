// lib/widgets/quick_action_modal.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/envelope.dart';
import '../models/transaction.dart';
import '../services/envelope_repo.dart';

class QuickActionModal extends StatefulWidget {
  final Envelope envelope; // SOURCE envelope for all actions
  final TransactionType type;
  final List<Envelope> allEnvelopes; // potential TARGETS for transfer
  final EnvelopeRepo repo;

  const QuickActionModal({
    super.key,
    required this.envelope,
    required this.type,
    required this.allEnvelopes,
    required this.repo,
  });

  @override
  State<QuickActionModal> createState() => _QuickActionModalState();
}

class _QuickActionModalState extends State<QuickActionModal> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  Envelope? _target;
  bool _loading = false;

  String get _title => switch (widget.type) {
    TransactionType.deposit => 'Deposit into ${widget.envelope.name}',
    TransactionType.withdrawal => 'Withdraw from ${widget.envelope.name}',
    TransactionType.transfer => 'Transfer from ${widget.envelope.name}',
  };

  String get _verb => switch (widget.type) {
    TransactionType.deposit => 'Deposit',
    TransactionType.withdrawal => 'Withdraw',
    TransactionType.transfer => 'Transfer',
  };

  bool get _isOwner => widget.envelope.userId == widget.repo.currentUserId;

  Future<void> _submit() async {
    // Permissions (client-side):
    // - Only owner can deposit/withdraw/transfer OUT of an envelope.
    // - Anyone may transfer TO someone else’s envelope by starting from their own source envelope.
    if ((widget.type != TransactionType.transfer || !_isOwner) &&
        (widget.type == TransactionType.deposit ||
            widget.type == TransactionType.withdrawal ||
            widget.type == TransactionType.transfer)) {
      if (!_isOwner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the owner can perform this action.'),
          ),
        );
        return;
      }
    }

    final a = double.tryParse(_amount.text);
    if (a == null || a <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      return;
    }
    if (widget.type == TransactionType.transfer && _target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a target envelope.')),
      );
      return;
    }
    if ((widget.type == TransactionType.withdrawal ||
            widget.type == TransactionType.transfer) &&
        a > widget.envelope.currentAmount) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Insufficient funds.')));
      return;
    }

    setState(() => _loading = true);

    // Build new balances
    Envelope from = widget.envelope;
    Envelope? to;

    switch (widget.type) {
      case TransactionType.deposit:
        from = Envelope(
          id: from.id,
          name: from.name,
          userId: from.userId,
          currentAmount: from.currentAmount + a,
          targetAmount: from.targetAmount,
          groupId: from.groupId,
          isShared: from.isShared,
        );
        break;

      case TransactionType.withdrawal:
        from = Envelope(
          id: from.id,
          name: from.name,
          userId: from.userId,
          currentAmount: from.currentAmount - a,
          targetAmount: from.targetAmount,
          groupId: from.groupId,
          isShared: from.isShared,
        );
        break;

      case TransactionType.transfer:
        to = _target!;
        from = Envelope(
          id: from.id,
          name: from.name,
          userId: from.userId,
          currentAmount: from.currentAmount - a,
          targetAmount: from.targetAmount,
          groupId: from.groupId,
          isShared: from.isShared,
        );
        to = Envelope(
          id: to.id,
          name: to.name,
          userId: to.userId,
          currentAmount: to.currentAmount + a,
          targetAmount: to.targetAmount,
          groupId: to.groupId,
          isShared: to.isShared,
        );
        break;
    }

    final userId = widget.repo.currentUserId.isNotEmpty
        ? widget.repo.currentUserId
        : (FirebaseAuth.instance.currentUser?.uid ?? 'anonymous');

    final tx = Transaction(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      envelopeId: widget.envelope.id,
      type: widget.type,
      amount: a,
      date: DateTime.now(),
      description: _notes.text.trim(),
      userId: userId,
      transferPeerEnvelopeId: null,
      transferLinkId: null,
      transferDirection: null,
    );

    try {
      await widget.repo.recordTransaction(tx, from: from, to: to);
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$_verb successful')));
  }

  @override
  Widget build(BuildContext context) {
    final canAct =
        _isOwner ||
        widget.type == TransactionType.transfer; // others can open transfer UI
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
            ],
          ),
          child: AbsorbPointer(
            absorbing: !canAct,
            child: Opacity(
              opacity: canAct ? 1 : 0.6,
              child: Padding(
                padding: EdgeInsets.only(
                  top: 25,
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(height: 30),
                      TextField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Amount (£)',
                          hintText: 'e.g., 150.00',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: const Icon(Icons.monetization_on),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _notes,
                        decoration: InputDecoration(
                          labelText: 'Notes (optional)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: const Icon(Icons.note_alt_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (widget.type == TransactionType.transfer)
                        DropdownButtonFormField<Envelope>(
                          isExpanded: true,
                          items: widget.allEnvelopes
                              .where((e) => e.id != widget.envelope.id)
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                    '${e.name}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _target = v),
                          decoration: InputDecoration(
                            labelText: 'Transfer to',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            prefixIcon: const Icon(Icons.compare_arrows),
                          ),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _submit,
                          icon: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(
                            _verb,
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      if (!canAct) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Only the owner can deposit, withdraw, or transfer out of this envelope. You can transfer to it by starting from one of your own envelopes.',
                          style: TextStyle(color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
