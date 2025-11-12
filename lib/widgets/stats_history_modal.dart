import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/envelope.dart';
import '../models/envelope_group.dart';
import '../models/transaction.dart';
import '../services/envelope_repo.dart';

class StatsHistoryModal extends StatefulWidget {
  final List<Envelope> envelopes;
  final List<EnvelopeGroup> groups;
  final List<Transaction> transactions; // Corrected model name
  final List<String> initialSelection;
  final EnvelopeRepo repo; // Added repository instance

  const StatsHistoryModal({
    super.key,
    required this.envelopes,
    required this.groups,
    required this.transactions,
    required this.repo,
    this.initialSelection = const [],
  });

  @override
  State<StatsHistoryModal> createState() => _StatsHistoryModalState();
}

class _StatsHistoryModalState extends State<StatsHistoryModal> {
  final currency = NumberFormat.currency(symbol: '£');
  final selected = <String>{};
  bool myOnly = false; // Filter toggle state
  DateTime start = DateTime.now().subtract(const Duration(days: 30));
  DateTime end = DateTime.now().add(
    const Duration(hours: 1),
  ); // Ensure 'today' transactions are included

  // Get current user ID for filtering (will be anonymous for now)
  final String _currentUserId =
      FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  @override
  void initState() {
    super.initState();
    selected.addAll(widget.initialSelection);

    // If no initial selection, default to ALL envelopes
    if (selected.isEmpty) {
      selected.addAll(widget.envelopes.map((e) => e.id));
      selected.addAll(widget.groups.map((g) => g.id));
    }
  }

  // Filters the full list of envelopes/groups based on the 'myOnly' toggle
  List<Envelope> get _filterableEnvelopes {
    if (!myOnly) return widget.envelopes;
    return widget.envelopes.where((e) => e.userId == _currentUserId).toList();
  }

  List<EnvelopeGroup> get _filterableGroups {
    if (!myOnly) return widget.groups;
    return widget.groups.where((g) => g.userId == _currentUserId).toList();
  }

  // Gets the final list of envelopes included in the current analysis, considering multi-selection
  List<Envelope> get _chosen {
    final envs = <Envelope>[];
    final selectedGroupIds = selected
        .where((id) => widget.groups.any((g) => g.id == id))
        .toSet();
    final selectedEnvelopeIds = selected
        .where((id) => widget.envelopes.any((e) => e.id == id))
        .toSet();

    for (final e in _filterableEnvelopes) {
      // 1. Check if the envelope itself is selected
      // 2. Check if the envelope belongs to a selected group
      if (selectedEnvelopeIds.contains(e.id) ||
          (e.groupId != null && selectedGroupIds.contains(e.groupId))) {
        envs.add(e);
      }
    }
    return envs.toSet().toList();
  }

  // Gets the final list of transactions for the analysis
  List<Transaction> get _txs {
    final ids = _chosen.map((e) => e.id).toSet();
    return widget.transactions.where((t) {
      final sel = ids.contains(t.envelopeId);
      final inRange = !t.date.isBefore(start) && t.date.isBefore(end);
      return sel && inRange;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  double get totalTarget =>
      _chosen.fold(0.0, (s, e) => s + (e.targetAmount ?? 0));
  double get totalSaved => _chosen.fold(0.0, (s, e) => s + e.currentAmount);
  double get pct =>
      totalTarget > 0 ? (totalSaved / totalTarget).clamp(0.0, 1.0) * 100 : 0.0;

  double get totDep => _txs
      .where((t) => t.type == TransactionType.deposit)
      .fold(0.0, (s, t) => s + t.amount);
  double get totWdr => _txs
      .where((t) => t.type == TransactionType.withdrawal)
      .fold(0.0, (s, t) => s + t.amount);
  double get totTrn => _txs
      .where((t) => t.type == TransactionType.transfer)
      .fold(0.0, (s, t) => s + t.amount);

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: start, end: end),
    );
    if (r != null) {
      // Set end date to midnight of the end day to include all transactions up to then
      setState(() {
        start = r.start;
        end = r.end
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      builder: (context, ctrl) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
            ],
          ),
          child: CustomScrollView(
            controller: ctrl,
            slivers: [
              SliverAppBar(
                automaticallyImplyLeading: false,
                pinned: true,
                backgroundColor: Colors.white,
                title: const Text(
                  'Statistics & History',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(
                    160,
                  ), // Increased height for the toggle
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Date Range Picker ---
                        InkWell(
                          onTap: _pickRange,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.calendar_today, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  '${DateFormat('MMM d, yyyy').format(start)} - ${DateFormat('MMM d, yyyy').format(end)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // --- Filter Toggle ---
                        Row(
                          children: [
                            const Text(
                              'Show My Envelopes Only',
                              style: TextStyle(fontSize: 16),
                            ),
                            const Spacer(),
                            Switch(
                              value: myOnly,
                              onChanged: (v) => setState(() => myOnly = v),
                              activeColor: Colors.black,
                            ),
                          ],
                        ),
                        const Divider(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Select Items for Stats',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Envelopes Checklist
                        ..._filterableEnvelopes.map(
                          (e) => CheckboxListTile(
                            title: Text(e.name),
                            value: selected.contains(e.id),
                            onChanged: (v) => setState(() {
                              v! ? selected.add(e.id) : selected.remove(e.id);
                            }),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            activeColor: Colors.black,
                          ),
                        ),
                        const Divider(),

                        // Groups Checklist
                        ..._filterableGroups.map(
                          (g) => CheckboxListTile(
                            title: Text('${g.name} (Group)'),
                            value: selected.contains(g.id),
                            onChanged: (v) => setState(() {
                              v! ? selected.add(g.id) : selected.remove(g.id);
                            }),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            activeColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Summary for ${_chosen.length} Envelopes',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // Statistics based on your requirements
                        _row(
                          'Total Envelopes Selected',
                          _chosen.length.toString(),
                        ),
                        _row(
                          'Total Target Amount',
                          currency.format(totalTarget),
                        ),
                        _row(
                          'Total Saved Amount',
                          currency.format(totalSaved),
                          bold: true,
                        ),
                        _row(
                          'Percent Towards Target',
                          '${pct.toStringAsFixed(1)}%',
                          bold: true,
                        ),
                        const Divider(height: 24),

                        // Transaction Summary based on date range
                        Text(
                          'Transactions (${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d').format(end)})',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _row(
                          'Total Deposited',
                          currency.format(totDep),
                          bold: true,
                        ),
                        _row('Total Withdrawn', currency.format(totWdr)),
                        _row('Total Transferred Out', currency.format(totTrn)),
                        const SizedBox(height: 8),

                        const Divider(),
                        const Text(
                          'Transaction Details',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Transaction List
                        ..._txs.map((t) {
                          final envelopeName = _chosen
                              .firstWhere(
                                (e) => e.id == t.envelopeId,
                                orElse: () => Envelope(
                                  id: '',
                                  name: 'Unknown',
                                  userId: '',
                                ),
                              )
                              .name;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${t.type.name} on $envelopeName',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        t.description.isEmpty
                                            ? 'N/A'
                                            : t.description,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _signed(t),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _col(t),
                                      ),
                                    ),
                                    Text(
                                      DateFormat('MMM dd').format(t.date),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                        if (_txs.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(30),
                              child: Text(
                                'No transactions in this range for selected items.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                        const SizedBox(height: 50),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String k, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
        Text(
          v,
          style: TextStyle(
            fontSize: 18,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    ),
  );

  String _signed(Transaction t) {
    switch (t.type) {
      case TransactionType.deposit:
        return '+${currency.format(t.amount)}';
      case TransactionType.withdrawal:
        return '-${currency.format(t.amount)}';
      case TransactionType.transfer:
        return '→${currency.format(t.amount)}';
    }
  }

  Color _col(Transaction t) {
    switch (t.type) {
      case TransactionType.deposit:
        return Colors.green.shade800;
      case TransactionType.withdrawal:
        return Colors.red.shade800;
      case TransactionType.transfer:
        return Colors.blue.shade800;
    }
  }
}
