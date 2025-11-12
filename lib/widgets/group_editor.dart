// lib/widgets/group_editor.dart
import 'package:flutter/material.dart';
import '../services/group_repo.dart';
import '../services/envelope_repo.dart';
import '../models/envelope_group.dart';
import '../models/envelope.dart';

Future<void> showGroupEditor({
  required BuildContext context,
  required GroupRepo groupRepo,
  required EnvelopeRepo envelopeRepo,
  EnvelopeGroup? group, // null => creating a new group
}) async {
  final isEdit = group != null;
  final nameCtrl = TextEditingController(text: group?.name ?? '');
  final formKey = GlobalKey<FormState>();

  // selection state
  final selectedEnvelopeIds = <String>{};
  bool saving = false;
  bool didInitSelection = false; // persist across rebuilds
  final scrollCtrl = ScrollController(); // keeps position stable
  final String? editingGroupId = group?.id;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> save() async {
          if (!formKey.currentState!.validate()) {
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Please enter a valid name.')),
            );
            return;
          }

          setLocal(() => saving = true);
          String? currentGroupId = editingGroupId;

          try {
            if (isEdit) {
              final gid = editingGroupId!; // safe: isEdit => group != null
              await groupRepo.renameGroup(
                groupId: gid,
                name: nameCtrl.text.trim(),
              );
            } else {
              currentGroupId = await groupRepo.createGroup(
                name: nameCtrl.text.trim(),
              );
            }

            await envelopeRepo.updateGroupMembership(
              groupId: currentGroupId!,
              newEnvelopeIds: selectedEnvelopeIds,
              allEnvelopesStream: envelopeRepo.envelopesStream,
            );

            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(
                  isEdit
                      ? 'Group updated successfully!'
                      : 'Group created successfully!',
                ),
              ),
            );
          } catch (e) {
            setLocal(() => saving = false);
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(
              ctx,
            ).showSnackBar(SnackBar(content: Text('Error saving group: $e')));
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: FractionallySizedBox(
            heightFactor: 0.9, // cap overall sheet height
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              isEdit
                                  ? 'Edit Group: ${group?.name ?? ''}'
                                  : 'New Group',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Group name',
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter a name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Assign Envelopes:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Flexible scroll area
                        Expanded(
                          child: Theme(
                            data: Theme.of(ctx).copyWith(
                              checkboxTheme: const CheckboxThemeData(
                                shape: CircleBorder(),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              listTileTheme: const ListTileThemeData(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                            ),
                            child: StreamBuilder<List<Envelope>>(
                              stream: envelopeRepo.envelopesStream,
                              builder: (context, snapshot) {
                                final allEnvelopes =
                                    (snapshot.data ?? []).toList()..sort(
                                      (a, b) => a.name.compareTo(b.name),
                                    );

                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                if (allEnvelopes.isEmpty) {
                                  return const Center(
                                    child: Text(
                                      'No envelopes available to group.',
                                    ),
                                  );
                                }

                                // one-time preselect for edit mode
                                if (isEdit && !didInitSelection) {
                                  for (final e in allEnvelopes) {
                                    if (e.groupId == editingGroupId) {
                                      selectedEnvelopeIds.add(e.id);
                                    }
                                  }
                                  didInitSelection = true;
                                }

                                return Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Scrollbar(
                                    controller: scrollCtrl,
                                    child: ListView.separated(
                                      key: const PageStorageKey(
                                        'groupEditorList',
                                      ),
                                      controller: scrollCtrl,
                                      primary: false,
                                      physics: const ClampingScrollPhysics(),
                                      itemCount: allEnvelopes.length,
                                      separatorBuilder: (_, __) => Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Colors.grey.shade200,
                                      ),
                                      itemBuilder: (context, i) {
                                        final e = allEnvelopes[i];
                                        final isSelected = selectedEnvelopeIds
                                            .contains(e.id);
                                        return CheckboxListTile(
                                          value: isSelected,
                                          onChanged: (v) {
                                            setLocal(() {
                                              if (v == true) {
                                                selectedEnvelopeIds.add(e.id);
                                              } else {
                                                selectedEnvelopeIds.remove(
                                                  e.id,
                                                );
                                              }
                                            });
                                          },
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          activeColor: Colors.black,
                                          title: Text(e.name),
                                          subtitle:
                                              (isEdit &&
                                                  e.groupId == editingGroupId)
                                              ? const Text(
                                                  'Currently in this group',
                                                )
                                              : null,
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                            ),
                            icon: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check, color: Colors.white),
                            label: Text(
                              isEdit ? 'Save Changes' : 'Create Group',
                              style: const TextStyle(color: Colors.white),
                            ),
                            onPressed: saving ? null : save,
                          ),
                        ),

                        if (isEdit)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: OutlinedButton.icon(
                                icon: const Icon(
                                  Icons.delete_forever,
                                  color: Colors.red,
                                ),
                                label: const Text(
                                  'Delete Group',
                                  style: TextStyle(color: Colors.red),
                                ),
                                onPressed: saving
                                    ? null
                                    : () async {
                                        final groupId = editingGroupId;
                                        if (groupId == null) return;

                                        setLocal(() => saving = true);
                                        try {
                                          await envelopeRepo
                                              .updateGroupMembership(
                                                groupId: groupId,
                                                newEnvelopeIds:
                                                    <String>{}, // clear all
                                                allEnvelopesStream: envelopeRepo
                                                    .envelopesStream,
                                              );

                                          await groupRepo.deleteGroup(
                                            groupId: groupId,
                                          );

                                          if (!ctx.mounted) return;
                                          Navigator.of(ctx).pop();
                                          ScaffoldMessenger.of(
                                            ctx,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('Group deleted.'),
                                            ),
                                          );
                                        } catch (e) {
                                          if (!ctx.mounted) return;
                                          setLocal(() => saving = false);
                                          ScaffoldMessenger.of(
                                            ctx,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Error deleting group: $e',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
