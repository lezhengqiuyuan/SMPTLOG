/// 通用 UI 组件。
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 页面容器：限制最大宽度并水平居中。
///
/// 桌面端屏幕很宽时，内容不应被拉满整个窗口（否则表格/表单会
/// 出现大片空白与超长输入框），统一收在 1240 以内好看得多。
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 1240});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 选择器的一项。
class AppPickerOption<T> {
  const AppPickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.badge,
  });

  final T value;
  final String label;
  final String? subtitle;
  final String? badge;
}

/// 统一的选项弹层：手机为底部弹层，桌面为居中弹窗。
Future<T?> showAppPicker<T>(
  BuildContext context, {
  required String title,
  required List<AppPickerOption<T>> options,
  T? selected,
  bool searchable = true,
}) {
  final wide = MediaQuery.of(context).size.width >= 600;
  final body = _PickerBody<T>(
    title: title,
    options: options,
    selected: selected,
    searchable: searchable && options.length > 7,
    wide: wide,
  );

  if (wide) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(ctx).cardTheme.color,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
          child: body,
        ),
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardTheme.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: body,
      ),
    ),
  );
}

class _PickerBody<T> extends StatefulWidget {
  const _PickerBody({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchable,
    required this.wide,
  });

  final String title;
  final List<AppPickerOption<T>> options;
  final T? selected;
  final bool searchable;
  final bool wide;

  @override
  State<_PickerBody<T>> createState() => _PickerBodyState<T>();
}

class _PickerBodyState<T> extends State<_PickerBody<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final list = _q.isEmpty
        ? widget.options
        : widget.options
            .where((o) =>
                o.label.toLowerCase().contains(_q.toLowerCase()) ||
                (o.subtitle ?? '').toLowerCase().contains(_q.toLowerCase()))
            .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.wide)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: t.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, widget.wide ? 18 : 10, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                hintText: '搜索…',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
        Flexible(
          child: list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      '没有匹配项',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSub),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final o = list[i];
                    final sel = o.value == widget.selected;
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(o.value),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.primary.withValues(alpha: 0.09)
                              : null,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          o.label,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: sel
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: sel
                                                ? AppColors.primary
                                                : null,
                                          ),
                                        ),
                                      ),
                                      if (o.badge != null) ...[
                                        const SizedBox(width: 6),
                                        TagPill(o.badge!, dense: false),
                                      ],
                                    ],
                                  ),
                                  if (o.subtitle != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      o.subtitle!,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (sel)
                              const Icon(
                                Icons.check_circle,
                                size: 18,
                                color: AppColors.primary,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 统一风格的下拉框：外观不变，点击后弹出上面的选择器。
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.width,
    this.optionBuilder,
  });

  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double? width;

  /// 可自定义弹层里每一项的副标题/徽标（不传则只显示文本）。
  final AppPickerOption<T> Function(DropdownMenuItem<T> item)? optionBuilder;

  static String _labelOf(DropdownMenuItem<dynamic> item) {
    final child = item.child;
    if (child is Text) return child.data ?? '${item.value}';
    return '${item.value}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final options = items
        .map((e) => optionBuilder?.call(e) ??
            AppPickerOption(value: e.value as T, label: _labelOf(e)))
        .toList();

    String? current;
    for (final o in options) {
      if (o.value == value) {
        current = o.label;
        break;
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await showAppPicker<T>(
          context,
          title: hint,
          options: options,
          selected: value,
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        width: width,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: t.cardTheme.color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.dividerColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                current ?? hint,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: current == null
                      ? AppColors.textHint
                      : t.textTheme.bodyMedium?.color,
                ),
              ),
            ),
            const Icon(Icons.expand_more, size: 18, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }
}


/// 纵向表单项：标签在上、控件在下。
///
/// 比「标签左、控件右」更紧凑：不会出现拉得过长的输入框，
/// 也便于在宽屏下排成两列。
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: AppColors.textSub),
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[
          const SizedBox(height: 5),
          Text(
            helper!,
            style: const TextStyle(fontSize: 11, color: AppColors.textHint),
          ),
        ],
      ],
    );
  }
}

/// 自适应表单网格：宽度够时两列，窄屏单列。
class FormGrid extends StatelessWidget {
  const FormGrid({
    super.key,
    required this.children,
    this.minItemWidth = 300,
    this.spacing = 16,
    this.maxColumns = 2,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / minItemWidth).floor().clamp(1, maxColumns);
        final w = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: w, child: child),
          ],
        );
      },
    );
  }
}

/// 统一风格的弹窗：紧凑、白底、右上角关闭。
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.width = 520,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final double width;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Dialog(
      backgroundColor: t.cardTheme.color,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Flexible(child: child),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 带标题的分组卡片。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.dividerColor),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                    decoration: TextDecoration.none,
                    backgroundColor: Colors.transparent,
                  ),
                ),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// 左右结构的表单行。
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.child,
    this.width = 92,
  });

  final String label;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSub,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 统计卡片。
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.sub = '',
    this.color = AppColors.primary,
    this.icon,
  });

  final String label;
  final String value;
  final String sub;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSub,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              style: const TextStyle(
                color: AppColors.textSub,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 空状态。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.text,
    this.hint = '',
    this.action,
  });

  final IconData icon;
  final String text;
  final String hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(
              text,
              style: const TextStyle(
                color: AppColors.textSub,
                fontSize: 14,
              ),
            ),
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 小标签。
class TagPill extends StatelessWidget {
  const TagPill(
    this.text, {
    super.key,
    this.color = AppColors.primary,
    this.dense = true,
  });

  final String text;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: dense ? 11 : 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// 近 30 天趋势图（自绘，无第三方图表库）。
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.values, this.height = 120});

  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _TrendPainter(
          values: values,
          color: AppColors.primary,
          gridColor: Theme.of(context).dividerColor,
          labelColor: AppColors.textHint,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.color,
    required this.gridColor,
    required this.labelColor,
  });

  final List<int> values;
  final Color color;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const bottom = 18.0;
    final chartH = size.height - bottom;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chartH / 3 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxV = values.reduce((a, b) => a > b ? a : b);
    final scale = maxV == 0 ? 1.0 : maxV.toDouble();
    final barW = size.width / values.length;

    final barPaint = Paint()..color = color.withValues(alpha: 0.85);
    final capPaint = Paint()..color = color;

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final h = v == 0 ? 0.0 : (v / scale) * (chartH - 6);
      final left = i * barW + barW * 0.2;
      final w = barW * 0.6;
      final rect = Rect.fromLTWH(left, chartH - h, w, h);
      if (h > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          barPaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(left, chartH - h, w, 2),
          capPaint,
        );
      }
    }

    final tp = TextPainter(
      text: TextSpan(
        text: '30 天前',
        style: TextStyle(color: labelColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(0, size.height - 14));

    final tp2 = TextPainter(
      text: TextSpan(
        text: '今天',
        style: TextStyle(color: labelColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(size.width - tp2.width, size.height - 14));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values || old.color != color;
}

/// 顶部提示条（冲突/错误）。
class NoticeBar extends StatelessWidget {
  const NoticeBar({
    super.key,
    required this.text,
    this.color = AppColors.warning,
    this.actionText,
    this.onAction,
    this.onClose,
  });

  final String text;
  final Color color;
  final String? actionText;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
          if (actionText != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionText!),
            ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
