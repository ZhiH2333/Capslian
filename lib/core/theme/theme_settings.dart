/// 主题可配置项：卡片透明度、AppBar 透明、字体等。
class ThemeSettings {
  const ThemeSettings({
    this.cardTransparency = 1.0,
    this.appBarTransparent = false,
    this.customFonts,
    this.showBackgroundImage = false,
  });

  /// 卡片颜色透明度，0～1。
  final double cardTransparency;

  /// 是否使用透明 AppBar（elevation 0、透明背景）。
  final bool appBarTransparent;

  /// 逗号分隔的字体 family 列表，作为 fallback。
  final String? customFonts;

  /// 是否显示背景图（与 AppBackground 配合）。
  final bool showBackgroundImage;

  ThemeSettings copyWith({
    double? cardTransparency,
    bool? appBarTransparent,
    String? customFonts,
    bool? showBackgroundImage,
  }) {
    return ThemeSettings(
      cardTransparency: cardTransparency ?? this.cardTransparency,
      appBarTransparent: appBarTransparent ?? this.appBarTransparent,
      customFonts: customFonts ?? this.customFonts,
      showBackgroundImage: showBackgroundImage ?? this.showBackgroundImage,
    );
  }

  List<String> get fontFamilyList {
    if (customFonts == null || customFonts!.isEmpty) return <String>[];
    return customFonts!.split(',').map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList();
  }
}
