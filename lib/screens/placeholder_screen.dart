import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Temporary placeholder for every route. Workstream agents replace each
/// route's builder with the real screen and delete this file when the last
/// placeholder is gone.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius:
                      BorderRadius.circular(AppColors.radiusL),
                  boxShadow: AppColors.glowShadow,
                ),
                alignment: Alignment.center,
                child: Text(
                  title.isNotEmpty ? title[0] : 'S',
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                detail ?? 'This screen is built by its workstream.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
