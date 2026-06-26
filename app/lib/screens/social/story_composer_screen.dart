import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/_crash_reporter.dart';
import '../../services/stories_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';

/// Compose + publish a 24h story: pick a photo (camera/gallery), add an optional
/// caption + location, share. Pops `true` on success so the feed reloads its
/// story tray. A caption-only (no photo) story is allowed.
class StoryComposerScreen extends StatefulWidget {
  const StoryComposerScreen({super.key, required this.service});

  final StoriesService service;

  @override
  State<StoryComposerScreen> createState() => _StoryComposerScreenState();
}

class _StoryComposerScreenState extends State<StoryComposerScreen> {
  final _picker = ImagePicker();
  final _captionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  Uint8List? _bytes;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _captionCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canPost =>
      !_posting && (_bytes != null || _captionCtrl.text.trim().isNotEmpty);

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (e, st) {
      reportError(e, st, reason: 'stories:pick');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nu am putut accesa imaginea.')),
      );
    }
  }

  Future<void> _post() async {
    if (!_canPost) return;
    setState(() => _posting = true);
    try {
      await widget.service.createStory(
        caption: _captionCtrl.text,
        location: _locationCtrl.text,
        imageBytes: _bytes,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      reportError(e, st, reason: 'stories:create');
      if (!mounted) return;
      setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nu am putut posta story-ul. Încearcă din nou.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Story nou', style: ZType.h4.copyWith(color: ZveltTokens.text)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: ZveltTokens.s3),
            child: TextButton(
              onPressed: _canPost ? _post : null,
              child: _posting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.brand),
                    )
                  : Text('Postează',
                      style: ZType.bodyM.copyWith(
                        color: _canPost ? ZveltTokens.brand : ZveltTokens.text4,
                        fontWeight: FontWeight.w700,
                      )),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(ZveltTokens.screenPaddingH),
        children: [
          _photoArea(),
          const SizedBox(height: ZveltTokens.s5),
          TextField(
            controller: _captionCtrl,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
            style: ZType.bodyM.copyWith(color: ZveltTokens.text),
            decoration: _decoration('Scrie un caption…', counter: true),
          ),
          const SizedBox(height: ZveltTokens.s3),
          TextField(
            controller: _locationCtrl,
            maxLength: 200,
            style: ZType.bodyM.copyWith(color: ZveltTokens.text),
            decoration: _decoration('Locație (opțional)', icon: AppIcons.location_alt),
          ),
        ],
      ),
    );
  }

  Widget _photoArea() {
    if (_bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Image.memory(_bytes!, fit: BoxFit.cover, width: double.infinity),
            ),
            Positioned(
              top: ZveltTokens.s2,
              right: ZveltTokens.s2,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => setState(() => _bytes = null),
                  icon: const Icon(AppIcons.cross_small, color: Colors.white, size: 20),
                  tooltip: 'Elimină',
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: ZveltTokens.surface2,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.picture, color: ZveltTokens.text3, size: 40),
          const SizedBox(height: ZveltTokens.s3),
          Text('Adaugă o poză la story', style: ZType.bodyM.copyWith(color: ZveltTokens.text3)),
          const SizedBox(height: ZveltTokens.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _pickButton(AppIcons.camera, 'Cameră', () => _pick(ImageSource.camera)),
              const SizedBox(width: ZveltTokens.s3),
              _pickButton(AppIcons.picture, 'Galerie', () => _pick(ImageSource.gallery)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pickButton(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: ZveltTokens.brand,
        side: const BorderSide(color: ZveltTokens.brand),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  InputDecoration _decoration(String hint, {bool counter = false, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: ZType.bodyM.copyWith(color: ZveltTokens.text4),
      counterText: counter ? null : '',
      prefixIcon: icon != null ? Icon(icon, color: ZveltTokens.text3, size: 18) : null,
      filled: true,
      fillColor: ZveltTokens.surface,
      contentPadding: const EdgeInsets.all(ZveltTokens.s4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        borderSide: BorderSide(color: ZveltTokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        borderSide: BorderSide(color: ZveltTokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        borderSide: const BorderSide(color: ZveltTokens.brand, width: 1.5),
      ),
    );
  }
}
