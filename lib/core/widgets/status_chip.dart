import 'package:flutter/material.dart';

import '../../shared/enums/enums.dart';
import '../theme/app_colors.dart';

/// Small pill with a colored dot. Color is never the only signal: the label is
/// always shown.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(110)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Localization key `connection_<db value>`.
String connectionStatusKey(ConnectionStatus s) => 'connection_${s.dbValue}';

Color connectionStatusColor(ConnectionStatus s) => switch (s) {
      ConnectionStatus.connected => AppColors.emerald,
      ConnectionStatus.connecting => AppColors.cyan,
      ConnectionStatus.disconnected => Colors.blueGrey,
      ConnectionStatus.authenticationRequired => AppColors.amber,
      ConnectionStatus.credentialsExpired => AppColors.amber,
      ConnectionStatus.rateLimited => AppColors.amber,
      ConnectionStatus.unsupported => Colors.blueGrey,
      ConnectionStatus.error => AppColors.red,
      ConnectionStatus.mockConnection => AppColors.violet,
    };

/// Localization key `integration_<db value>`.
String integrationStatusKey(IntegrationStatus s) => 'integration_${s.dbValue}';

Color integrationStatusColor(IntegrationStatus s) => switch (s) {
      IntegrationStatus.supported => AppColors.emerald,
      IntegrationStatus.partiallySupported => AppColors.amber,
      IntegrationStatus.unsupported => AppColors.red,
      IntegrationStatus.notVerified => Colors.blueGrey,
      IntegrationStatus.requiresApproval => AppColors.amber,
      IntegrationStatus.mockOnly => AppColors.violet,
    };
