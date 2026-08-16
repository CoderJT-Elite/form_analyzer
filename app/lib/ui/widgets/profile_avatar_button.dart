import 'dart:io';

import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../services/storage_service.dart';

/// Small avatar shown in the corner of every main screen's header, so the
/// user's profile — and whatever photo they've set — is always one tap away.
class ProfileAvatarButton extends StatelessWidget {
  final VoidCallback? onTap;

  const ProfileAvatarButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ValueListenableBuilder<String?>(
        valueListenable: profilePictureNotifier,
        builder: (context, path, _) {
          final hasPhoto = path != null && File(path).existsSync();
          return Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.accentCyan, AppColors.accentMagenta],
              ),
            ),
            child: CircleAvatar(
              backgroundColor: AppColors.surface,
              backgroundImage: hasPhoto ? FileImage(File(path)) : null,
              child: hasPhoto
                  ? null
                  : Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset('assets/icons/avatar_placeholder.png'),
                    ),
            ),
          );
        },
      ),
    );
  }
}
