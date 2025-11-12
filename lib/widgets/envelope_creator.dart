import 'package:flutter/material.dart';
import '../services/envelope_repo.dart';

Future<void> showEnvelopeCreator(
  BuildContext context, {
  required EnvelopeRepo repo,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EnvelopeCreatorSheet(repo: repo),
  );
}

class _EnvelopeCreatorSheet extends StatefulWidget {
  const _EnvelopeCreatorSheet({required this.repo});
  final EnvelopeRepo repo;

  @override
  State<_EnvelopeCreatorSheet> createState() => _EnvelopeCreatorSheetState();
}

class _EnvelopeCreatorSheetState extends State<_EnvelopeCreatorSheet> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameCtrl = TextEditingController();
  final _amtCtrl = TextEditingController(text: '0.00');
  final _targetCtrl = TextEditingController();

  // Focus nodes to control keyboard navigation
  final _nameFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _targetFocus = FocusNode();

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    // Auto-focus the name field when the sheet opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });

    // Select all text in amount when it gains focus
    _amountFocus.addListener(() {
      if (_amountFocus.hasFocus) {
        _amtCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _amtCtrl.text.length,
        );
      }
    });

    // Select all in target when it gains focus (optional nicety)
    _targetFocus.addListener(() {
      if (_targetFocus.hasFocus) {
        _targetCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _targetCtrl.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amtCtrl.dispose();
    _targetCtrl.dispose();
    _nameFocus.dispose();
    _amountFocus.dispose();
    _targetFocus.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_saving) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (widget.repo.db == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Database not initialized.')),
      );
      return;
    }

    final name = _nameCtrl.text.trim();

    // starting amount (blank -> 0.00)
    double start = 0.0;
    final rawStart = _amtCtrl.text.trim();
    if (rawStart.isNotEmpty) {
      final parsed = double.tryParse(rawStart);
      if (parsed == null || parsed < 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid starting amount')),
        );
        return;
      }
      start = parsed;
    }

    // target (optional)
    double? target;
    final rawTarget = _targetCtrl.text.trim();
    if (rawTarget.isNotEmpty) {
      final parsed = double.tryParse(rawTarget);
      if (parsed == null || parsed < 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid target')));
        return;
      }
      target = parsed;
    }

    setState(() => _saving = true);
    try {
      await widget.repo.createEnvelope(
        name: name,
        startingAmount: start,
        targetAmount: target,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // close the sheet
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Envelope created successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creating envelope: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.9;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          // Replace deprecated withOpacity with withAlpha(26) ~ 10% opacity
          BoxShadow(color: Colors.black.withAlpha(26), blurRadius: 10),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: media.viewInsets.bottom + 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        'New Envelope',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Name
                  TextFormField(
                    controller: _nameCtrl,
                    focusNode: _nameFocus,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Please enter a name'
                        : null,
                    onEditingComplete: () => _amountFocus.requestFocus(),
                  ),
                  const SizedBox(height: 12),

                  // Starting amount
                  TextFormField(
                    controller: _amtCtrl,
                    focusNode: _amountFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Starting amount (£)',
                      hintText: 'e.g. 0.00',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return null; // allowed → treated as 0.00
                      final d = double.tryParse(s);
                      if (d == null || d < 0) return 'Enter a valid amount';
                      return null;
                    },
                    onEditingComplete: () => _targetFocus.requestFocus(),
                    onTap: () {
                      // Select all when the user taps into the field
                      _amtCtrl.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _amtCtrl.text.length,
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Target
                  TextFormField(
                    controller: _targetCtrl,
                    focusNode: _targetFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Target (optional) (£)',
                      hintText: 'e.g. 1000.00',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    onEditingComplete: _handleSave,
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.mail_outline), // envelope-ish
                      label: const Text('Create Envelope'),
                      onPressed: _saving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
