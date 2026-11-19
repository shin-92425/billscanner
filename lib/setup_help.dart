import 'package:flutter/material.dart';

import 'app_config.dart';

/// Shown when the model files are missing or cannot be loaded.
class SetupHelp extends StatelessWidget {
  const SetupHelp({super.key, required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.model_training, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Model not ready', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text(
              'The app is installed correctly, but it cannot find a trained '
              'model yet. The scanner needs two files in the assets/ folder:',
            ),
            const SizedBox(height: 12),
            Text('\u2022 ${AppConfig.modelAsset}'),
            Text('\u2022 ${AppConfig.labelsAsset}'),
            const SizedBox(height: 12),
            const Text(
              'Train the model with training/train_bills.ipynb in Google '
              'Colab, copy the two files it gives you into assets/, then run '
              'the app again (see README.md, step 4).',
            ),
            const SizedBox(height: 20),
            Text('Technical details', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            SelectableText(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
