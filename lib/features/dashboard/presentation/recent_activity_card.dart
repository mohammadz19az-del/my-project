import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/widgets/glow_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../shared/enums/enums.dart';
import '../../../shared/models/activity_event.dart';

class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard({super.key, required this.events});

  final List<ActivityEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return GlowCard(
        child: EmptyState(
          compact: true,
          icon: Icons.history,
          title: context.tr('empty_activity_title'),
          message: context.tr('empty_activity_body'),
        ),
      );
    }
    return GlowCard(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _EventRow(event: events[i]),
          ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final ActivityEvent event;

  (IconData, Color) get _visual => switch (event.severity) {
        EventSeverity.info => (Icons.info_outline, AppColors.blue),
        EventSeverity.warning => (Icons.warning_amber_rounded, AppColors.amber),
        EventSeverity.error => (Icons.error_outline, AppColors.red),
        EventSeverity.security => (Icons.shield_outlined, AppColors.violet),
      };

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final key = 'event_${event.eventType}';
    // Known event types are localized; unknown ones fall back to the stored text.
    final title = strings.has(key) ? strings.t(key) : event.description;
    final (icon, color) = _visual;

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(context.tr('severity_${event.severity.dbValue}')),
      trailing: Text(
        formatRelative(context, event.createdAt),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
