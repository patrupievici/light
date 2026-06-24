import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../services/photo_progress_service.dart';
import '../../theme/zvelt_tokens.dart';
import 'photo_capture_screen.dart';

/// Gallery + side-by-side / overlay comparison for on-device progress photos.
///
/// Layout (top → bottom):
///   1. Horizontal thumb strip (newest first). Tap badge selects left/right.
///   2. Two-photo compare card with mode toggle: "Side-by-side" / "Overlay".
///      - Side-by-side: two Images, full-width, with date + days-elapsed.
///      - Overlay: stacked Images with a draggable vertical divider — a
///        classic "swipe between" before/after slider.
///   3. Privacy footer.
class PhotoProgressScreen extends StatefulWidget {
  const PhotoProgressScreen({super.key});

  @override
  State<PhotoProgressScreen> createState() => _PhotoProgressScreenState();
}

class _PhotoProgressScreenState extends State<PhotoProgressScreen> {
  List<ProgressPhoto> _photos = const [];
  ProgressPhoto? _left; // Day 0 by default
  ProgressPhoto? _right; // Latest by default
  bool _loading = true;
  bool _overlayMode = false;
  // Selection target for next thumb tap. null = neither (just preview).
  _Side? _picking;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final svc = PhotoProgressService.instance;
    final list = await svc.listPhotos();
    if (!mounted) return;
    setState(() {
      _photos = list;
      // Default: Day 0 = earliest (last in DESC list), Latest = newest (first).
      if (list.isNotEmpty) {
        _left = list.last;
        _right = list.first;
      } else {
        _left = null;
        _right = null;
      }
      _loading = false;
    });
  }

  Future<void> _takePhoto() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PhotoCaptureScreen()),
    );
    if (result is ProgressPhoto) {
      await _reload();
    }
  }

  Future<void> _confirmDelete(ProgressPhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: Text('Delete photo?',
            style: TextStyle(color: ZveltTokens.text)),
        content: Text(
          'This permanently removes the photo from this device.',
          style: TextStyle(color: ZveltTokens.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: TextStyle(color: ZveltTokens.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                const Text('Delete', style: TextStyle(color: ZveltTokens.error)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PhotoProgressService.instance.deletePhoto(photo.id);
      await _reload();
    }
  }

  void _onThumbTap(ProgressPhoto photo) {
    final side = _picking;
    setState(() {
      if (side == _Side.left) {
        _left = photo;
      } else if (side == _Side.right) {
        _right = photo;
      } else {
        // Default — replace right (the "after") on simple tap.
        _right = photo;
      }
      _picking = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        title: Text(
          'Photo Progress',
          style: TextStyle(
              color: ZveltTokens.text, fontWeight: FontWeight.w700),
        ),
        iconTheme: IconThemeData(color: ZveltTokens.text),
        actions: [
          if (_photos.isNotEmpty)
            IconButton(
              tooltip: 'Take photo',
              icon: const Icon(AppIcons.camera,
                  color: ZveltTokens.brand),
              onPressed: _takePhoto,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: ZveltTokens.brand))
          : (_photos.isEmpty ? _buildEmpty() : _buildContent()),
    );
  }

  // ── EMPTY ─────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(ZveltTokens.s6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: ZveltTokens.brand.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: ZveltTokens.brand.withValues(alpha: 0.30),
                  width: 1.5,
                ),
              ),
              child: const Icon(AppIcons.camera,
                  color: ZveltTokens.brand, size: 38),
            ),
            const SizedBox(height: 18),
            Text(
              'Take your first photo to\nstart your progress timeline.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ZveltTokens.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Photos stay on this device. Only you see them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _takePhoto,
              style: ElevatedButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: ZveltTokens.s6, vertical: ZveltTokens.s4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                ),
              ),
              icon: const Icon(AppIcons.camera, size: 18),
              label: const Text('Take photo',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ── CONTENT ───────────────────────────────────────────────────────

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s6),
      children: [
        _buildThumbStrip(),
        const SizedBox(height: 18),
        _buildModeToggle(),
        const SizedBox(height: 12),
        _buildCompare(),
        const SizedBox(height: 18),
        _buildPrivacyFooter(),
      ],
    );
  }

  Widget _buildThumbStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Timeline',
              style: TextStyle(
                color: ZveltTokens.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            if (_picking != null)
              Text(
                _picking == _Side.left
                    ? 'Pick for LEFT'
                    : 'Pick for RIGHT',
                style: const TextStyle(
                  color: ZveltTokens.brand,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _photos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _ThumbTile(
              photo: _photos[i],
              isLeft: _photos[i].id == _left?.id,
              isRight: _photos[i].id == _right?.id,
              onTap: () => _onThumbTap(_photos[i]),
              onLongPress: () => _confirmDelete(_photos[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s1),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Row(
        children: [
          _toggleSeg('Side-by-side', !_overlayMode,
              () => setState(() => _overlayMode = false)),
          _toggleSeg('Overlay', _overlayMode,
              () => setState(() => _overlayMode = true)),
        ],
      ),
    );
  }

  Widget _toggleSeg(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? ZveltTokens.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(ZveltTokens.rSm),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : ZveltTokens.text2,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompare() {
    if (_left == null || _right == null) {
      return const SizedBox.shrink();
    }
    final firstPhotoAt = _photos.isEmpty
        ? DateTime.now()
        : _photos
            .map((p) => p.takenAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);

    if (_overlayMode) {
      return _OverlayCompare(
        left: _left!,
        right: _right!,
        firstAt: firstPhotoAt,
        onPickLeft: () => setState(() => _picking = _Side.left),
        onPickRight: () => setState(() => _picking = _Side.right),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SidePane(
            photo: _left!,
            firstAt: firstPhotoAt,
            sideLabel: 'LEFT',
            onPick: () => setState(() => _picking = _Side.left),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SidePane(
            photo: _right!,
            firstAt: firstPhotoAt,
            sideLabel: 'RIGHT',
            onPick: () => setState(() => _picking = _Side.right),
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacyFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Row(
        children: [
          Icon(AppIcons.lock, size: 16, color: ZveltTokens.text2),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Photos stay on this device. Only you see them.',
              style: TextStyle(
                color: ZveltTokens.text2,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Side { left, right }

// ─── helpers ────────────────────────────────────────────────────────

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

int _daysSince(DateTime first, DateTime later) {
  final a = DateTime(first.year, first.month, first.day);
  final b = DateTime(later.year, later.month, later.day);
  return b.difference(a).inDays;
}

// ─── widgets ────────────────────────────────────────────────────────

class _ThumbTile extends StatelessWidget {
  const _ThumbTile({
    required this.photo,
    required this.isLeft,
    required this.isRight,
    required this.onTap,
    required this.onLongPress,
  });

  final ProgressPhoto photo;
  final bool isLeft;
  final bool isRight;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final selected = isLeft || isRight;
    return Semantics(
      button: true,
      selected: selected,
      label:
          'Photo from ${_fmtDate(photo.takenAt)}${isLeft ? ', selected as left' : isRight ? ', selected as right' : ''}. Tap to select, long-press to delete.',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
              border: Border.all(
                color: selected ? ZveltTokens.brand : ZveltTokens.border,
                width: selected ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(photo.file, fit: BoxFit.cover),
                if (isLeft)
                  Positioned(
                    top: 2,
                    left: 2,
                    child: _miniBadge('L'),
                  ),
                if (isRight)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: _miniBadge('R'),
                  ),
              ],
            ),
          ),
            const SizedBox(height: 5),
            Text(
              _fmtDate(photo.takenAt),
              style: ZType.eyebrow.copyWith(
                color: ZveltTokens.text2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBadge(String letter) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: ZveltTokens.brand,
          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
        ),
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _SidePane extends StatelessWidget {
  const _SidePane({
    required this.photo,
    required this.firstAt,
    required this.sideLabel,
    required this.onPick,
  });

  final ProgressPhoto photo;
  final DateTime firstAt;
  final String sideLabel;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final days = _daysSince(firstAt, photo.takenAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Day $days',
              style: const TextStyle(
                color: ZveltTokens.brand,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontStyle: FontStyle.italic,
              ),
            ),
            const Spacer(),
            Semantics(
              button: true,
              label: 'Pick photo for $sideLabel side',
              child: GestureDetector(
                onTap: onPick,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: ZveltTokens.s2, vertical: ZveltTokens.s1),
                  decoration: BoxDecoration(
                    color: ZveltTokens.brand.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                  ),
                  child: Text(
                    sideLabel,
                    style: const TextStyle(
                      color: ZveltTokens.brand,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _fmtDate(photo.takenAt),
          style: TextStyle(
            color: ZveltTokens.text2,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZveltTokens.rMd),
              border: Border.all(color: ZveltTokens.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.file(
              photo.file,
              fit: BoxFit.cover,
              semanticLabel:
                  'Progress photo, $sideLabel side, from ${_fmtDate(photo.takenAt)}',
            ),
          ),
        ),
      ],
    );
  }
}

/// Stack with a draggable vertical divider — drag the handle to reveal more
/// of the LEFT image (Day 0) over the RIGHT image (Latest) underneath, or
/// vice versa. The handle is clamped to [0.05, 0.95] so neither side ever
/// fully disappears.
class _OverlayCompare extends StatefulWidget {
  const _OverlayCompare({
    required this.left,
    required this.right,
    required this.firstAt,
    required this.onPickLeft,
    required this.onPickRight,
  });

  final ProgressPhoto left;
  final ProgressPhoto right;
  final DateTime firstAt;
  final VoidCallback onPickLeft;
  final VoidCallback onPickRight;

  @override
  State<_OverlayCompare> createState() => _OverlayComparePaneState();
}

class _OverlayComparePaneState extends State<_OverlayCompare> {
  double _split = 0.5; // fraction 0..1 of width occupied by LEFT image.

  @override
  Widget build(BuildContext context) {
    final daysLeft = _daysSince(widget.firstAt, widget.left.takenAt);
    final daysRight = _daysSince(widget.firstAt, widget.right.takenAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: widget.onPickLeft,
              child: _overlayHeader(
                  'Day $daysLeft', _fmtDate(widget.left.takenAt), 'LEFT'),
            ),
            const Spacer(),
            GestureDetector(
              onTap: widget.onPickRight,
              child: _overlayHeader(
                  'Day $daysRight', _fmtDate(widget.right.takenAt), 'RIGHT'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 3 / 4,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final dividerX = (_split.clamp(0.05, 0.95)) * w;
              return ClipRRect(
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) {
                    setState(() {
                      _split = (dividerX + d.delta.dx) / w;
                      _split = _split.clamp(0.05, 0.95);
                    });
                  },
                  child: Stack(
                    children: [
                      // RIGHT image full-width underneath.
                      Positioned.fill(
                        child: Image.file(widget.right.file, fit: BoxFit.cover),
                      ),
                      // LEFT image clipped to the left of the divider.
                      Positioned.fill(
                        child: ClipRect(
                          clipper: _LeftClipper(_split.clamp(0.05, 0.95)),
                          child: Image.file(widget.left.file, fit: BoxFit.cover),
                        ),
                      ),
                      // Divider line.
                      Positioned(
                        left: dividerX - 1,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: Colors.white),
                      ),
                      // Drag handle.
                      Positioned(
                        left: dividerX - 18,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: ZveltTokens.brand,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(AppIcons.arrows_repeat,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                      // Corner labels so users know which side is which.
                      const Positioned(
                        top: 8,
                        left: 8,
                        child: _CornerLabel('LEFT'),
                      ),
                      const Positioned(
                        top: 8,
                        right: 8,
                        child: _CornerLabel('RIGHT'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Drag the handle to compare.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ZveltTokens.text2, fontSize: 11),
        ),
      ],
    );
  }

  Widget _overlayHeader(String day, String date, String side) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          day,
          style: const TextStyle(
            color: ZveltTokens.brand,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
          ),
        ),
        Text(
          '$date · $side',
          style: TextStyle(color: ZveltTokens.text2, fontSize: 11),
        ),
      ],
    );
  }
}

class _CornerLabel extends StatelessWidget {
  const _CornerLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s2, vertical: ZveltTokens.s1),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      );
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(covariant _LeftClipper old) => old.fraction != fraction;
}
