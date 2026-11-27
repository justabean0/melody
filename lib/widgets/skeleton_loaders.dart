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

    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceContainerHighest;
    final highlightColor = colorScheme.surfaceContainerLow;
    final midColor = colorScheme.surfaceContainer;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
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
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
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
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        shape: shape,
        borderRadius: shape == BoxShape.circle
            ? null
            : (borderRadius ?? BorderRadius.circular(8)),
      ),
    );
  }
}

/// Layout-matched skeleton loader for the Home feed.
/// Renders filter chips row, Quick Picks track list, and Featured & Trending carousel.
class HomeFeedSkeleton extends StatelessWidget {
  const HomeFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 172 + MediaQuery.paddingOf(context).bottom),
        children: [
          // Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              children: List.generate(
                6,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: SkeletonBox(
                    width: 64 + (i % 3) * 16.0,
                    height: 32,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Section 1 Header: Quick Picks
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(
                      width: 120,
                      height: 22,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    const SizedBox(height: 6),
                    SkeletonBox(
                      width: 180,
                      height: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
                SkeletonBox(
                  width: 80,
                  height: 32,
                  borderRadius: BorderRadius.circular(16),
                ),
              ],
            ),
          ),

          // Quick Picks Song Rows (6 items matching SongTile layout)
          ...List.generate(
            6,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  SkeletonBox(
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: 140 + (i % 3) * 30.0,
                          height: 14,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 6),
                        SkeletonBox(
                          width: 90 + (i % 2) * 20.0,
                          height: 12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SkeletonBox(
                    width: 24,
                    height: 24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section 2 Header: Featured & Trending
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: SkeletonBox(
              width: 160,
              height: 22,
              borderRadius: BorderRadius.circular(6),
            ),
          ),

          // Horizontal Media Cards Carousel
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              children: List.generate(
                4,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(
                        width: 140,
                        height: 140,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      const SizedBox(height: 8),
                      SkeletonBox(
                        width: 110,
                        height: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 4),
                      SkeletonBox(
                        width: 70,
                        height: 12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout-matched skeleton loader for Search results.
/// Renders Top Result hero card, vertical song items, and section shelves.
class SearchResultsSkeleton extends StatelessWidget {
  const SearchResultsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 172 + MediaQuery.paddingOf(context).bottom),
        children: [
          // Top Result Hero Card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  SkeletonBox(
                    width: 72,
                    height: 72,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: 60,
                          height: 18,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 8),
                        SkeletonBox(
                          width: 160,
                          height: 16,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 6),
                        SkeletonBox(
                          width: 100,
                          height: 12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Section Header: Songs
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SkeletonBox(
              width: 80,
              height: 18,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Song Rows (5 items matching SongTile)
          ...List.generate(
            5,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  SkeletonBox(
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: 150 + (i % 3) * 25.0,
                          height: 14,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 6),
                        SkeletonBox(
                          width: 95 + (i % 2) * 20.0,
                          height: 12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SkeletonBox(
                    width: 24,
                    height: 24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ],
              ),
            ),
          ),

          // Section Header: Albums & Playlists
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SkeletonBox(
              width: 120,
              height: 18,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Horizontal Albums Carousel
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              children: List.generate(
                3,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(
                        width: 130,
                        height: 130,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      const SizedBox(height: 8),
                      SkeletonBox(
                        width: 100,
                        height: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 4),
                      SkeletonBox(
                        width: 60,
                        height: 12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout-matched skeleton loader for Album & Playlist detail screens.
/// Renders artwork cover header, title/author text, action pill buttons, and tracklist rows.
class CollectionDetailSkeleton extends StatelessWidget {
  const CollectionDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 172 + MediaQuery.paddingOf(context).bottom),
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

          // Title & Subtitle / Metadata
          Center(
            child: SkeletonBox(
              width: 220,
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

          const SizedBox(height: 18),

          // Action Button Pills (Play, Shuffle, Favorite)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonBox(
                  width: 110,
                  height: 42,
                  borderRadius: BorderRadius.circular(21),
                ),
                const SizedBox(width: 12),
                SkeletonBox(
                  width: 42,
                  height: 42,
                  shape: BoxShape.circle,
                ),
                const SizedBox(width: 12),
                SkeletonBox(
                  width: 42,
                  height: 42,
                  shape: BoxShape.circle,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Tracklist Rows (7 items)
          ...List.generate(
            7,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  SkeletonBox(
                    width: 20,
                    height: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: 140 + (i % 4) * 25.0,
                          height: 14,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 5),
                        SkeletonBox(
                          width: 80 + (i % 3) * 20.0,
                          height: 12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SkeletonBox(
                    width: 32,
                    height: 12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout-matched skeleton loader for Artist profile screens.
/// Renders circular avatar header, artist name & followers, action pills, top songs, and albums carousel.
class ArtistDetailSkeleton extends StatelessWidget {
  const ArtistDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 172 + MediaQuery.paddingOf(context).bottom),
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
              width: 100,
              height: 14,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          const SizedBox(height: 18),

          // Action Button Pills
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonBox(
                  width: 110,
                  height: 42,
                  borderRadius: BorderRadius.circular(21),
                ),
                const SizedBox(width: 12),
                SkeletonBox(
                  width: 42,
                  height: 42,
                  shape: BoxShape.circle,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section Header: Top Songs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: SkeletonBox(
              width: 100,
              height: 20,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Top Song Rows (5 items)
          ...List.generate(
            5,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  SkeletonBox(
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: 140 + (i % 3) * 25.0,
                          height: 14,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 6),
                        SkeletonBox(
                          width: 80 + (i % 2) * 20.0,
                          height: 12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SkeletonBox(
                    width: 24,
                    height: 24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section Header: Albums & Singles
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: SkeletonBox(
              width: 130,
              height: 20,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          // Horizontal Albums Carousel
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              children: List.generate(
                3,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(
                        width: 130,
                        height: 130,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      const SizedBox(height: 8),
                      SkeletonBox(
                        width: 100,
                        height: 14,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 4),
                      SkeletonBox(
                        width: 60,
                        height: 12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
