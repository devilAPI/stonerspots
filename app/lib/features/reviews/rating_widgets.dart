import 'package:flutter/material.dart';

String formatRating(double avg) => avg.toStringAsFixed(1);

/// Five stars, filled (and half filled) according to [rating].
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 18});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Colors.amber.shade700;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i - 0.25
                ? Icons.star
                : rating >= i - 0.75
                ? Icons.star_half
                : Icons.star_border,
            size: size,
            color: color,
          ),
      ],
    );
  }
}

/// Compact "star 4.3 (12)"; renders nothing when there are no reviews.
class RatingBadge extends StatelessWidget {
  const RatingBadge({
    super.key,
    required this.avg,
    required this.count,
    this.size = 16,
  });

  final double avg;
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: size, color: Colors.amber.shade700),
        const SizedBox(width: 2),
        Text(
          '${formatRating(avg)} ($count)',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
