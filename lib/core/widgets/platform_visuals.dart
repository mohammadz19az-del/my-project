import 'package:flutter/material.dart';

import '../../shared/enums/enums.dart';
import '../theme/app_colors.dart';

/// Neutral Material icons and theme-palette colors per platform. Official brand
/// logos are deliberately not bundled.
IconData platformIcon(MessagingPlatform p) => switch (p) {
      MessagingPlatform.telegram => Icons.send_rounded,
      MessagingPlatform.whatsapp => Icons.chat_rounded,
      MessagingPlatform.rubika => Icons.blur_circular_rounded,
      MessagingPlatform.soroush => Icons.forum_rounded,
    };

Color platformColor(MessagingPlatform p) => switch (p) {
      MessagingPlatform.telegram => AppColors.cyan,
      MessagingPlatform.whatsapp => AppColors.emerald,
      MessagingPlatform.rubika => AppColors.violet,
      MessagingPlatform.soroush => AppColors.amber,
    };
