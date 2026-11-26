import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../l10n/strings.dart';

const String kSearchBarHeroTag = 'search-bar';
const double _height = 44;

/// 搜索栏的外观（圆角胶囊 + 放大镜）。列表页的入口、搜索页的输入框、Hero 飞行中的画面共用这一份，
/// 保证起点、终点和飞行过程三者完全一致，飞行时看不出「换了一个控件」。
class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: _height,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(_height / 2),
        border: Border.all(color: p.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: p.textTertiary),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Text(
      S.of(context).searchHint,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 14.5, color: context.palette.textTertiary),
    );
  }
}

/// 飞行途中渲染静态外观，而不是把 TextField 搬进 Overlay：
/// 输入框带焦点和控制器，在飞行层里再建一份会出现两个同控制器的 TextField。
Widget _shuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) => const Material(
  type: MaterialType.transparency,
  child: _Pill(child: _Placeholder()),
);

/// 列表页上的搜索入口：点击后以共享元素飞到搜索页顶部。
class SearchBarHero extends StatelessWidget {
  const SearchBarHero({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: S.of(context).searchHint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const Hero(
          tag: kSearchBarHeroTag,
          flightShuttleBuilder: _shuttle,
          child: Material(
            type: MaterialType.transparency,
            child: _Pill(child: _Placeholder()),
          ),
        ),
      ),
    );
  }
}

/// 搜索页里的输入框，外观与入口一致。
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Hero(
      tag: kSearchBarHeroTag,
      flightShuttleBuilder: _shuttle,
      child: Material(
        type: MaterialType.transparency,
        child: _Pill(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  style: TextStyle(fontSize: 14.5, color: p.text),
                  cursorColor: p.accent,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: S.of(context).searchHint,
                    hintStyle: TextStyle(fontSize: 14.5, color: p.textTertiary),
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => AnimatedScale(
                  scale: value.text.isEmpty ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onClear,
                    icon: Icon(Icons.cancel_rounded, size: 18, color: p.textTertiary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
