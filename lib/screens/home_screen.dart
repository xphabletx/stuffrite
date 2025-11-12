// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';

import '../services/envelope_repo.dart';
import '../services/group_repo.dart';
import '../services/auth_service.dart';
import '../services/run_migrations_once.dart'; // ADD THIS

import '../widgets/envelope_tile.dart';
import '../widgets/envelope_creator.dart';
import '../widgets/group_editor.dart' as editor;

import '../models/envelope.dart';
import '../models/envelope_group.dart';
import '../models/transaction.dart';

import 'envelopes_detail_screen.dart';
import 'workspace_gate.dart';
import 'stats_history_screen.dart';

// Unified SpeedDial child style
SpeedDialChild sdChild({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  return SpeedDialChild(
    child: Icon(icon, color: Colors.black),
    backgroundColor: Colors.grey.shade200,
    label: label,
    labelBackgroundColor: Colors.white,
    onTap: onTap,
  );
}

const String kPrefsKeyWorkspace = 'last_workspace_id';
const String kPrefsKeyWorkspaceName = 'last_workspace_name';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repo});
  final EnvelopeRepo repo;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // Cache a friendly workspace name for the chip
  String? _workspaceName;

  GroupRepo get _groupRepo => GroupRepo(widget.repo.db, widget.repo);

  @override
  void initState() {
    super.initState();
    _restoreLastWorkspaceName();

    // Run migrations once per build for the current user on first entry
    // to Home. Safe to call every app start; internally it no-ops if already run.
    Future.microtask(() {
      return runMigrationsOncePerBuild(
        db: widget.repo.db,
        explicitUid: widget.repo.currentUserId,
      );
    });
  }

  Future<void> _restoreLastWorkspaceName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _workspaceName = prefs.getString(kPrefsKeyWorkspaceName));
  }

  Future<void> _saveWorkspaceSelection({String? id, String? name}) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null || id.isEmpty) {
      await prefs.remove(kPrefsKeyWorkspace);
      await prefs.remove(kPrefsKeyWorkspaceName);
    } else {
      await prefs.setString(kPrefsKeyWorkspace, id);
      if (name != null && name.isNotEmpty) {
        await prefs.setString(kPrefsKeyWorkspaceName, name);
      }
    }
  }

  Future<String?> _fetchWorkspaceName(String id) async {
    try {
      final snap = await widget.repo.db.collection('workspaces').doc(id).get();
      if (!snap.exists) return null;
      final data = snap.data();
      return (data?['name'] as String?)?.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _openWorkspaceGate() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (gateCtx) => WorkspaceGate(
          onJoined: (wsId) async {
            // Set repo context first
            await widget.repo.setWorkspace(wsId);

            // Try to fetch a friendly name (the implicit name = joinCode)
            final fetchedName = await _fetchWorkspaceName(wsId);
            setState(() {
              _workspaceName = fetchedName;
            });

            // Persist both id + name locally
            await _saveWorkspaceSelection(id: wsId, name: fetchedName);

            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Joined workspace.')));
            // Gate pops itself; no pop() here.
          },
        ),
      ),
    );
  }

  Future<void> _leaveWorkspace() async {
    await _saveWorkspaceSelection(id: null, name: null);
    widget.repo.setWorkspace(null);
    if (!mounted) return;
    setState(() => _workspaceName = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Left workspace. Now in Solo Mode.')),
    );
  }

  String get _workspaceLabel {
    if (!widget.repo.inWorkspace) return 'Solo Mode';
    final id = widget.repo.workspaceId!;
    final short = id.length > 6 ? id.substring(0, 6) : id;
    return _workspaceName?.isNotEmpty == true
        ? _workspaceName!
        : 'Workspace: $short';
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _AllEnvelopes(repo: widget.repo, groupRepo: _groupRepo),
      _GroupsPage(repo: widget.repo, groupRepo: _groupRepo),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Team Envelopes',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.black,
          ),
        ),
        elevation: 0,
        actions: [
          // Sign out
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () async {
              await AuthService.signOut();
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Signed out')));
              // AuthGate takes over after this.
            },
          ),

          // Workspace chip + menu
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PopupMenuButton<String>(
              tooltip: 'Workspace',
              onSelected: (value) async {
                switch (value) {
                  case 'join':
                    await _openWorkspaceGate();
                    break;
                  case 'leave':
                    await _leaveWorkspace();
                    break;
                  case 'manage':
                    // Open the same WorkspaceGate in Manage mode
                    if (!mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WorkspaceGate(
                          onJoined: (_) {}, // not used in manage mode
                          workspaceId:
                              widget.repo.workspaceId!, // current workspace
                        ),
                      ),
                    );
                    setState(() {}); // refresh label if nickname changed
                    break;
                }
              },
              itemBuilder: (ctx) {
                final items = <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Text(
                      _workspaceLabel,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const PopupMenuDivider(),
                ];
                if (widget.repo.inWorkspace) {
                  items.addAll([
                    const PopupMenuItem<String>(
                      value: 'manage',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.settings),
                        title: Text('Workspace settings / rename'),
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'leave',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.logout),
                        title: Text('Leave workspace'),
                      ),
                    ),
                  ]);
                } else {
                  items.add(
                    const PopupMenuItem<String>(
                      value: 'join',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.group_add),
                        title: Text('Create / Join workspace'),
                      ),
                    ),
                  );
                }
                return items;
              },
              child: Chip(
                label: Text(
                  _workspaceLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                avatar: Icon(
                  widget.repo.inWorkspace ? Icons.groups : Icons.person,
                  size: 18,
                ),
                shape: StadiumBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey.shade600,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Envelopes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_alt_outlined),
            activeIcon: Icon(Icons.people_alt),
            label: 'Groups',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }
}

// ====== All Envelopes ======
class _AllEnvelopes extends StatefulWidget {
  const _AllEnvelopes({required this.repo, required this.groupRepo});
  final EnvelopeRepo repo;
  final GroupRepo groupRepo;

  @override
  State<_AllEnvelopes> createState() => _AllEnvelopesState();
}

class _AllEnvelopesState extends State<_AllEnvelopes> {
  bool isMulti = false;
  final selected = <String>{};

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

  void _openDetails(Envelope envelope) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            EnvelopeDetailScreen(envelope: envelope, repo: widget.repo),
      ),
    );
  }

  void _openStatsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StatsHistoryScreen(repo: widget.repo)),
    );
  }

  Future<void> _openGroupCreator() async {
    await editor.showGroupEditor(
      context: context,
      groupRepo: widget.groupRepo,
      envelopeRepo: widget.repo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Envelope>>(
      stream: widget.repo.envelopesStream,
      builder: (c1, s1) {
        final envs = s1.data ?? [];
        return StreamBuilder<List<EnvelopeGroup>>(
          stream: widget.repo.groupsStream,
          builder: (c2, s2) {
            final _unusedGroups = s2.data ?? const <EnvelopeGroup>[];
            return StreamBuilder<List<Transaction>>(
              stream: widget.repo.transactionsStream,
              builder: (c3, s3) {
                final _ = s3.data ?? []; // txs not directly used here

                final sortedEnvs = envs.toList()
                  ..sort((a, b) {
                    if (a.groupId != null && b.groupId == null) return -1;
                    if (a.groupId == null && b.groupId != null) return 1;
                    return a.name.compareTo(b.name);
                  });

                return Scaffold(
                  appBar: AppBar(
                    title: const Text(
                      'All Envelopes',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                    elevation: 0,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.bar_chart_sharp, size: 28),
                        onPressed: _openStatsScreen,
                        color: Colors.black,
                      ),
                    ],
                  ),
                  body: sortedEnvs.isEmpty && !s1.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: sortedEnvs.map((e) {
                            final isSel = selected.contains(e.id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: EnvelopeTile(
                                envelope: e,
                                allEnvelopes: envs,
                                isSelected: isSel,
                                onLongPress: () => _toggle(e.id),
                                onTap: isMulti
                                    ? () => _toggle(e.id)
                                    : () => _openDetails(e),
                                repo: widget.repo,
                                isMultiSelectMode: isMulti,
                              ),
                            );
                          }).toList(),
                        ),
                  floatingActionButton: SpeedDial(
                    icon: isMulti ? Icons.check : Icons.add,
                    activeIcon: Icons.close,
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    overlayColor: Colors.black,
                    overlayOpacity: 0.5,
                    spacing: 12,
                    spaceBetweenChildren: 8,
                    children: isMulti
                        ? [
                            sdChild(
                              icon: Icons.delete_forever,
                              label: 'Delete (${selected.length})',
                              onTap: () async {
                                await widget.repo.deleteEnvelopes(selected);
                                setState(() {
                                  selected.clear();
                                  isMulti = false;
                                });
                              },
                            ),
                            sdChild(
                              icon: Icons.cancel,
                              label: 'Cancel Selection',
                              onTap: () => setState(() {
                                selected.clear();
                                isMulti = false;
                              }),
                            ),
                          ]
                        : [
                            sdChild(
                              icon: Icons.people_alt, // group icon
                              label: 'New Group',
                              onTap: _openGroupCreator,
                            ),
                            sdChild(
                              icon: Icons.mail_outline, // envelope-looking
                              label: 'New Envelope',
                              onTap: () async {
                                await showEnvelopeCreator(
                                  context,
                                  repo: widget.repo,
                                );
                              },
                            ),
                            sdChild(
                              icon: Icons.edit_note, // multi-select
                              label: 'Enter Multi-Select Mode',
                              onTap: () => setState(() => isMulti = true),
                            ),
                          ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ====== Groups ======
class _GroupsPage extends StatelessWidget {
  const _GroupsPage({required this.repo, required this.groupRepo});
  final EnvelopeRepo repo;
  final GroupRepo groupRepo;

  Map<String, dynamic> _statsFor(EnvelopeGroup g, List<Envelope> envs) {
    final inGroup = envs.where((e) => e.groupId == g.id).toList();
    final totTarget = inGroup.fold(0.0, (s, e) => s + (e.targetAmount ?? 0));
    final totSaved = inGroup.fold(0.0, (s, e) => s + e.currentAmount);
    final pct = totTarget > 0
        ? (totSaved / totTarget).clamp(0.0, 1.0) * 100
        : 0.0;

    final overallTotalSaved = envs.fold(0.0, (s, e) => s + e.currentAmount);
    final overallGroupPercent = overallTotalSaved > 0
        ? (totSaved / overallTotalSaved) * 100
        : 0.0;

    return {
      'count': inGroup.length,
      'totalTarget': totTarget,
      'totalSaved': totSaved,
      'percentSaved': pct,
      'overallGroupPercent': overallGroupPercent,
    };
  }

  void _openGroupStatement(
    BuildContext context,
    EnvelopeGroup group,
    List<Envelope> envs,
    List<Transaction> txs,
  ) {
    final groupEnvelopeIds = envs
        .where((e) => e.groupId == group.id)
        .map((e) => e.id)
        .toList();

    // Reuse the Stats screen; it will subscribe itself.
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => StatsHistoryScreen(repo: repo)));

    // (If you prefer the old sheet behavior, swap back to the modal instead.)
  }

  Future<void> _openGroupEditor(
    BuildContext context,
    EnvelopeGroup? group,
  ) async {
    await editor.showGroupEditor(
      context: context,
      groupRepo: groupRepo,
      envelopeRepo: repo,
      group: group,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '£');
    return StreamBuilder<List<Envelope>>(
      stream: repo.envelopesStream,
      builder: (_, s1) {
        final envs = s1.data ?? [];
        return StreamBuilder<List<EnvelopeGroup>>(
          stream: repo.groupsStream,
          builder: (_, s2) {
            final groups = s2.data ?? [];
            return StreamBuilder<List<Transaction>>(
              stream: repo.transactionsStream,
              builder: (_, s3) {
                final txs = s3.data ?? [];

                return Scaffold(
                  appBar: AppBar(
                    title: const Text(
                      'Envelope Groups',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    elevation: 0,
                  ),
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: groups.map((g) {
                      final st = _statsFor(g, envs);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: Colors.black,
                            child: Text(
                              g.name.isNotEmpty ? g.name[0] : '?',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            g.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${st['count']} envelopes | ${(st['percentSaved'] as double).toStringAsFixed(1)}% to target',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currency.format(st['totalSaved']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                '${(st['overallGroupPercent'] as double).toStringAsFixed(1)}% of total',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          onTap: () =>
                              _openGroupStatement(context, g, envs, txs),
                          onLongPress: () => _openGroupEditor(context, g),
                        ),
                      );
                    }).toList(),
                  ),
                  floatingActionButton: SpeedDial(
                    icon: Icons.add,
                    activeIcon: Icons.close,
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    spacing: 12,
                    spaceBetweenChildren: 8,
                    children: [
                      SpeedDialChild(
                        child: const Icon(
                          Icons.people_alt,
                          color: Colors.black,
                        ),
                        backgroundColor: Colors.grey.shade200,
                        label: 'New Group',
                        labelBackgroundColor: Colors.white,
                        onTap: () => _openGroupEditor(context, null),
                      ),
                      SpeedDialChild(
                        child: const Icon(Icons.edit_note, color: Colors.black),
                        backgroundColor: Colors.grey.shade200,
                        label: 'Edit/Delete Groups',
                        labelBackgroundColor: Colors.white,
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Long-press a group to edit/delete.'),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
