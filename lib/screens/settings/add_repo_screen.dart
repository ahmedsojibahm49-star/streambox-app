import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../data/sample_provider.dart';
import '../../i18n/i18n.dart';
import '../../providers/catalog_providers.dart';
import '../../services/provider_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/widgets.dart';

/// Add a provider repo: via URL (fetch + validate) or pasted JSON
/// (parse + validate). The JSON tab has a "Load example" button that fills
/// the bundled sample repo JSON.
/// Route: `/settings/providers/add` (see app_router.dart).
class AddRepoScreen extends ConsumerStatefulWidget {
  const AddRepoScreen({super.key});

  @override
  ConsumerState<AddRepoScreen> createState() => _AddRepoScreenState();
}

class _AddRepoScreenState extends ConsumerState<AddRepoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _urlController = TextEditingController();
  final _jsonController = TextEditingController();
  final _urlFormKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.danger : null,
      ),
    );
  }

  Future<void> _addFromUrl() async {
    if (!_urlFormKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(providersListProvider.notifier)
          .addFromUrl(_urlController.text.trim());
      if (!mounted) return;
      _showMessage(tr(context, 'providers.providerAdded'));
      context.pop();
    } on RepoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      // Non-repo failures (e.g. a Hive write error) used to be unhandled
      // async errors — show a generic message instead.
      if (mounted) {
        setState(() => _error = tr(context, 'common.errorGeneric'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFromJson() async {
    final rawJson = _jsonController.text.trim();
    if (rawJson.isEmpty) {
      setState(() => _error = tr(context, 'validation.required'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(providersListProvider.notifier)
          .addFromJson(rawJson);
      if (!mounted) return;
      _showMessage(tr(context, 'providers.providerAdded'));
      context.pop();
    } on RepoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr(context, 'common.errorGeneric'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fill the JSON field with the bundled sample repo JSON. Falls back to
  /// the in-code sample data if the asset cannot be loaded.
  Future<void> _loadExample() async {
    final loadedMessage = tr(context, 'providers.exampleLoaded');
    String example;
    try {
      example = await rootBundle.loadString('assets/sample-repo.json');
    } catch (_) {
      example = sampleRepoJsonString;
    }
    if (!mounted) return;
    _jsonController.text = example;
    setState(() => _error = null);
    _showMessage(loadedMessage);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'providers.addRepo')),
        bottom: TabBar(
          controller: _tabController,
          labelColor: palette.text,
          unselectedLabelColor: palette.muted,
          indicatorColor: AppColors.brand,
          tabs: [
            Tab(
              icon: const Icon(Iconsax.link_1, size: 20),
              text: tr(context, 'providers.addViaUrl'),
            ),
            Tab(
              icon: const Icon(Iconsax.document_text, size: 20),
              text: tr(context, 'providers.addViaJson'),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUrlTab(),
          _buildJsonTab(),
        ],
      ),
    );
  }

  Widget _buildUrlTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _urlFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'providers.subtitle'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: context.palette.muted),
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _urlController,
              label: tr(context, 'providers.providerUrl'),
              hint: tr(context, 'providers.providerUrlHint'),
              prefixIcon: Iconsax.global,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addFromUrl(),
              validator: (value) {
                final key = Validators.providerUrl(value);
                return key == null ? null : tr(context, key);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorBox(message: _error!),
            ],
            const SizedBox(height: 20),
            GradientButton(
              label: _busy
                  ? tr(context, 'providers.adding')
                  : tr(context, 'providers.addProvider'),
              icon: Iconsax.add_circle,
              loading: _busy,
              onPressed: _busy ? null : _addFromUrl,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJsonTab() {
    final palette = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, 'providers.subtitle'),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: palette.muted),
                ),
              ),
              const SizedBox(width: 8),
              GhostButton(
                label: tr(context, 'providers.loadExample'),
                onPressed: _loadExample,
                width: 140,
                height: 40,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            tr(context, 'providers.pasteJsonLabel'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _jsonController,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              hintText: tr(context, 'providers.pasteJsonHint'),
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorBox(message: _error!),
          ],
          const SizedBox(height: 20),
          GradientButton(
            label: _busy
                ? tr(context, 'providers.adding')
                : tr(context, 'providers.addProvider'),
            icon: Iconsax.add_circle,
            loading: _busy,
            onPressed: _busy ? null : _addFromJson,
          ),
        ],
      ),
    );
  }
}

/// Red error box showing a specific [RepoException] message.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppColors.radiusS),
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Iconsax.warning_2, size: 20, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.isDark
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFFB91C1C),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
