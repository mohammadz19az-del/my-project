import 'package:flutter/material.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/localization/app_strings.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/account.dart';
import '../domain/account_validator.dart';
import '../domain/platform_specs.dart';

class AccountFormResult {
  const AccountFormResult({
    required this.platform,
    required this.identifier,
    required this.displayName,
    required this.secrets,
  });

  final MessagingPlatform platform;
  final String identifier;
  final String displayName;
  final Map<String, String> secrets;
}

/// Add/edit dialog. Saving happens through [onSubmit] while the dialog stays open,
/// so a failure (limit reached, duplicate, secure storage error) never loses input.
class AccountFormDialog extends StatefulWidget {
  const AccountFormDialog({
    super.key,
    required this.onSubmit,
    this.existing,
    this.initialPlatform,
    this.hasStoredCredentials = false,
  });

  final Future<void> Function(AccountFormResult result) onSubmit;
  final Account? existing;
  final MessagingPlatform? initialPlatform;
  final bool hasStoredCredentials;

  @override
  State<AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends State<AccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _displayName = TextEditingController();
  Map<String, TextEditingController> _secrets = {};
  final Set<String> _revealed = {};
  late MessagingPlatform _platform;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _platform = e?.platform ?? widget.initialPlatform ?? MessagingPlatform.telegram;
    _identifier.text = e?.accountIdentifier ?? '';
    _displayName.text = e?.displayName ?? '';
    _rebuildSecretControllers();
  }

  void _rebuildSecretControllers() {
    _disposeSecrets();
    _secrets = {
      for (final f in PlatformSpecs.of(_platform).secrets) f.key: TextEditingController(),
    };
    _revealed.clear();
  }

  void _disposeSecrets() {
    for (final c in _secrets.values) {
      c.clear();
      c.dispose();
    }
  }

  @override
  void dispose() {
    _identifier.dispose();
    _displayName.dispose();
    _disposeSecrets();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = AccountFormResult(
      platform: _platform,
      identifier: _identifier.text,
      displayName: _displayName.text,
      secrets: {for (final e in _secrets.entries) e.key: e.value.text},
    );
    try {
      await widget.onSubmit(result);
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
    final spec = PlatformSpecs.of(_platform);

    return AlertDialog(
      title: Text(context.tr(_editing ? 'form_title_edit' : 'form_title_add')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_editing) ...[
                  DropdownButtonFormField<MessagingPlatform>(
                    value: _platform,
                    decoration: InputDecoration(labelText: context.tr('field_platform')),
                    items: [
                      for (final p in MessagingPlatform.values)
                        DropdownMenuItem(value: p, child: Text(p.label)),
                    ],
                    onChanged: _saving
                        ? null
                        : (p) => setState(() {
                              _platform = p ?? _platform;
                              _rebuildSecretControllers();
                            }),
                  ),
                  const SizedBox(height: 12),
                ] else
                  Text(_platform.label, style: theme.textTheme.titleSmall),
                Text(context.tr(spec.noteKey), style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _identifier,
                  enabled: !_saving,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: context.tr(spec.identifierLabelKey),
                    hintText: context.tr(spec.identifierHintKey),
                  ),
                  validator: (v) {
                    final key = AccountValidator.validateIdentifier(_platform, v ?? '');
                    return key == null ? null : context.tr(key);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayName,
                  enabled: !_saving,
                  decoration: InputDecoration(labelText: context.tr('field_display_name')),
                ),
                for (final f in spec.secrets) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _secrets[f.key],
                    enabled: !_saving,
                    obscureText: !_revealed.contains(f.key),
                    enableSuggestions: false,
                    autocorrect: false,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: context.tr(f.labelKey),
                      hintText: context.tr(f.hintKey),
                      helperText: _editing ? context.tr('secret_keep_hint') : null,
                      suffixIcon: IconButton(
                        icon: Icon(_revealed.contains(f.key)
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setState(() {
                          _revealed.contains(f.key) ? _revealed.remove(f.key) : _revealed.add(f.key);
                        }),
                      ),
                    ),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      if (text.isEmpty) return _editing ? null : context.tr('validation_required');
                      final key = AccountValidator.validateSecret(_platform, f.key, text);
                      return key == null ? null : context.tr(key);
                    },
                  ),
                ],
                const SizedBox(height: 12),
                if (spec.requiresCredentials) ...[
                  if (_editing)
                    Text(
                      context.tr(widget.hasStoredCredentials ? 'credential_stored' : 'credential_not_stored'),
                      style: theme.textTheme.bodySmall,
                    ),
                  Text(context.tr('form_secret_note'), style: theme.textTheme.bodySmall),
                ] else
                  Text(context.tr('credential_not_required'), style: theme.textTheme.bodySmall),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
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
