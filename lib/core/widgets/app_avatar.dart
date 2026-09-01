import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_typography.dart';

Future<void> showAvatarPhotoViewer(
  BuildContext context, {
  required ImageProvider image,
  String? personName,
}) {
  final label = _viewerLabel(personName);
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _AppAvatarViewer(image: image, semanticsLabel: label),
    ),
  );
}

class AppAvatar extends StatefulWidget {
  const AppAvatar({
    super.key,
    required this.name,
    required this.size,
    this.avatarUrl,
    this.imageProvider,
    this.backgroundColor,
    this.foregroundColor,
    this.textStyle,
    this.borderRadius,
    this.fallbackKey,
    this.maxInitials = 2,
  });

  final String name;
  final double size;
  final String? avatarUrl;
  final ImageProvider? imageProvider;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final TextStyle? textStyle;
  final BorderRadius? borderRadius;
  final Key? fallbackKey;
  final int maxInitials;

  @override
  State<AppAvatar> createState() => _AppAvatarState();
}

class _AppAvatarState extends State<AppAvatar> {
  bool _imageFailed = false;

  ImageProvider? get _image {
    if (_imageFailed) return null;
    if (widget.imageProvider != null) return widget.imageProvider;
    final url = widget.avatarUrl?.trim();
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('data:image/') && url.contains(';base64,')) {
      try {
        return MemoryImage(base64Decode(url.split(';base64,').last));
      } on FormatException {
        return null;
      }
    }
    return NetworkImage(url);
  }

  String get _initials {
    final parts = widget.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(widget.maxInitials);
    final value = parts.map((part) => part[0].toUpperCase()).join();
    return value.isEmpty ? 'A' : value;
  }

  @override
  void didUpdateWidget(covariant AppAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl ||
        oldWidget.imageProvider != widget.imageProvider) {
      _imageFailed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final radius =
        widget.borderRadius ?? BorderRadius.circular(widget.size / 2);
    final avatar = ClipRRect(
      borderRadius: radius,
      child: SizedBox.square(
        dimension: widget.size,
        child: ColoredBox(
          color: widget.backgroundColor ?? AppColors.surfaceAlt(context),
          child: image == null
              ? Center(
                  child: Text(
                    _initials,
                    key:
                        widget.fallbackKey ??
                        const ValueKey('app-avatar-fallback'),
                    style:
                        widget.textStyle ??
                        AppTypography.buttonLabel(context).copyWith(
                          color: widget.foregroundColor ?? AppColors.primary,
                        ),
                  ),
                )
              : Image(
                  image: image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_imageFailed) {
                        setState(() => _imageFailed = true);
                      }
                    });
                    return Center(
                      child: Text(
                        _initials,
                        key:
                            widget.fallbackKey ??
                            const ValueKey('app-avatar-fallback'),
                        style:
                            widget.textStyle ??
                            AppTypography.buttonLabel(context).copyWith(
                              color:
                                  widget.foregroundColor ?? AppColors.primary,
                            ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );

    if (image == null) return avatar;
    return Semantics(
      button: true,
      label: _viewerLabel(widget.name),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('app-avatar-viewer-trigger'),
          customBorder: const CircleBorder(),
          onTap: () => showAvatarPhotoViewer(
            context,
            image: image,
            personName: widget.name,
          ),
          child: avatar,
        ),
      ),
    );
  }
}

class _AppAvatarViewer extends StatelessWidget {
  const _AppAvatarViewer({required this.image, required this.semanticsLabel});

  final ImageProvider image;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('app-avatar-viewer'),
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            image: true,
            label: semanticsLabel,
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image(
                  image: image,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Padding(
                    padding: const EdgeInsets.all(AppSpacing.screenX),
                    child: Text(
                      'No se pudo cargar la foto.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body(
                        context,
                      ).copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.xs,
            right: AppSpacing.xs,
            child: IconButton(
              key: const ValueKey('app-avatar-viewer-close'),
              tooltip: 'Cerrar',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

String _viewerLabel(String? personName) {
  final name = personName?.trim();
  return name == null || name.isEmpty
      ? 'Ver foto de perfil'
      : 'Ver foto de $name';
}
