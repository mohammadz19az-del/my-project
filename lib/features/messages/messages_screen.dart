import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/error_messages.dart';
import '../../core/localization/app_strings.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utilities/formatters.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/glow_card.dart';
import '../../core/widgets/responsive_wrap.dart';
import '../../core/widgets/state_views.dart';
import '../../core/widgets/status_chip.dart';
import '../../shared/enums/enums.dart';
import '../../shared/models/account.dart';
import '../../shared/models/message_template.dart';
import '../accounts/presentation/account_selector.dart';

final templatesProvider = FutureProvider.autoDispose.family<List<MessageTemplate>, int>(
  (ref, accountId) => ref.watch(messageTemplateRepositoryProvider).listForAccount(accountId),
);

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) => AccountScoped(
        builder: (context, ref, account, selector) => _TemplatesView(account: account, selector: selector),
      );
}

Future<void> _run(BuildContext context, WidgetRef ref, int accountId, Future<void> Function() action,
    {String? successKey}) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  try {
    await action();
    if (successKey != null) messenger.showSnackBar(SnackBar(content: Text(strings.t(successKey))));
  } catch (e, s) {
    AppLogger.error('Template action failed', error: e.runtimeType, stackTrace: s);
    messenger.showSnackBar(SnackBar(content: Text(localizedError(strings, e))));
  } finally {
    ref.invalidate(templatesProvider(accountId));
  }
}

class _TemplatesView extends ConsumerWidget {
  const _TemplatesView({required this.account, required this.selector});

  final Account account;
  final Widget selector;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(templatesProvider(account.id));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    const max = AppConstants.maxTemplatesPerAccount;

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorState(
        message: localizedError(context.strings, e),
        onRetry: () => ref.invalidate(templatesProvider(account.id)),
      ),
      data: (templates) {
        final full = templates.length >= max;
        return ListView(
          padding: EdgeInsets.all(wide ? 28 : 16),
          children: [
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: selector),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(
                  label: context.tr('templates_count', args: {
                    'n': formatNumber(context, templates.length),
                    'max': formatNumber(context, max),
                  }),
                  color: full ? Colors.amber : Colors.cyan,
                ),
                Tooltip(
                  message: full ? context.tr('templates_limit_reached', args: {'max': formatNumber(context, max)}) : '',
                  child: FilledButton.icon(
                    onPressed: full ? null : () => _edit(context, ref, account),
                    icon: const Icon(Icons.add),
                    label: Text(context.tr('template_add')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (templates.isEmpty)
              EmptyState(
                icon: Icons.chat_bubble_outline,
                title: context.tr('templates_empty_title'),
                message: context.tr('templates_empty_body'),
              )
            else
              ResponsiveWrap(
                minItemWidth: 340,
                children: [for (final t in templates) _TemplateCard(account: account, template: t)],
              ),
          ],
        );
      },
    );
  }
}

class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({required this.account, required this.template});

  final Account account;
  final MessageTemplate template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(messageTemplateRepositoryProvider);
    return GlowCard(
      onTap: () => _edit(context, ref, account, existing: template),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(template.title, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
              Tooltip(
                message: context.tr(template.enabled ? 'template_enabled' : 'template_disabled'),
                child: Switch(
                  value: template.enabled,
                  onChanged: (v) => _run(context, ref, account.id,
                      () => repo.setEnabled(template.id, enabled: v)),
                ),
              ),
            ],
          ),
          Wrap(spacing: 8, children: [
            StatusChip(label: context.tr('lang_${template.language.dbValue}'), color: Colors.blueGrey),
            if ((template.waTemplateName ?? '').isNotEmpty)
              StatusChip(label: context.tr('template_wa_badge'), color: Colors.green),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              template.body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textDirection: textDirectionFor(template.body),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => _preview(context, template),
                child: Text(context.tr('template_preview')),
              ),
              TextButton(
                onPressed: () => _edit(context, ref, account, existing: template),
                child: Text(context.tr('account_edit')),
              ),
              TextButton(
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: context.tr('template_delete_title'),
                    message: context.tr('template_delete_body'),
                    confirmLabel: context.tr('account_delete'),
                    destructive: true,
                  );
                  if (ok && context.mounted) {
                    await _run(context, ref, account.id, () => repo.delete(template.id),
                        successKey: 'template_deleted');
                  }
                },
                child: Text(context.tr('account_delete')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void _preview(BuildContext context, MessageTemplate t) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.title),
      content: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.primary.withAlpha(30),
            borderRadius: BorderRadius.circular(14),
          ),
          // Exact text, rendered in its natural direction.
          child: Text(t.body, textDirection: textDirectionFor(t.body)),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.tr('action_close')))],
    ),
  );
}

Future<void> _edit(BuildContext context, WidgetRef ref, Account account, {MessageTemplate? existing}) async {
  final messenger = ScaffoldMessenger.of(context);
  final strings = context.strings;
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TemplateEditor(
      account: account,
      existing: existing,
      onSubmit: (title, body, language, waName, waLang) async {
        final repo = ref.read(messageTemplateRepositoryProvider);
        if (existing == null) {
          await repo.create(MessageTemplateInput(
            accountId: account.id,
            title: title,
            body: body,
            language: language,
            waTemplateName: waName,
            waTemplateLanguage: waLang,
          ));
        } else {
          await repo.update(existing.id,
              title: title,
              body: body,
              language: language,
              waTemplateName: waName,
              waTemplateLanguage: waLang);
        }
      },
    ),
  );
  ref.invalidate(templatesProvider(account.id));
  if (saved == true) messenger.showSnackBar(SnackBar(content: Text(strings.t('template_saved'))));
}

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({required this.account, required this.onSubmit, this.existing});

  final Account account;
  final MessageTemplate? existing;
  final Future<void> Function(String title, String body, MessageLanguage language, String? waName, String? waLang)
      onSubmit;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _body = TextEditingController(text: widget.existing?.body ?? '');
  late final _waName = TextEditingController(text: widget.existing?.waTemplateName ?? '');
  late final _waLang = TextEditingController(text: widget.existing?.waTemplateLanguage ?? '');
  late MessageLanguage _language = widget.existing?.language ?? MessageLanguage.mixed;
  bool _preview = false;
  bool _saving = false;
  String? _error;

  bool get _isWhatsApp => widget.account.platform == MessagingPlatform.whatsapp;
  static const int _maxLength = 4096;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _waName.dispose();
    _waLang.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        _title.text,
        _body.text, // exact content, not trimmed
        _language,
        _isWhatsApp ? _waName.text : null,
        _isWhatsApp ? _waLang.text : null,
      );
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
      title: Text(context.tr(widget.existing == null ? 'template_add' : 'template_edit')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _title,
                  enabled: !_saving,
                  decoration: InputDecoration(labelText: context.tr('template_title')),
                  validator: (v) => (v ?? '').trim().isEmpty ? context.tr('validation_required') : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MessageLanguage>(
                  value: _language,
                  decoration: InputDecoration(labelText: context.tr('template_language')),
                  items: [
                    for (final l in MessageLanguage.values)
                      DropdownMenuItem(value: l, child: Text(context.tr('lang_${l.dbValue}'))),
                  ],
                  onChanged: _saving ? null : (l) => setState(() => _language = l ?? _language),
                ),
                const SizedBox(height: 12),
                if (_preview)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(_body.text, textDirection: textDirectionFor(_body.text)),
                  )
                else
                  TextFormField(
                    controller: _body,
                    enabled: !_saving,
                    minLines: 5,
                    maxLines: 12,
                    maxLength: _maxLength,
                    textDirection: textDirectionFor(_body.text),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: context.tr('template_body')),
                    validator: (v) => (v ?? '').trim().isEmpty ? context.tr('validation_required') : null,
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _preview = !_preview),
                    icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
                    label: Text(context.tr(_preview ? 'template_edit_mode' : 'template_preview')),
                  ),
                ),
                if (_isWhatsApp) ...[
                  Text(context.tr('template_wa_note'), style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _waName,
                    enabled: !_saving,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: context.tr('template_wa_name')),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _waLang,
                    enabled: !_saving,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: context.tr('template_wa_language'),
                      hintText: 'en_US, fa',
                    ),
                  ),
                ],
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
