import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../utils/thumbnail_utils.dart';

class MediaCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback onTap;
  final double size;
  final bool isCircle;
  final bool showSubtitle;
  final IconData? fallbackIcon;

  const MediaCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onTap,
    this.size = 138,
    this.isCircle = false,
    this.showSubtitle = true,
    this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radius = isCircle ? size / 2 : 14.0;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment:
                isCircle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: CachedNetworkImage(
                  imageUrl: ThumbnailUtils.upgradeUrl(imageUrl, size: 544),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: size,
                    height: size,
                    color: colorScheme.surfaceContainerHigh,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: size,
                    height: size,
                    color: colorScheme.surfaceContainerHigh,
                    child: Icon(
                      fallbackIcon ??
                          (isCircle ? Icons.person_rounded : Icons.album_rounded),
                      size: size * 0.4,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isCircle ? TextAlign.center : TextAlign.start,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: isCircle ? 12.5 : 13.5,
                  fontWeight: isCircle ? FontWeight.w500 : FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              if (showSubtitle && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: isCircle ? TextAlign.center : TextAlign.start,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
