import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/envelope.dart';
import '../models/transaction.dart';
import '../services/envelope_repo.dart';

class EditableEnvelopeHeader extends StatefulWidget {
  const EditableEnvelopeHeader({
    super.key,
    required this.envelope, // This is the live envelope from the stream
    required this.repo,
  });
  final Envelope envelope;
  final EnvelopeRepo repo;

  @override
  State<EditableEnvelopeHeader> createState() => _EditableEnvelopeHeaderState();
}

class _EditableEnvelopeHeaderState extends State<EditableEnvelopeHeader> {
  final nameCtrl = TextEditingController();
  final targetCtrl = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _updateControllers(widget.envelope);
  }

  @override
  void didUpdateWidget(covariant EditableEnvelopeHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the live data changes, update the text controllers *unless* we are currently editing/saving.
    // This prevents the user's input from being overwritten.
    if (!saving &&
        (widget.envelope.name != nameCtrl.text ||
            (widget.envelope.targetAmount ?? 0) !=
                (double.tryParse(targetCtrl.text.trim()) ?? 0))) {
      _updateControllers(widget.envelope);
    }
  }

  void _updateControllers(Envelope envelope) {
    nameCtrl.text = envelope.name;
    targetCtrl.text = envelope.targetAmount == null
        ? ''
        : envelope.targetAmount!.toStringAsFixed(2);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    double? newTarget;
    final targetText = targetCtrl.text.trim();

    if (targetText.isNotEmpty) {
      final t = double.tryParse(targetText);
      if (t == null || t < 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid target')));
        return;
      }
      newTarget = t;
    }

    setState(() => saving = true);
    try {
      await widget.repo.updateEnvelope(
        envelopeId: widget.envelope.id,
        name: nameCtrl.text.trim(),
        targetAmount: newTarget,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Envelope updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Envelope Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: targetCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Target Amount (optional)',
                prefixIcon: Icon(Icons.flag),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save'),
                onPressed: saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EnvelopeDetailScreen extends StatelessWidget {
  const EnvelopeDetailScreen({
    super.key,
    required this.envelope,
    required this.repo,
  });

  final Envelope envelope;
  final EnvelopeRepo repo;

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(symbol: '£');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          envelope.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      // Outer StreamBuilder: Get the live, most up-to-date Envelope object
      body: StreamBuilder<List<Envelope>>(
        stream: repo.envelopesStream,
        builder: (context, envelopeSnap) {
          // Find the most up-to-date version of this envelope
          final liveEnvelope = envelopeSnap.data?.firstWhere(
            (e) => e.id == envelope.id,
            orElse: () => envelope, // Fallback to initial envelope
          );

          if (liveEnvelope == null || !envelopeSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Inner StreamBuilder: Get the live Transactions list
          return StreamBuilder<List<Transaction>>(
            stream: repo.transactionsStream,
            builder: (context, txSnap) {
              final Map<String, String> envMap = {
                for (final e in (envelopeSnap.data ?? <Envelope>[]))
                  e.id: e.name,
              };
              final allTxs = txSnap.data ?? [];
              final transactions =
                  allTxs.where((t) => t.envelopeId == envelope.id).toList()
                    ..sort((a, b) => b.date.compareTo(a.date));

              double totalDeposited = transactions
                  .where((t) => t.type == TransactionType.deposit)
                  .fold(0.0, (sum, t) => sum + t.amount);
              double totalWithdrawn = transactions
                  .where((t) => t.type == TransactionType.withdrawal)
                  .fold(0.0, (sum, t) => sum + t.amount);
              double totalTransferred = transactions
                  .where((t) => t.type == TransactionType.transfer)
                  .fold(0.0, (sum, t) => sum + t.amount);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatCard(
                      'Current Balance',
                      liveEnvelope.currentAmount, // Use live data
                      Colors.black,
                      currencyFormatter,
                    ),
                    const SizedBox(height: 16),
                    EditableEnvelopeHeader(
                      envelope: liveEnvelope, // Pass live data to header
                      repo: repo,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Lifetime Summary',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 10),
                    _buildLifetimeStat(
                      'Target Amount',
                      liveEnvelope.targetAmount ?? 0.0, // Use live data
                      liveEnvelope.targetAmount != null
                          ? Colors.black
                          : Colors.grey,
                      currencyFormatter,
                    ),
                    _buildLifetimeStat(
                      'Amount until Target',
                      (liveEnvelope.targetAmount ?? 0.0) -
                          liveEnvelope.currentAmount, // Use live data
                      Colors.deepOrange,
                      currencyFormatter,
                    ),
                    _buildLifetimeStat(
                      'Total Deposited',
                      totalDeposited,
                      Colors.green,
                      currencyFormatter,
                    ),
                    _buildLifetimeStat(
                      'Total Withdrawn',
                      totalWithdrawn,
                      Colors.red,
                      currencyFormatter,
                    ),
                    _buildLifetimeStat(
                      'Total Transferred Out',
                      totalTransferred,
                      Colors.blue,
                      currencyFormatter,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Transaction Ledger',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 10),
                    if (transactions.isEmpty && !txSnap.hasData)
                      const Center(child: CircularProgressIndicator()),
                    if (transactions.isEmpty && txSnap.hasData)
                      const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: Text(
                            'No transactions recorded yet.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ...transactions.map(
                        (t) =>
                            _buildTransactionTile(t, currencyFormatter, envMap),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    double amount,
    Color color,
    NumberFormat currencyFormatter,
  ) {
    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: color.withAlpha(180), // Replaced withOpacity
              ),
            ),
            const SizedBox(height: 6),
            Text(
              currencyFormatter.format(amount),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLifetimeStat(
    String label,
    double amount,
    Color color,
    NumberFormat currencyFormatter,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            currencyFormatter.format(amount),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: amount >= 0
                  ? color
                  : Colors.red, // Show negative amounts in red
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(
    Transaction t,
    NumberFormat currencyFormatter,
    Map<String, String> envMap,
  ) {
    late final IconData icon;
    late final Color color;
    late final String sign;
    late final String titleText; // renamed from description for clarity

    if (t.type == TransactionType.transfer) {
      final peerName = envMap[t.transferPeerEnvelopeId ?? ''] ?? 'Unknown';
      final isIn = t.transferDirection == TransferDirection.in_;
      icon = Icons.compare_arrows;
      color = Colors.blue.shade700;
      sign = isIn ? '+' : '-';
      titleText = isIn ? 'Transfer from $peerName' : 'Transfer to $peerName';
    } else if (t.type == TransactionType.deposit) {
      icon = Icons.add_circle;
      color = Colors.green.shade700;
      sign = '+';
      titleText = t.description.isEmpty ? 'Deposit' : 'Deposit';
    } else {
      icon = Icons.remove_circle;
      color = Colors.red.shade700;
      sign = '-';
      titleText = t.description.isEmpty ? 'Withdrawal' : 'Withdrawal';
    }

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(titleText),
      // NEW: show notes if present
      subtitle: (t.description.isNotEmpty) ? Text(t.description) : null,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$sign${currencyFormatter.format(t.amount)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            DateFormat('MMM dd, hh:mm a').format(t.date),
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
