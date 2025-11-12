import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/envelope.dart';
import '../models/transaction.dart';
import '../services/envelope_repo.dart';
import '../screens/envelopes_detail_screen.dart';
import './quick_action_modal.dart';

// Helper for calculating progress
extension EnvelopeX on Envelope {
  double get progress {
    if (targetAmount == null || targetAmount! <= 0) return 0.0;
    return (currentAmount / targetAmount!).clamp(0.0, 1.0);
  }
}

class EnvelopeTile extends StatelessWidget {
  final Envelope envelope;
  final List<Envelope> allEnvelopes;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final EnvelopeRepo repo;
  final bool isMultiSelectMode; // Added to control quick actions/navigation

  const EnvelopeTile({
    super.key,
    required this.envelope,
    required this.allEnvelopes,
    required this.repo,
    this.isSelected = false,
    this.onLongPress,
    this.onTap,
    this.isMultiSelectMode = false,
  });

  void _openDetail(BuildContext context) {
    // Only allow navigation if not in multi-select mode
    if (isMultiSelectMode) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EnvelopeDetailScreen(envelope: envelope, repo: repo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '£');

    return InkWell(
      onLongPress: onLongPress,
      onTap:
          onTap ??
          () => _openDetail(context), // Use _openDetail if onTap is null
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05), // Lighter shadow
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isSelected
                ? Colors.black
                : Colors.transparent, // Highlight with black border
            width: isSelected ? 2 : 0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row (name + selection indicator)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    envelope.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (isMultiSelectMode)
                  Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected ? Colors.black : Colors.grey,
                    size: 24,
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Balance + target/progress + quick actions
            Row(
              children: [
                // Balance + (optional) progress
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currency.format(envelope.currentAmount),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (envelope.targetAmount != null) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: envelope.progress,
                            backgroundColor: Colors.grey.shade200,
                            minHeight: 8,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.black,
                            ), // Black progress bar
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Target: ${currency.format(envelope.targetAmount)} (${(envelope.progress * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (!isMultiSelectMode) ...[
                  const SizedBox(width: 16),
                  // Quick actions: + / − / ↔
                  _btn(
                    icon: Icons.add,
                    color: Colors.green.shade800,
                    onTap: () => _openAction(context, TransactionType.deposit),
                  ),
                  _btn(
                    icon: Icons.remove,
                    color: Colors.red.shade800,
                    onTap: () =>
                        _openAction(context, TransactionType.withdrawal),
                  ),
                  _btn(
                    icon: Icons.compare_arrows,
                    color: Colors.blue.shade800,
                    onTap: () => _openAction(context, TransactionType.transfer),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openAction(BuildContext context, TransactionType type) async {
    // Prevent quick actions in multi-select mode
    if (isMultiSelectMode) return;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickActionModal(
        envelope: envelope,
        type: type,
        allEnvelopes: allEnvelopes.where((e) => e.id != envelope.id).toList(),
        repo: repo,
      ),
    );
  }

  Widget _btn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        onPressed: onTap,
        constraints: BoxConstraints.tight(const Size(40, 40)),
      ),
    );
  }
}
