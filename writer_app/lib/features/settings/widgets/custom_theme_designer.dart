import 'package:flutter/material.dart';
import '../../editor/providers/theme_provider.dart';

class CustomThemeDesigner extends StatefulWidget {
  final WriterTheme currentTheme;
  final ValueChanged<WriterTheme> onThemeChanged;

  const CustomThemeDesigner({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
  });

  @override
  State<CustomThemeDesigner> createState() => _CustomThemeDesignerState();
}

class _CustomThemeDesignerState extends State<CustomThemeDesigner> {
  late TextEditingController _bgController;
  late TextEditingController _fgController;

  static const List<Color> bgSwatches = [
    Color(0xFFFBF8EB), // Soft Cream
    Color(0xFFF5F5F5), // Pure Paper
    Color(0xFFFDF0F5), // Sakura Blush
    Color(0xFF0D0E15), // Deep Obsidian
    Color(0xFF051026), // Cyber Blue
    Color(0xFF162521), // Forest Dark
    Color(0xFF000000), // Solid Black
  ];

  static const List<Color> fgSwatches = [
    Color(0xFF1E1E1E), // Soft Charcoal
    Color(0xFFE5E5E5), // Warm White
    Color(0xFFFFAA00), // Amber Gold
    Color(0xFF00FF9F), // Neon Green
    Color(0xFFC0CAF5), // Aura Blue
    Color(0xFFE8C5C8), // Rose Gold
    Color(0xFFFF0055), // Cyber Pink
  ];

  @override
  void initState() {
    super.initState();
    _bgController = TextEditingController(text: _colorToHex(widget.currentTheme.backgroundColor));
    _fgController = TextEditingController(text: _colorToHex(widget.currentTheme.foregroundColor));
  }

  @override
  void didUpdateWidget(covariant CustomThemeDesigner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep inputs in sync if theme is switched externally
    if (widget.currentTheme.name != 'Custom') {
      _bgController.text = _colorToHex(widget.currentTheme.backgroundColor);
      _fgController.text = _colorToHex(widget.currentTheme.foregroundColor);
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _fgController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    return color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
  }

  void _updateTheme(Color bg, Color fg) {
    widget.onThemeChanged(
      WriterTheme(
        name: 'Custom',
        backgroundColor: bg,
        foregroundColor: fg,
        sidebarColor: bg,
      ),
    );
  }

  void _onHexChanged() {
    final bgHex = _bgController.text.trim();
    final fgHex = _fgController.text.trim();
    
    final bgVal = int.tryParse('0xFF$bgHex') ?? widget.currentTheme.backgroundColor.value;
    final fgVal = int.tryParse('0xFF$fgHex') ?? widget.currentTheme.foregroundColor.value;

    _updateTheme(Color(bgVal), Color(fgVal));
  }

  @override
  Widget build(BuildContext context) {
    final panelTheme = widget.currentTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: panelTheme.sidebarColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: panelTheme.foregroundColor.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CUSTOM THEME DESIGNER',
            style: TextStyle(
              color: panelTheme.foregroundColor.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 20),
          
          // Background Color Config
          _buildColorSection(
            label: 'BACKGROUND COLOR',
            controller: _bgController,
            currentSelected: panelTheme.backgroundColor,
            swatches: bgSwatches,
            onSwatchTap: (color) {
              _bgController.text = _colorToHex(color);
              _updateTheme(color, panelTheme.foregroundColor);
            },
            panelTheme: panelTheme,
          ),
          
          const Divider(height: 32, thickness: 1, color: Colors.transparent),
          
          // Foreground Color Config
          _buildColorSection(
            label: 'FOREGROUND COLOR',
            controller: _fgController,
            currentSelected: panelTheme.foregroundColor,
            swatches: fgSwatches,
            onSwatchTap: (color) {
              _fgController.text = _colorToHex(color);
              _updateTheme(panelTheme.backgroundColor, color);
            },
            panelTheme: panelTheme,
          ),
        ],
      ),
    );
  }

  Widget _buildColorSection({
    required String label,
    required TextEditingController controller,
    required Color currentSelected,
    required List<Color> swatches,
    required ValueChanged<Color> onSwatchTap,
    required WriterTheme panelTheme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: panelTheme.foregroundColor.withValues(alpha: 0.4),
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            // Custom Hex input field
            Container(
              width: 100,
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: panelTheme.foregroundColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Text('#', style: TextStyle(color: panelTheme.foregroundColor.withValues(alpha: 0.4), fontSize: 11)),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      style: TextStyle(color: panelTheme.foregroundColor, fontSize: 11, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.only(left: 4),
                      ),
                      onChanged: (_) => _onHexChanged(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Swatches grid
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: swatches.map((color) {
            final isCurrent = color.value == currentSelected.value;
            return GestureDetector(
              onTap: () => onSwatchTap(color),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCurrent 
                        ? Colors.blue 
                        : panelTheme.foregroundColor.withValues(alpha: 0.15),
                    width: isCurrent ? 2.5 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
