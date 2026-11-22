import 'package:flutter/material.dart';

import '../errors/error_messages.dart';
import '../localization/app_strings.dart';

class FormFieldSpec {
  const FormFieldSpec(
    this.key, {
    required this.label,
    this.hint,
    this.initial = '',
    this.maxLines = 1,
    this.ltr = false,
    this.required = false,
    this.validator,
  });

  final String key;
  final String label;
  final String? hint;
  final String initial;
  final int maxLines;
  final bool ltr;
  final bool required;

  /// Returns an already-localized error message, or null.
  final String? Function(String value)? validator;
}

class FormChoiceSpec {
  const FormChoiceSpec(this.key, {required this.label, required this.options, required this.initial});

  final String key;
  final String label;

  /// value -> display label
  final Map<String, String> options;
  final String initial;
}

/// Small reusable add/edit dialog. [onSubmit] runs while the dialog stays open, so
/// a failure shows an inline message and the user's input is never lost.
class SimpleFormDialog extends StatefulWidget {
  const SimpleFormDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.onSubmit,
    this.choices = const [],
    this.note,
  });

  final String title;
  final List<FormFieldSpec> fields;
  final List<FormChoiceSpec> choices;
  final String? note;
  final Future<void> Function(Map<String, String> values) onSubmit;

  @override
  State<SimpleFormDialog> createState() => _SimpleFormDialogState();
}

class _SimpleFormDialogState extends State<SimpleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.initial),
  };
  late final Map<String, String> _choices = {for (final c in widget.choices) c.key: c.initial};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit({
        for (final e in _controllers.entries) e.key: e.value.text,
        ..._choices,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = localizedError(context.strings, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.note != null) ...[
                  Text(widget.note!, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                ],
                for (final c in widget.choices) ...[
                  DropdownButtonFormField<String>(
                    value: _choices[c.key],
                    decoration: InputDecoration(labelText: c.label),
                    items: [
                      for (final o in c.options.entries)
                        DropdownMenuItem(value: o.key, child: Text(o.value)),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _choices[c.key] = v ?? c.initial),
                  ),
                  const SizedBox(height: 12),
                ],
                for (final f in widget.fields) ...[
                  TextFormField(
                    controller: _controllers[f.key],
                    enabled: !_saving,
                    maxLines: f.maxLines,
                    minLines: f.maxLines > 1 ? 3 : 1,
                    textDirection: f.ltr ? TextDirection.ltr : null,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: f.label, hintText: f.hint),
                    validator: (v) {
                      final text = v ?? '';
                      if (f.required && text.trim().isEmpty) return context.tr('validation_required');
                      return f.validator?.call(text);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(context.tr('action_cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('form_save')),
        ),
      ],
    );
  }
}
