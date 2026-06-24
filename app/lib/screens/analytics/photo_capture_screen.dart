import 'dart:io';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/photo_progress_service.dart';
import '../../theme/zvelt_tokens.dart';

/// Thin wrapper around [ImagePicker] that captures a single photo from the
/// device camera and persists it via [PhotoProgressService].
///
/// We intentionally launch the OS camera UI instead of building one ourselves
/// — the OS UI handles permissions, focus, and exposure for free, which is
/// more than good enough for the v1.0 "before/after timeline" use case.
class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget — open camera as soon as the screen mounts so users
    // don't see an empty intermediate screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final XFile? x = await _picker.pickImage(
        source: ImageSource.camera,
        // 1600px on the long edge keeps files ~300-700KB while still being
        // sharp enough for a side-by-side compare on a 6.7" phone.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (!mounted) return;
      if (x == null) {
        // User cancelled — pop back to whoever pushed us.
        Navigator.of(context).pop(false);
        return;
      }
      try {
        final saved = await PhotoProgressService.instance.savePhoto(File(x.path));
        if (!mounted) return;
        Navigator.of(context).pop(saved);
      } on FileSystemException catch (e) {
        // Most common cause: disk full or sandbox quota hit.
        if (!mounted) return;
        setState(() => _error =
            "Couldn't save photo. Free up space and try again.\n(${e.osError?.message ?? e.message})");
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      // camera_access_denied → user denied permission in the OS prompt.
      final denied = (e.code).toLowerCase().contains('denied') ||
          (e.code).toLowerCase().contains('permission');
      setState(() => _error = denied
          ? 'Camera access is required to capture progress photos. Grant camera access in Settings.'
          : 'Camera unavailable: ${e.message ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Couldn't capture photo: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        title: Text('Photo Progress',
            style: TextStyle(color: ZveltTokens.text)),
        iconTheme: IconThemeData(color: ZveltTokens.text),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(ZveltTokens.s6),
          child: _busy
              ? const CircularProgressIndicator(color: ZveltTokens.brand)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.camera,
                        size: 64,
                        color: ZveltTokens.text2.withValues(alpha: 0.7)),
                    const SizedBox(height: ZveltTokens.s4),
                    Text(
                      _error ?? 'Opening camera…',
                      textAlign: TextAlign.center,
                      style: ZType.bodyM.copyWith(
                        color: _error == null
                            ? ZveltTokens.text2
                            : ZveltTokens.error,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: ZveltTokens.s6),
                    ElevatedButton.icon(
                      onPressed: _capture,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ZveltTokens.brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: ZveltTokens.s6, vertical: ZveltTokens.s4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                        ),
                      ),
                      icon: const Icon(AppIcons.camera, size: 18),
                      label: Text(_error == null ? 'Open camera' : 'Try again'),
                    ),
                    const SizedBox(height: ZveltTokens.s2),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text('Cancel',
                          style: TextStyle(color: ZveltTokens.text2)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
