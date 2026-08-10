import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/models/transaction_draft.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/tables.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/label_picker.dart';

/// Add / edit a transaction (§2.2, §2.3). Passing [transaction] switches the
/// screen into edit mode, offering Delete; omitting it starts a blank entry
/// defaulted to now, per §1's fast-path goal.
///
/// [embedded] is true when this is hosted as the Add tab inside the root
/// shell: no own `Scaffold`/`AppBar` (the shell provides those), and a
/// successful save clears the form in place instead of popping a route.
class EntryScreen extends ConsumerStatefulWidget {
  const EntryScreen({super.key, this.transaction, this.embedded = false});

  final Transaction? transaction;
  final bool embedded;

  @override
  ConsumerState<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends ConsumerState<EntryScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _extraNotesController = TextEditingController();
  late DateTime _occurredAt;
  String? _categoryId;
  String? _paymentMethodId;
  bool _saving = false;

  bool get _isEditing => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    _loadFrom(widget.transaction);
  }

  /// Populates the form from [t], or resets to a blank entry defaulted to
  /// now when [t] is null — used both for initial state and, in embedded
  /// (Add tab) mode, to clear the form after a successful save.
  void _loadFrom(Transaction? t) {
    _amountController.text = t == null ? '' : Money.toDecimalString(t.amountCents);
    _noteController.text = t?.note ?? '';
    _extraNotesController.text = t?.extraNotes ?? '';
    _occurredAt = t == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(t.occurredAt, isUtc: true).toLocal();
    _categoryId = t?.categoryId;
    _paymentMethodId = t?.paymentMethodId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _extraNotesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (!mounted) return;

    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _occurredAt.hour,
        time?.minute ?? _occurredAt.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_paymentMethodId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choose a payment method.')));
      return;
    }
    if (_categoryId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choose a category.')));
      return;
    }

    final int? cents = Money.tryParse(_amountController.text);
    if (cents == null) return; // validator already caught this

    setState(() => _saving = true);
    final TransactionRepository repo = ref.read(transactionRepositoryProvider);
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await repo.upsert(
        TransactionDraft(
          id: widget.transaction?.id,
          amountCents: cents,
          occurredAt: _occurredAt.toUtc().millisecondsSinceEpoch,
          categoryId: _categoryId!,
          paymentMethodId: _paymentMethodId!,
          note: _noteController.text.trim(),
          extraNotes: _extraNotesController.text.trim().isEmpty
              ? null
              : _extraNotesController.text.trim(),
        ),
      );
      if (widget.embedded) {
        // Stays on the Add tab (§1 fast path) — clear the form and confirm
        // via snackbar rather than popping a route that doesn't exist here.
        _formKey.currentState?.reset();
        setState(() => _loadFrom(null));
        messenger.showSnackBar(const SnackBar(content: Text('Transaction added.')));
      } else {
        navigator.pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmDialog(
      context,
      title: 'Delete transaction',
      message: 'Delete this transaction?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final TransactionRepository repo = ref.read(transactionRepositoryProvider);
    final NavigatorState navigator = Navigator.of(context);
    await repo.delete(widget.transaction!.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final DateFormat dateFormat = DateFormat.yMMMd().add_jm();

    // Field order: Amount, Payment method, Note, Category, Date, Additional
    // notes — amount and how-you-paid first since those are usually the two
    // things front-of-mind right after a purchase.
    final Widget form = Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _amountController,
            autofocus: !_isEditing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
            ),
            validator: (String? value) {
              if (Money.tryParse(value ?? '') == null) {
                return 'Enter an amount greater than 0.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          LabelPicker(
            kind: LabelKind.paymentMethod,
            selectedId: _paymentMethodId,
            onChanged: (String? id) => setState(() => _paymentMethodId = id),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _noteController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note',
              border: OutlineInputBorder(),
            ),
            validator: (String? value) =>
                (value == null || value.trim().isEmpty) ? 'Enter a note.' : null,
          ),
          const SizedBox(height: 16),
          LabelPicker(
            kind: LabelKind.category,
            selectedId: _categoryId,
            onChanged: (String? id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
            child: InkWell(
              onTap: _pickDate,
              child: Row(
                children: [
                  Expanded(child: Text(dateFormat.format(_occurredAt))),
                  const Icon(Icons.edit_calendar_outlined),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _extraNotesController,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Additional notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_isEditing ? 'Save Changes' : 'Add Transaction'),
          ),
        ],
      ),
    );

    if (widget.embedded) return form;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: form,
    );
  }
}
