import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_avatar.dart';
import '../widgets/app_badge.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/rating_stars.dart';

/// Reusable, self-contained "gallery" widgets that render slices of the design
/// system from tokens only. Used both by the on-device Theme Preview and by the
/// golden tests (which snapshot each gallery as a separate image). Because they
/// read everything through `context.*`, a token change re-skins them with no
/// edits here — which is exactly what the golden regression guard verifies.

/// A titled section wrapper shared by the galleries.
class GallerySection extends StatelessWidget {
  const GallerySection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: context.text.h2.copyWith(color: context.colors.textPrimary)),
        SizedBox(height: context.space.md),
        child,
      ],
    );
  }
}

/// Every color token as a labelled swatch.
class ColorTokensGallery extends StatelessWidget {
  const ColorTokensGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final swatches = <_SwatchLabel>[
      _SwatchLabel('primary', c.primary, c.onPrimary),
      _SwatchLabel('primaryPressed', c.primaryPressed, c.onPrimary),
      _SwatchLabel('accent', c.accent, c.onAccent),
      _SwatchLabel('success', c.success, c.onSuccess),
      _SwatchLabel('warning', c.warning, c.onWarning),
      _SwatchLabel('danger', c.danger, c.onDanger),
      _SwatchLabel('info', c.info, c.onInfo),
      _SwatchLabel('textPrimary', c.textPrimary, c.surface),
      _SwatchLabel('textSecondary', c.textSecondary, c.surface),
      _SwatchLabel('textMuted', c.textMuted, c.surface),
      _SwatchLabel('surface', c.surface, c.textPrimary),
      _SwatchLabel('surfaceMuted', c.surfaceMuted, c.textPrimary),
      _SwatchLabel('background', c.background, c.textPrimary),
      _SwatchLabel('border', c.border, c.textPrimary),
      _SwatchLabel('borderStrong', c.borderStrong, c.textPrimary),
    ];
    return GallerySection(
      title: 'الألوان · Color tokens',
      child: Wrap(
        spacing: context.space.sm,
        runSpacing: context.space.sm,
        children: [for (final s in swatches) _swatch(context, s)],
      ),
    );
  }

  Widget _swatch(BuildContext context, _SwatchLabel s) {
    return Container(
      width: 122,
      height: 72,
      padding: EdgeInsets.all(context.space.sm),
      alignment: Alignment.bottomRight,
      decoration: BoxDecoration(
        color: s.color,
        borderRadius: context.radii.mdAll,
        border: Border.all(color: context.colors.border),
      ),
      child: Text(
        s.name,
        style: context.text.caption
            .copyWith(color: s.onColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SwatchLabel {
  const _SwatchLabel(this.name, this.color, this.onColor);
  final String name;
  final Color color;
  final Color onColor;
}

/// The full type scale plus the tabular-figures sample.
class TypeScaleGallery extends StatelessWidget {
  const TypeScaleGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    Widget row(String name, TextStyle style) => Padding(
          padding: EdgeInsets.only(bottom: context.space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 96,
                child: Text(name,
                    style: t.caption.copyWith(color: context.colors.textMuted)),
              ),
              Expanded(child: Text('رحلة النجف كربلاء', style: style)),
            ],
          ),
        );
    return GallerySection(
      title: 'الخطوط · Type scale (Cairo)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          row('display', t.display),
          row('h1', t.h1),
          row('h2', t.h2),
          row('title', t.title),
          row('body', t.body),
          row('bodyStrong', t.bodyStrong),
          row('label', t.label),
          row('caption', t.caption),
          SizedBox(height: context.space.sm),
          Text('أرقام tabular · Prices & times',
              style: t.caption.copyWith(color: context.colors.textMuted)),
          SizedBox(height: context.space.xs),
          Text('12,000 IQD · 07:30 · +9647701234567',
              style: t.title.tabular.copyWith(color: context.colors.textPrimary)),
        ],
      ),
    );
  }
}

/// Every base widget in one column: buttons (all variants + loading + disabled),
/// card, text fields (label/helper/error), badges & pills, avatar, rating stars.
class WidgetShowcaseGallery extends StatelessWidget {
  const WidgetShowcaseGallery({super.key, this.buttonLoading = true});

  /// Render the loading button in its spinner state (goldens want to show it).
  final bool buttonLoading;

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GallerySection(
          title: 'الأزرار · Buttons',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppButton(label: 'احجز مقعد', icon: AppIcons.seat, onPressed: () {}),
              SizedBox(height: space.sm),
              AppButton(
                  label: 'ثانوي',
                  variant: AppButtonVariant.secondary,
                  onPressed: () {}),
              SizedBox(height: space.sm),
              AppButton(
                  label: 'شفاف',
                  variant: AppButtonVariant.ghost,
                  onPressed: () {}),
              SizedBox(height: space.sm),
              AppButton(
                  label: 'إلغاء الرحلة',
                  variant: AppButtonVariant.danger,
                  icon: AppIcons.close,
                  onPressed: () {}),
              SizedBox(height: space.sm),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: buttonLoading ? 'جارٍ…' : 'تحميل',
                      loading: buttonLoading,
                      onPressed: () {},
                    ),
                  ),
                  SizedBox(width: space.sm),
                  const Expanded(
                    child: AppButton(label: 'معطّل', onPressed: null),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: space.xl2),
        GallerySection(
          title: 'البطاقة · Card',
          child: AppCard(
            child: Row(
              children: [
                Icon(AppIcons.car, color: context.colors.primary),
                SizedBox(width: space.md),
                Expanded(child: Text('بطاقة بظل ناعم', style: context.text.body)),
              ],
            ),
          ),
        ),
        SizedBox(height: space.xl2),
        GallerySection(
          title: 'الحقول · Inputs',
          child: Column(
            children: [
              const AppTextField(
                label: 'رقم الهاتف',
                hint: '7XX XXX XXXX',
                helper: 'نرسل رمز عبر واتساب',
                prefixIcon: AppIcons.phone,
              ),
              SizedBox(height: space.md),
              const AppTextField(
                label: 'الاسم',
                hint: 'الاسم الكامل',
                error: 'الاسم مطلوب',
              ),
            ],
          ),
        ),
        SizedBox(height: space.xl2),
        GallerySection(
          title: 'الشارات · Badges & Pills',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: space.sm,
                runSpacing: space.sm,
                children: const [
                  AppBadge(label: 'مؤكد', tone: AppBadgeTone.success, icon: AppIcons.success),
                  AppBadge(label: 'قيد الانتظار', tone: AppBadgeTone.warning, icon: AppIcons.clock),
                  AppBadge(label: 'ملغى', tone: AppBadgeTone.danger, icon: AppIcons.close),
                  AppBadge(label: 'معلومة', tone: AppBadgeTone.info, icon: AppIcons.info),
                  AppBadge(label: 'عادي', tone: AppBadgeTone.neutral),
                ],
              ),
              SizedBox(height: space.md),
              Wrap(
                spacing: space.sm,
                runSpacing: space.sm,
                children: const [
                  AppPill(label: 'النجف → كربلاء', tone: AppBadgeTone.info, icon: AppIcons.route),
                  AppPill(label: '3 مقاعد', tone: AppBadgeTone.success, icon: AppIcons.seat),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: space.xl2),
        GallerySection(
          title: 'أخرى · Avatar & Rating',
          child: AppCard(
            child: Row(
              children: [
                const AppAvatar(name: 'علي حسن'),
                SizedBox(width: space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('علي حسن', style: context.text.title),
                      SizedBox(height: space.xs),
                      const RatingStars(value: 4.5),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
