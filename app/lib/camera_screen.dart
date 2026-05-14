import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'translations.dart';

/// Result returned when the user takes a photo and chooses an action.
class CameraResult {
  final String imagePath;
  final CameraAction action;

  const CameraResult({required this.imagePath, required this.action});
}

enum CameraAction { post, scanAI }

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  List<CameraDescription> cameras = [];

  // Preview of the captured photo before the user chooses action
  String? _capturedImagePath;

  late final AnimationController _fabAnimController;
  late final Animation<double> _fabScaleAnim;

  @override
  void initState() {
    super.initState();
    _initializeCamera();

    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fabScaleAnim = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _fabAnimController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeCamera() async {
    try {
      cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _controller = CameraController(
          cameras.first,
          ResolutionPreset.high,
        );
        _initializeControllerFuture = _controller!.initialize();
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${Translations.text(context, 'camera_init_error')}: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _fabAnimController.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    try {
      _fabAnimController.forward().then((_) => _fabAnimController.reverse());
      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      if (!mounted) return;

      // Show the preview + choice sheet instead of popping immediately
      setState(() => _capturedImagePath = image.path);
      _showActionSheet(image.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${Translations.text(context, 'camera_take_error')}: $e')),
        );
      }
    }
  }

  /// Bottom sheet that asks the user what to do with the captured photo.
  void _showActionSheet(String imagePath) {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,          // allows sheet > 50% height
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ActionChoiceSheet(
          imagePath: imagePath,
          onScanAI: () {
            Navigator.of(sheetContext).pop();
            Navigator.of(context).pop(
              CameraResult(imagePath: imagePath, action: CameraAction.scanAI),
            );
          },
          onPost: () {
            Navigator.of(sheetContext).pop();
            Navigator.of(context).pop(
              CameraResult(imagePath: imagePath, action: CameraAction.post),
            );
          },
          onRetake: () {
            Navigator.of(sheetContext).pop();
            setState(() => _capturedImagePath = null);
          },
        );
      },
    ).then((_) {
      if (mounted && _capturedImagePath != null) {
        setState(() => _capturedImagePath = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: Colors.black,
      body: _controller == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Camera preview
                      CameraPreview(_controller!),

                      // Preview overlay when photo is captured
                      if (_capturedImagePath != null)
                        kIsWeb
                            ? Image.network(
                                _capturedImagePath!,
                                fit: BoxFit.cover,
                              )
                            : Image.file(
                                File(_capturedImagePath!),
                                fit: BoxFit.cover,
                              ),

                      // Top bar
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _CircleIconButton(
                                  icon: Icons.close,
                                  onTap: () => Navigator.of(context).pop(),
                                ),
                                Text(
                                  Translations.text(context, 'camera'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 44), // balance
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Bottom shutter button
                      Positioned(
                        bottom: 40,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: ScaleTransition(
                            scale: _fabScaleAnim,
                            child: GestureDetector(
                              onTap: _capturedImagePath == null
                                  ? _takePicture
                                  : null,
                              child: Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 4,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _capturedImagePath == null
                                          ? Colors.white
                                          : primaryColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
              },
            ),
    );
  }
}

// ─── Action Choice Bottom Sheet ───────────────────────────────────────────────

class _ActionChoiceSheet extends StatelessWidget {
  final String imagePath;
  final VoidCallback onScanAI;
  final VoidCallback onPost;
  final VoidCallback onRetake;

  const _ActionChoiceSheet({
    required this.imagePath,
    required this.onScanAI,
    required this.onPost,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final screenHeight = MediaQuery.of(context).size.height;
    final safePaddingBottom = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, safePaddingBottom + 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Photo — tall thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: kIsWeb
                      ? Image.network(
                          imagePath,
                          height: screenHeight * 0.45,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : Image.file(
                          File(imagePath),
                          height: screenHeight * 0.45,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                ),

                const SizedBox(height: 16),

                Text(
                  Translations.text(context, 'what_to_do_with_photo'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // Action buttons row
                Row(
                  children: [
                    Expanded(
                      child: _ChoiceButton(
                        icon: Icons.auto_awesome,
                        label: Translations.text(context, 'scan_with_ai'),
                        subtitle: Translations.text(context, 'species_info'),
                        color: const Color(0xFF7C3AED),
                        onTap: onScanAI,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ChoiceButton(
                        icon: Icons.add_photo_alternate,
                        label: Translations.text(context, 'post'),
                        subtitle: Translations.text(context, 'share_on_feed'),
                        color: primaryColor,
                        onTap: onPost,
                      ),
                    ),
                  ],
                ),

                // Retake — compact
                TextButton.icon(
                  onPressed: onRetake,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(Translations.text(context, 'retake')),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade500,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _ChoiceButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ChoiceButton> createState() => _ChoiceButtonState();
}

class _ChoiceButtonState extends State<_ChoiceButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.color.withOpacity(0.3), width: 1.5),
          ),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 10),
              Text(
                widget.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: widget.color,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Small circle icon button for the top bar ─────────────────────────────────

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withOpacity(0.45),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}