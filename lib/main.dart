import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

void main() => runApp(const OneTeleApp());

class OneTeleApp extends StatelessWidget {
  const OneTeleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OneTele',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          useMaterial3: true, colorSchemeSeed: const Color(0xFF14B8A6)),
      home: const TeleprompterScreen(),
    );
  }
}

class TeleprompterScreen extends StatefulWidget {
  const TeleprompterScreen({super.key});

  @override
  State<TeleprompterScreen> createState() => _TeleprompterScreenState();
}

class _TeleprompterScreenState extends State<TeleprompterScreen> {
  List<String> _questions = [];
  int _index = 0;
  String? _fileName;

  // Display settings. When null, a viewport-relative default is used so the
  // first render matches the reference screenshot on any screen size.
  double? _fontSize; // px
  double? _maxWidth; // px (wrap width of the text column)
  double _topFraction = 0.155; // distance from top as fraction of height

  bool _dark = false; // false = white bg / black text
  bool _showControls = true;
  bool _showLogo = true; // faint centered OneTELE watermark

  // When non-null ('font' | 'width' | 'top'), arrow keys adjust that slider
  // instead of changing the question.
  String? _selectedControl;

  // ---- Tuned to the reference screenshot (proportional, so it scales) ----
  static const double _defaultFontFraction = 0.033; // ~ cap height of the SS
  static const double _defaultWidthFraction = 0.60; // centered column width

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  // Global key handler so arrow keys work no matter what has focus
  // (e.g. after dragging a slider with the mouse).
  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final k = event.logicalKey;

    // If a slider is selected, arrow keys adjust its value.
    if (_selectedControl != null) {
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowDown) {
        _adjustSelected(-1);
        return true;
      }
      if (k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.arrowUp) {
        _adjustSelected(1);
        return true;
      }
      if (k == LogicalKeyboardKey.escape) {
        setState(() => _selectedControl = null);
        return true;
      }
    }

    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.pageDown) {
      _go(_index + 1);
      return true;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.pageUp) {
      _go(_index - 1);
      return true;
    }
    if (k == LogicalKeyboardKey.home) {
      _go(0);
      return true;
    }
    if (k == LogicalKeyboardKey.end) {
      _go(_questions.length - 1);
      return true;
    }
    if (k == LogicalKeyboardKey.keyH) {
      setState(() => _showControls = !_showControls);
      return true;
    }
    if (k == LogicalKeyboardKey.keyB) {
      setState(() => _dark = !_dark);
      return true;
    }
    if (k == LogicalKeyboardKey.keyL) {
      setState(() => _showLogo = !_showLogo);
      return true;
    }
    return false;
  }

  void _go(int i) {
    if (_questions.isEmpty) return;
    final clamped = i.clamp(0, _questions.length - 1);
    if (clamped != _index) setState(() => _index = clamped);
  }

  // Step the currently selected slider. dir is +1 or -1.
  void _adjustSelected(int dir) {
    final size = MediaQuery.of(context).size;
    switch (_selectedControl) {
      case 'font':
        final cur = _fontSize ?? size.height * _defaultFontFraction;
        setState(() => _fontSize = (cur + dir * 2).clamp(16.0, 160.0));
        break;
      case 'width':
        final cur = _maxWidth ?? size.width * _defaultWidthFraction;
        setState(() => _maxWidth = (cur + dir * 20).clamp(240.0, size.width));
        break;
      case 'top':
        setState(
            () => _topFraction = (_topFraction + dir * 0.01).clamp(0.0, 0.6));
        break;
    }
  }

  // Click a control label to select it (or click it again to release).
  void _toggleSelect(String name) {
    setState(() => _selectedControl = _selectedControl == name ? null : name);
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
        withData: true,
      );
      if (result == null) return;
      final bytes = result.files.single.bytes;
      final name = result.files.single.name;
      if (bytes == null) {
        _toast('Could not read the file data.');
        return;
      }
      final questions = _parseDocx(bytes);
      if (questions.isEmpty) {
        _toast('No text paragraphs were found in that document.');
        return;
      }
      setState(() {
        _questions = questions;
        _index = 0;
        _fileName = name;
      });
    } catch (e) {
      _toast('Failed to load file: $e');
    }
  }

  // Extract one entry per non-empty paragraph from a .docx (OOXML zip).
  List<String> _parseDocx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.files.firstWhere(
      (f) => f.name == 'word/document.xml',
      orElse: () => throw 'document.xml not found - is this a valid .docx?',
    );
    final xmlString = utf8.decode(entry.content as List<int>);
    final doc = XmlDocument.parse(xmlString);

    final result = <String>[];
    final paragraphs = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.prefix == 'w' && e.name.local == 'p');

    for (final p in paragraphs) {
      final sb = StringBuffer();
      for (final n in p.descendants.whereType<XmlElement>()) {
        if (n.name.prefix != 'w') continue;
        switch (n.name.local) {
          case 't':
            sb.write(n.innerText);
            break;
          case 'tab':
            sb.write('\t');
            break;
          case 'br':
          case 'cr':
            sb.write('\n');
            break;
        }
      }
      final text = sb.toString().trim();
      if (text.isNotEmpty) result.add(text);
    }
    return result;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bg = _dark ? Colors.black : Colors.white;
    final fg = _dark ? Colors.white : Colors.black;

    final fontSize = _fontSize ?? size.height * _defaultFontFraction;
    final maxWidth = _maxWidth ?? size.width * _defaultWidthFraction;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // Faint centered OneTELE watermark (behind the reading text)
          if (_showLogo)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Opacity(
                    opacity: _dark ? 0.13 : 0.10,
                    child: _Watermark(dark: _dark, width: size.width * 0.52),
                  ),
                ),
              ),
            ),

          // The reading area
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _selectedControl == null
                  ? null
                  : () => setState(() => _selectedControl = null),
              child: _questions.isEmpty
                  ? _EmptyState(dark: _dark, onPick: _pickFile)
                  : Padding(
                      padding: EdgeInsets.only(top: size.height * _topFraction),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: maxWidth,
                          child: Text(
                            _questions[_index],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: fg,
                              fontSize: fontSize,
                              height: 1.35,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),

          // Small persistent toggle so controls can be brought back
          if (!_showControls)
            Positioned(
              top: 12,
              right: 12,
              child: _GhostButton(
                icon: Icons.tune,
                onTap: () => setState(() => _showControls = true),
              ),
            ),

          // Bottom control bar
          if (_showControls)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ControlBar(
                index: _index,
                total: _questions.length,
                fontSize: fontSize,
                maxWidth: maxWidth,
                topFraction: _topFraction,
                dark: _dark,
                screenWidth: size.width,
                onPrev: () => _go(_index - 1),
                onNext: () => _go(_index + 1),
                onPick: _pickFile,
                onToggleDark: () => setState(() => _dark = !_dark),
                showLogo: _showLogo,
                onToggleLogo: () => setState(() => _showLogo = !_showLogo),
                onHide: () => setState(() {
                  _showControls = false;
                  _selectedControl = null;
                }),
                onFont: (v) => setState(() => _fontSize = v),
                onWidth: (v) => setState(() => _maxWidth = v),
                onTop: (v) => setState(() => _topFraction = v),
                selected: _selectedControl,
                onSelect: _toggleSelect,
                fileName: _fileName,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool dark;
  final VoidCallback onPick;
  const _EmptyState({required this.dark, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : Colors.black87;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 56, color: fg.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text('OneTele',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w600, color: fg)),
          const SizedBox(height: 8),
          Text('Load a .docx file to begin. Each paragraph becomes a question.',
              style: TextStyle(fontSize: 15, color: fg.withOpacity(0.7))),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open .docx'),
          ),
          const SizedBox(height: 28),
          Text('←  →  change question     H  hide controls     B  background',
              style: TextStyle(fontSize: 12, color: fg.withOpacity(0.5))),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  final int index;
  final int total;
  final double fontSize;
  final double maxWidth;
  final double topFraction;
  final bool dark;
  final double screenWidth;
  final String? fileName;
  final String? selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback onToggleDark;
  final bool showLogo;
  final VoidCallback onToggleLogo;
  final VoidCallback onHide;
  final ValueChanged<double> onFont;
  final ValueChanged<double> onWidth;
  final ValueChanged<double> onTop;

  const _ControlBar({
    required this.index,
    required this.total,
    required this.fontSize,
    required this.maxWidth,
    required this.topFraction,
    required this.dark,
    required this.screenWidth,
    required this.fileName,
    required this.selected,
    required this.onSelect,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onToggleDark,
    required this.showLogo,
    required this.onToggleLogo,
    required this.onHide,
    required this.onFont,
    required this.onWidth,
    required this.onTop,
  });

  @override
  Widget build(BuildContext context) {
    const onColor = Colors.white;
    final hasContent = total > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.82),
        border: const Border(top: BorderSide(color: Colors.white24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Navigation row
          Row(
            children: [
              IconButton(
                tooltip: 'Open .docx',
                onPressed: onPick,
                icon: const Icon(Icons.folder_open, color: onColor),
              ),
              IconButton(
                tooltip: 'Previous  (←)',
                onPressed: hasContent ? onPrev : null,
                icon: const Icon(Icons.chevron_left, color: onColor, size: 30),
              ),
              Text(
                hasContent ? '${index + 1} / $total' : '— / —',
                style: const TextStyle(
                    color: onColor, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              IconButton(
                tooltip: 'Next  (→)',
                onPressed: hasContent ? onNext : null,
                icon: const Icon(Icons.chevron_right, color: onColor, size: 30),
              ),
              const SizedBox(width: 8),
              if (fileName != null)
                Expanded(
                  child: Text(
                    fileName!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                )
              else
                const Spacer(),
              IconButton(
                tooltip: 'Background  (B)',
                onPressed: onToggleDark,
                icon: Icon(dark ? Icons.light_mode : Icons.dark_mode,
                    color: onColor),
              ),
              IconButton(
                tooltip: 'Logo watermark  (L)',
                onPressed: onToggleLogo,
                icon: Icon(showLogo ? Icons.image : Icons.hide_image_outlined,
                    color: onColor),
              ),
              IconButton(
                tooltip: 'Hide controls  (H)',
                onPressed: onHide,
                icon: const Icon(Icons.visibility_off, color: onColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Sliders row
          Row(
            children: [
              _LabeledSlider(
                label: 'Font',
                value: fontSize,
                min: 16,
                max: 160,
                display: fontSize.round().toString(),
                selected: selected == 'font',
                onSelect: () => onSelect('font'),
                onChanged: onFont,
              ),
              _LabeledSlider(
                label: 'Width',
                value: maxWidth.clamp(240.0, screenWidth),
                min: 240,
                max: screenWidth,
                display: '${((maxWidth / screenWidth) * 100).round()}%',
                selected: selected == 'width',
                onSelect: () => onSelect('width'),
                onChanged: onWidth,
              ),
              _LabeledSlider(
                label: 'Top',
                value: topFraction,
                min: 0.0,
                max: 0.6,
                display: '${(topFraction * 100).round()}%',
                selected: selected == 'top',
                onSelect: () => onSelect('top'),
                onChanged: onTop,
              ),
            ],
          ),
          if (selected != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '← → adjusts ${selected![0].toUpperCase()}${selected!.substring(1)}  ·  Esc to release',
                style: const TextStyle(color: Color(0xFF5EEAD4), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF14B8A6);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tap the label to select / release this control.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSelect,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (selected)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child:
                                Icon(Icons.keyboard, size: 13, color: accent),
                          ),
                        Text(
                          label,
                          style: TextStyle(
                            color: selected ? accent : Colors.white70,
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      display,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GhostButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.35),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        tooltip: 'Show controls  (H)',
      ),
    );
  }
}

/// The recolored OneTELE logo: purple disc mark + "One" (medium) "TELE" (bold).
class _Watermark extends StatelessWidget {
  final bool dark;
  final double width;
  const _Watermark({required this.dark, required this.width});

  @override
  Widget build(BuildContext context) {
    final textColor = dark ? const Color(0xFFEDEDED) : const Color(0xFF2F2F31);
    return SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child:
                  CustomPaint(painter: OneMarkPainter(const Color(0xFF7C3AED))),
            ),
            const SizedBox(width: 24),
            Text.rich(
              TextSpan(children: const [
                TextSpan(
                    text: 'One', style: TextStyle(fontWeight: FontWeight.w500)),
                TextSpan(
                    text: 'TELE',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ]),
              style: TextStyle(
                fontSize: 120,
                color: textColor,
                letterSpacing: -1,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the circular OneTELE mark: purple disc, broken white ring, white "1".
class OneMarkPainter extends CustomPainter {
  final Color circleColor;
  OneMarkPainter(this.circleColor);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);

    // Purple disc
    canvas.drawCircle(c, s / 2, Paint()..color = circleColor);

    // Thin open ring (single gap at the lower-right, ~4:30)
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.035 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 0.32 * s),
      1.1519, // start 66deg
      5.6549, // sweep 324deg -> ~36deg gap at lower-right
      false,
      ring,
    );

    // Bold "1": flag + vertical stem (coords in a 200-unit design box)
    final f = s / 200.0;
    final topLeft = Offset(c.dx - s / 2, c.dy - s / 2);
    Offset p(double x, double y) => topLeft + Offset(x * f, y * f);
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.11 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(p(84, 70).dx, p(84, 70).dy)
        ..lineTo(p(108, 54).dx, p(108, 54).dy)
        ..lineTo(p(108, 152).dx, p(108, 152).dy),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant OneMarkPainter old) =>
      old.circleColor != circleColor;
}
