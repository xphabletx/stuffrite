// lib/screens/group_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/envelope.dart';
import '../models/envelope_group.dart';
import '../models/transaction.dart';
import '../services/envelope_repo.dart';
import '../services/group_repo.dart';
import '../widgets/envelope_tile.dart';
import '../widgets/group_editor.dart' as editor;
import '../screens/envelopes_detail_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.group,
    required this.groupRepo,
    required this.envelopeRepo,
  });

  final EnvelopeGroup group;
  final GroupRepo groupRepo;
  final EnvelopeRepo envelopeRepo;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final currency = NumberFormat.currency(symbol: '£');

  // selection for bulk actions
  bool isMulti = false;
  final selected = <String>{};

  // date range for transactions section
  DateTime start = DateTime.now().subtract(const Duration(days: 30));
  DateTime end = DateTime.now().add(
    const Duration(hours: 1),
  ); // include "today"

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: start, end: end),
    );
    if (r != null) {
      setState(() {
        start = DateTime(r.start.year, r.start.month, r.start.day);
        end = DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59, 999);
      });
    }
  }

  void _toggle(String id) {
    setState(() {
      if (selected.contains(id)) {
        selected.remove(id);
      } else {
        selected.add(id);
      }
      isMulti = selected.isNotEmpty;
      if (!isMulti) selected.clear();
    });
  }

  Future<void> _renameGroup() async {
    final ctrl = TextEditingController(text: widget.group.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final name = ctrl.text.trim();
      if (name.isEmpty) return;
      await widget.groupRepo.renameGroup(groupId: widget.group.id, name: name);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group renamed')));
    }
  }

  Future<void> _editMembership() async {
    await editor.showGroupEditor(
      context: context,
      groupRepo: widget.groupRepo,
      envelopeRepo: widget.envelopeRepo,
      group: widget.group,
    );
  }

  Future<void> _deleteGroupConfirm(List<Envelope> inGroupEnvelopes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Group?'),
        content: Text(
          'This will remove the group "${widget.group.name}".\n\n'
          'Envelopes remain, but their group will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    // Clear all memberships then delete the group
    await widget.envelopeRepo.updateGroupMembership(
      groupId: widget.group.id,
      newEnvelopeIds: <String>{},
      allEnvelopesStream: widget.envelopeRepo.envelopesStream,
    );
    await widget.groupRepo.deleteGroup(groupId: widget.group.id);

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Group deleted')));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Envelope>>(
      stream: widget.envelopeRepo.envelopesStream,
      builder: (_, sEnv) {
        final envs = sEnv.data ?? [];
        final inGroup = envs.where((e) => e.groupId == widget.group.id).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        final totTarget = inGroup.fold<double>(
          0,
          (s, e) => s + (e.targetAmount ?? 0),
        );
        final totSaved = inGroup.fold<double>(0, (s, e) => s + e.currentAmount);
        final pct = totTarget > 0 ? (totSaved / totTarget) * 100 : 0.0;

        return StreamBuilder<List<Transaction>>(
          stream: widget.envelopeRepo.transactionsStream,
          builder: (_, sTx) {
            final txs = sTx.data ?? [];
            final groupIds = inGroup.map((e) => e.id).toSet();
            final shownTxs = txs.where((t) {
              final inChosen = groupIds.contains(t.envelopeId);
              final inRange = !t.date.isBefore(start) && t.date.isBefore(end);
              return inChosen && inRange;
            }).toList()..sort((a, b) => b.date.compareTo(a.date));

            final totDep = shownTxs
                .where((t) => t.type == TransactionType.deposit)
                .fold<double>(0, (s, t) => s + t.amount);
            final totWdr = shownTxs
                .where((t) => t.type == TransactionType.withdrawal)
                .fold<double>(0, (s, t) => s + t.amount);
            final totTrnOut = shownTxs
                .where(
                  (t) =>
                      t.type == TransactionType.transfer &&
                      t.transferDirection == TransferDirection.out_,
                )
                .fold<double>(0, (s, t) => s + t.amount);

            return Scaffold(
              appBar: AppBar(
                title: Text(
                  widget.group.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Rename group',
                    icon: const Icon(Icons.edit),
                    onPressed: _renameGroup,
                  ),
                  IconButton(
                    tooltip: 'Edit membership',
                    icon: const Icon(Icons.people_alt),
                    onPressed: _editMembership,
                  ),
                  IconButton(
                    tooltip: 'Delete group',
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    onPressed: () => _deleteGroupConfirm(inGroup),
                  ),
                ],
              ),
              body:
                  (sEnv.connectionState == ConnectionState.waiting &&
                      envs.isEmpty)
                  ? const Center(child: CircularProgressIndicator())
                  : CustomScrollView(
                      slivers: [
                        // ===== Header stats =====
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: _StatsHeader(
                              count: inGroup.length,
                              totalSaved: totSaved,
                              totalTarget: totTarget,
                              percent: pct,
                              totDep: totDep,
                              totWdr: totWdr,
                              totTrnOut: totTrnOut,
                              onPickRange: _pickRange,
                              rangeLabel:
                                  '${DateFormat('MMM d, yyyy').format(start)} — ${DateFormat('MMM d, yyyy').format(end)}',
                              currency: currency,
                            ),
                          ),
                        ),

                        // ===== Envelopes in group =====
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Row(
                              children: [
                                const Text(
                                  'Envelopes in this Group',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                if (isMulti)
                                  TextButton(
                                    onPressed: () => setState(() {
                                      selected.clear();
                                      isMulti = false;
                                    }),
                                    child: const Text('Cancel'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SliverList.separated(
                          itemBuilder: (_, i) {
                            final e = inGroup[i];
                            final isSel = selected.contains(e.id);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: EnvelopeTile(
                                envelope: e,
                                allEnvelopes: envs,
                                isSelected: isSel,
                                onLongPress: () => _toggle(e.id),
                                onTap: isMulti
                                    ? () => _toggle(e.id)
                                    : () {
                                        // open details screen (keeps parity with home)
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => /* reuse existing */
                                                EnvelopeDetailScreen(
                                                  envelope: e,
                                                  repo: widget.envelopeRepo,
                                                ),
                                          ),
                                        );
                                      },
                                repo: widget.envelopeRepo,
                                isMultiSelectMode: isMulti,
                              ),
                            );
                          },
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemCount: inGroup.length,
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),

                        // ===== Transactions =====
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: const Text(
                              'Transactions',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (shownTxs.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  'No transactions in this range.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                          )
                        else
                          SliverList.separated(
                            itemBuilder: (_, i) {
                              final t = shownTxs[i];
                              final label = switch (t.type) {
                                TransactionType.deposit =>
                                  'Deposit on ${_envName(t.envelopeId, inGroup)}',
                                TransactionType.withdrawal =>
                                  'Withdrawal on ${_envName(t.envelopeId, inGroup)}',
                                TransactionType.transfer =>
                                  (t.transferDirection == TransferDirection.in_)
                                      ? 'Transfer From ${_envName(t.transferPeerEnvelopeId, inGroup)}'
                                      : 'Transfer To ${_envName(t.transferPeerEnvelopeId, inGroup)}',
                              };
                              final color = _col(t);
                              final signed = _signed(t);

                              return ListTile(
                                dense: true,
                                title: Text(label),
                                subtitle: t.description.isNotEmpty
                                    ? Text(
                                        t.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                                trailing: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      signed,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: color,
                                      ),
                                    ),
                                    Text(
                                      DateFormat(
                                        'MMM dd, HH:mm',
                                      ).format(t.date),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemCount: shownTxs.length,
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ),
              floatingActionButton: isMulti
                  ? FloatingActionButton.extended(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.delete_forever),
                      label: Text('Delete (${selected.length})'),
                      onPressed: () async {
                        await widget.envelopeRepo.deleteEnvelopes(selected);
                        setState(() {
                          selected.clear();
                          isMulti = false;
                        });
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Deleted envelopes')),
                        );
                      },
                    )
                  : FloatingActionButton.extended(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      icon: const Icon(Icons.people_alt),
                      label: const Text('Edit Membership'),
                      onPressed: _editMembership,
                    ),
            );
          },
        );
      },
    );
  }

  String _envName(String? id, List<Envelope> inGroup) {
    if (id == null) return 'Unknown';
    return inGroup
        .firstWhere(
          (e) => e.id == id,
          orElse: () => Envelope(id: '', name: 'Unknown', userId: ''),
        )
        .name;
  }

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

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({
    required this.count,
    required this.totalSaved,
    required this.totalTarget,
    required this.percent,
    required this.totDep,
    required this.totWdr,
    required this.totTrnOut,
    required this.onPickRange,
    required this.rangeLabel,
    required this.currency,
  });

  final int count;
  final double totalSaved;
  final double totalTarget;
  final double percent;
  final double totDep;
  final double totWdr;
  final double totTrnOut;
  final VoidCallback onPickRange;
  final String rangeLabel;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final pctStr = '${percent.isFinite ? percent.toStringAsFixed(1) : '0.0'}%';

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          children: [
            // Top row: count + date range
            Row(
              children: [
                Text(
                  '$count envelopes',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: onPickRange,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        rangeLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Totals + progress
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    'Total Saved',
                    currency.format(totalSaved),
                    bold: true,
                  ),
                ),
                Expanded(
                  child: _statTile(
                    'Total Target',
                    currency.format(totalTarget),
                  ),
                ),
                Expanded(child: _statTile('To Target', pctStr, bold: true)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: totalTarget > 0
                    ? (totalSaved / totalTarget).clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    'Deposited',
                    currency.format(totDep),
                    bold: true,
                  ),
                ),
                Expanded(
                  child: _statTile('Withdrawn', currency.format(totWdr)),
                ),
                Expanded(
                  child: _statTile(
                    'Transferred Out',
                    currency.format(totTrnOut),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String k, String v, {bool bold = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: TextStyle(color: Colors.grey.shade600)),
      const SizedBox(height: 4),
      Text(
        v,
        style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600),
      ),
    ],
  );
}
