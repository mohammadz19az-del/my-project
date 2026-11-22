import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/widgets/glow_card.dart';
import '../../../core/widgets/platform_visuals.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../shared/enums/enums.dart';
import '../domain/dashboard_data.dart';

/// Per-platform account usage (x of 10), connected count and integration status.
class PlatformStatusCard extends StatelessWidget {
  const PlatformStatusCard({
    super.key,
    required this.stats,
    required this.integration,
  });

  final PlatformStats stats;
  final IntegrationStatus integration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = stats.platform;
    final color = platformColor(platform);
    const max = AppConstants.maxAccountsPerPlatform;

    return GlowCard(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(36),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(platformIcon(platform), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(platform.label, style: theme.textTheme.titleMedium)),
              Flexible(
                child: Tooltip(
                  message: context.tr('integration_pending_note'),
                  child: StatusChip(
                    label: context.tr(integrationStatusKey(integration)),
                    color: integrationStatusColor(integration),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (stats.total / max).clamp(0.0, 1.0),
              minHeight: 6,
              color: color,
              backgroundColor: color.withAlpha(30),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('platform_accounts_usage', args: {
              'used': formatNumber(context, stats.total),
              'max': formatNumber(context, max),
            }),
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            context.tr('platform_connected_count',
                args: {'n': formatNumber(context, stats.connected)}),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
