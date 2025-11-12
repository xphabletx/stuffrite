// lib/screens/workspace_gate.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WorkspaceGate extends StatefulWidget {
  const WorkspaceGate({
    super.key,
    required this.onJoined,
    this.workspaceId, // if provided, show Manage section (rename)
  });

  final ValueChanged<String> onJoined;
  final String? workspaceId;

  @override
  State<WorkspaceGate> createState() => _WorkspaceGateState();
}

class _WorkspaceGateState extends State<WorkspaceGate> {
  final _db = FirebaseFirestore.instance;
  final _joinCtrl = TextEditingController();

  bool _creating = false;
  bool _joining = false;

  // Manage mode fields
  final _displayNameCtrl = TextEditingController();
  String? _joinCodeForManage;
  bool _savingName = false;
  bool _loadedManage = false;

  @override
  void initState() {
    super.initState();
    if (widget.workspaceId != null) {
      _loadManageData(widget.workspaceId!);
    }
  }

  Future<void> _loadManageData(String wsId) async {
    try {
      final snap = await _db.collection('workspaces').doc(wsId).get();
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      _joinCodeForManage = (data['joinCode'] as String?)?.trim();
      _displayNameCtrl.text =
          ((data['displayName'] ?? data['name']) as String? ?? '').trim();
    } catch (_) {
      // swallow; keep UI usable
    } finally {
      if (mounted) setState(() => _loadedManage = true);
    }
  }

  String _randomCode(int n) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final ref = _db.collection('workspaces').doc();
      final code = _randomCode(6);

      // Canonical: joinCode (immutable). Optional friendly: displayName.
      await ref.set({
        'joinCode': code,
        'displayName': '', // empty by default; purely cosmetic
        'name': code, // keep legacy 'name' matching joinCode for now
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Workspace created. Share this code: $code'),
          duration: const Duration(seconds: 5),
        ),
      );

      widget.onJoined(ref.id);
      if (mounted) Navigator.of(context).maybePop(); // close the gate
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creating workspace: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _join() async {
    final code = _joinCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _joining = true);

    try {
      final snap = await _db
          .collection('workspaces')
          .where('joinCode', isEqualTo: code)
          .limit(1)
          .get();

      if (!mounted) return;
      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No workspace found for that code')),
        );
        return;
      }

      final doc = snap.docs.first;
      widget.onJoined(doc.id);
      Navigator.of(context).maybePop(); // close the gate
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error joining workspace: $e')));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _saveDisplayName() async {
    final wsId = widget.workspaceId;
    if (wsId == null) return;

    final friendly = _displayNameCtrl.text.trim();
    setState(() => _savingName = true);
    try {
      await _db.collection('workspaces').doc(wsId).update({
        'displayName': friendly, // cosmetic only
        // keep 'joinCode' immutable; 'name' remains canonical code for now
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Workspace name updated.')));
      Navigator.of(context).maybePop(); // return to Home; label will refresh
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save name: $e')));
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loadingIndicator = const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
    );

    final inManageMode = widget.workspaceId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          inManageMode ? 'Workspace Settings' : 'Start or Join Workspace',
        ),
        elevation: 0,
        automaticallyImplyLeading: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!inManageMode) ...[
                // --- Create Workspace ---
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _creating || _joining ? null : _create,
                    icon: _creating
                        ? loadingIndicator
                        : const Icon(Icons.add_business),
                    label: Text(
                      _creating ? 'Creating...' : 'Create New Shared Workspace',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30.0),
                  child: Divider(color: Colors.black26),
                ),

                // --- Join Workspace ---
                const Text(
                  'Or join an existing one:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _joinCtrl,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  enabled: !_creating && !_joining,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Enter 6-digit Join Code',
                    hintText: 'e.g. ABC123',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _creating || _joining ? null : _join,
                    icon: _joining ? loadingIndicator : const Icon(Icons.login),
                    label: Text(
                      _joining ? 'Joining...' : 'Join Workspace',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ] else ...[
                // ----------------- Manage current workspace -----------------
                if (!_loadedManage)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Join Code (immutable)',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Chip(label: Text(_joinCodeForManage ?? '—')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Display name (optional)',
                      hintText: 'e.g. Lovell Family',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Shown as “CODE (Display name)”. Joining always uses CODE.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _savingName ? null : _saveDisplayName,
                      icon: _savingName
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: Text(_savingName ? 'Saving...' : 'Save'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
