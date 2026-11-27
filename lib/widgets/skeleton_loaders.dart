import 'package:flutter/material.dart';

/// Single coordinated shimmer animation driven by Theme.of(context).colorScheme.
/// Respects MediaQuery.disableAnimationsOf(context) for reduced motion accessibility.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    } else {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }

    return _ShimmerScope(
      animation: _controller,
      child: widget.child,
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  final Animation<double> animation;

  const _ShimmerScope({
    required this.animation,
    required super.child,
  });

  static Animation<double>? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;
  }

  @override
  bool updateShouldNotify(covariant _ShimmerScope oldWidget) =>
      oldWidget.animation != animation;
}

/// Generic skeleton block with custom dimensions, border radius, or circular shape.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final EdgeInsetsGeometry? margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.margin,
  });

  const SkeletonBox.circle({
    super.key,
    required double size,
    this.margin,
  })  : width = size,
        height = size,
        shape = BoxShape.circle,
        borderRadius = null;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final baseColor = colorScheme.surfaceContainerHigh;
    final midColor = isDark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainer;
    final highlightColor = isDark
        ? Color.lerp(
            colorScheme.surfaceContainerHighest,
            colorScheme.onSurface,
            0.08,
          )!
        : colorScheme.surfaceContainerLow;
    final resolvedBorderRadius =
        shape == BoxShape.circle ? null : (borderRadius ?? BorderRadius.circular(8));

    final animation = MediaQuery.disableAnimationsOf(context)
        ? null
        : _ShimmerScope.maybeOf(context);

    if (animation == null) {
      return Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          color: baseColor,
          shape: shape,
          borderRadius: resolvedBorderRadius,
        ),
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value;
        return Container(
          width: width,
          height: height,
          margin: margin,
          decoration: BoxDecoration(
            shape: shape,
            borderRadius: resolvedBorderRadius,
            gradient: LinearGradient(
              begin: Alignment(-2.0 + 4.0 * v, -0.3),
              end: Alignment(-0.5 + 4.0 * v, 0.3),
              colors: [
                baseColor,
                midColor,
                highlightColor,
                midColor,
                baseColor,
              ],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonSongRow extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final int seedIndex;

  const _SkeletonSongRow({
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
    this.seedIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          SkeletonBox(
            width: 48,
            height: 48,
            borderRadius: BorderRadius.circular(10),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.62 + (seedIndex % 3) * 0.1,
                  child: SkeletonBox(
                    height: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.38 + (seedIndex % 2) * 0.12,
                  child: SkeletonBox(
                    height: 12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const SkeletonBox.circle(size: 20),
        ],
      ),
    );
  }
}

class _SkeletonMediaShelf extends StatelessWidget {
  final double cardSize;
  final bool isCircle;
  final bool showSecondCaptionLine;
  final int itemCount;

  const _SkeletonMediaShelf({
    this.cardSize = 140,
    this.isCircle = false,
    this.showSecondCaptionLine = true,
    this.itemCount = 4,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 16.0, right: 4.0),
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(
          itemCount,
          (i) => Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: SizedBox(
              width: cardSize,
              child: Column(
                crossAxisAlignment:
                    isCircle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                  isCircle
                      ? SkeletonBox.circle(size: cardSize)
                      : SkeletonBox(
                          width: cardSize,
                          height: cardSize,
                          borderRadius: BorderRadius.circular(14),
                        ),
                  const SizedBox(height: 7),
                  SkeletonBox(
                    width: isCircle ? cardSize * 0.78 : cardSize * 0.78,
                    height: 13,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  if (showSecondCaptionLine) ...[
                    const SizedBox(height: 4),
                    SkeletonBox(
                      width: cardSize * 0.52,
                      height: 11,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Layout-matched skeleton loader for the Home feed.
/// Renders mood chips (when [showMoodChips] is true), Quick Picks header + Play all pill,
/// 4-row horizontal column with next-column peek, Featured & Trending 138dp cards, and Albums shelf.
class HomeFeedSkeleton extends StatelessWidget {
  final bool showMoodChips;

  const HomeFeedSkeleton({
    super.key,
    this.showMoodChips = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = 172.0 + MediaQuery.paddingOf(context).bottom;

    return ColoredBox(
      color: colorScheme.surface,
      child: Shimmer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            if (showMoodChips)
              SizedBox(
                height: 48,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: List.generate(
                      7,
                      (i) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Center(
                          child: SkeletonBox(
                            width: 58 + (i % 3) * 16.0,
                            height: 34,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 18),

            // Quick Picks Header + Play all pill
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SkeletonBox(
                      width: 112,
                      height: 22,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    SkeletonBox(
                      width: 84,
                      height: 32,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 6),

            // 4-row Quick Picks horizontal column + narrowed next-column peek (~0.91 width)
            LayoutBuilder(
              builder: (context, constraints) {
                final colWidth =
                    (constraints.maxWidth * 0.91).clamp(280.0, 420.0);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(right: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(
                      2,
                      (colIndex) => SizedBox(
                        width: colWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            4,
                            (rowIndex) => _SkeletonSongRow(
                              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                              seedIndex: colIndex * 4 + rowIndex,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 22),

            // Featured & Trending Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(
                  width: 175,
                  height: 22,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Featured & Trending 138dp square cards with 2-line captions
            const _SkeletonMediaShelf(
              cardSize: 138,
              showSecondCaptionLine: true,
              itemCount: 4,
            ),

            const SizedBox(height: 22),

            // Albums Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(
                  width: 82,
                  height: 22,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Albums 138dp square cards with 2-line captions
            const _SkeletonMediaShelf(
              cardSize: 138,
              showSecondCaptionLine: true,
              itemCount: 4,
            ),
          ],
        ),
      ),
    );
  }
}

/// Layout-matched skeleton loader for Search results.
/// Renders Top Result hero card with trailing circular play button,
/// borderless Songs rows, 80dp circular Artists row, and Albums shelf.
class SearchResultsSkeleton extends StatelessWidget {
  const SearchResultsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = 172.0 + MediaQuery.paddingOf(context).bottom;

    return ColoredBox(
      color: colorScheme.surface,
      child: Shimmer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottomPadding),
          children: [
            // Section Header: Top Result
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(
                  width: 96,
                  height: 20,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),

            // Top Result Hero Card (56dp artwork + title/subtitle + 42dp play button circle)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    SkeletonBox(
                      width: 56,
                      height: 56,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SkeletonBox(
                            width: 150,
                            height: 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 6),
                          SkeletonBox(
                            width: 105,
                            height: 12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: SkeletonBox.circle(size: 42),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Section Header: Songs
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(
                  width: 68,
                  height: 20,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),

            // Borderless Song Rows
            ...List.generate(
              4,
              (i) => _SkeletonSongRow(seedIndex: i),
            ),

            // Section Header: Artists
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(
                  width: 72,
                  height: 20,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),

            // 80dp Circular Artists Row
            const _SkeletonMediaShelf(
              cardSize: 80,
              isCircle: true,
              showSecondCaptionLine: false,
              itemCount: 4,
            ),

            // Section Header: Albums
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(
                  width: 78,
                  height: 20,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),

            // 138dp Albums Carousel
            const _SkeletonMediaShelf(
              cardSize: 138,
              showSecondCaptionLine: true,
              itemCount: 3,
            ),
          ],
        ),
      ),
    );
  }
}

/// Layout-matched skeleton loader for Album & Playlist detail screens.
/// Renders artwork cover header, title/author text, Play/Shuffle action pills, and tracklist rows.
class CollectionDetailSkeleton extends StatelessWidget {
  const CollectionDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const double bottomPadding = 24.0;

    return ColoredBox(
      color: colorScheme.surface,
      child: Shimmer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: bottomPadding),
          children: [
            const SizedBox(height: 16),

            // Centered Artwork Cover
            Center(
              child: SkeletonBox(
                width: 190,
                height: 190,
                borderRadius: BorderRadius.circular(18),
              ),
            ),

            const SizedBox(height: 20),

            // Title, Subtitle & Metadata
            Center(
              child: SkeletonBox(
                width: 210,
                height: 22,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: SkeletonBox(
                width: 140,
                height: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: SkeletonBox(
                width: 100,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            const SizedBox(height: 20),

            // Action Button Pills (Play & Shuffle matching CollectionDetailScreen)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 10,
                children: [
                  SkeletonBox(
                    width: 130,
                    height: 48,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  SkeletonBox(
                    width: 130,
                    height: 48,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Section Header: Tracks
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(
                  width: 72,
                  height: 18,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            // Tracklist Rows (6 items matching SongTile)
            ...List.generate(
              6,
              (i) => _SkeletonSongRow(seedIndex: i),
            ),
          ],
        ),
      ),
    );
  }
}

/// Layout-matched skeleton loader for Artist profile screens.
/// Renders circular avatar header, artist name & audience, action pills, top songs, and albums carousel.
class ArtistDetailSkeleton extends StatelessWidget {
  const ArtistDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const double bottomPadding = 24.0;

    return ColoredBox(
      color: colorScheme.surface,
      child: Shimmer(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: bottomPadding),
          children: [
            const SizedBox(height: 20),

            // Circular Artist Avatar Header
            const Center(
              child: SkeletonBox.circle(size: 130),
            ),

            const SizedBox(height: 16),

            // Artist Name & Subscriber Count
            Center(
              child: SkeletonBox(
                width: 180,
                height: 24,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: SkeletonBox(
                width: 110,
                height: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            const SizedBox(height: 20),

            // Action Button Pills (Play Songs & Shuffle matching ArtistDetailScreen)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 10,
                children: [
                  SkeletonBox(
                    width: 146,
                    height: 48,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  SkeletonBox(
                    width: 130,
                    height: 48,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Section Header: Top Songs
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(
                  width: 96,
                  height: 20,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            // Top Song Rows (5 items)
            ...List.generate(
              5,
              (i) => _SkeletonSongRow(seedIndex: i),
            ),

            const SizedBox(height: 16),

            // Section Header: Albums
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(
                  width: 82,
                  height: 20,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),

            // Horizontal Albums Carousel
            const _SkeletonMediaShelf(
              cardSize: 138,
              showSecondCaptionLine: true,
              itemCount: 3,
            ),
          ],
        ),
      ),
    );
  }
}
