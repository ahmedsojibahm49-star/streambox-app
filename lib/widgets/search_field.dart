import 'package:material_ui/material_ui.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';

/// Rounded search field with a search icon and a clear button.
/// Debouncing lives in the Search screen, not here.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.hintKey = 'search.hint',
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final String hintKey;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: tr(context, widget.hintKey),
        prefixIcon: Icon(
          Iconsax.search_normal_copy,
          size: 20,
          color: palette.muted,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Iconsax.close_circle_copy,
                  size: 20,
                  color: palette.muted,
                ),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged?.call('');
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide:
              const BorderSide(color: AppColors.brand, width: 1.5),
        ),
      ),
    );
  }
}
