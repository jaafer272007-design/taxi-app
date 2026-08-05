import 'package:flutter/material.dart';

import '../format/numerals.dart';
import '../theme/app_theme.dart';
import '../widgets/app_avatar.dart';
import '../widgets/app_badge.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/floating_pill_nav.dart';
import '../widgets/rating_stars.dart';
import '../widgets/route_rail.dart';
import '../widgets/seat_glyphs.dart';

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
      // accent is a FILL token — its label is drawn in onAccent (dark ink),
      // because the saffron itself is never legible as text on a page.
      _SwatchLabel('accent (fill)', c.accent, c.onAccent),
      // accentText is the saffron when it must be ink; shown on surface.
      _SwatchLabel('accentText', c.surface, c.accentText),
      _SwatchLabel('success', c.success, c.onSuccess),
      _SwatchLabel('warning', c.warning, c.onWarning),
      _SwatchLabel('danger', c.danger, c.onDanger),
      _SwatchLabel('info', c.info, c.onInfo),
      // Tonal backgrounds, each labelled in the ink actually drawn on it.
      _SwatchLabel('primaryTonal', c.primaryTonal, c.primary),
      _SwatchLabel('successTonal', c.successTonal, c.success),
      _SwatchLabel('warningTonal', c.warningTonal, c.warning),
      _SwatchLabel('dangerTonal', c.dangerTonal, c.danger),
      _SwatchLabel('infoTonal', c.infoTonal, c.info),
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
        borderRadius: context.radii.fieldLgAll,
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
          SizedBox(height: context.space.md),
          // The locked numeral rule, shown side by side.
          Text('عرض · Arabic-Indic (prices, times, counts)',
              style: t.caption.copyWith(color: context.colors.textMuted)),
          SizedBox(height: context.space.xs),
          Text(
            '${formatPrice(12000)} · ${formatClock(7, 30)} · '
            '${formatCount(3)} مقاعد · ${formatRating(4.8)}',
            style: t.title.tabular.copyWith(color: context.colors.textPrimary),
          ),
          SizedBox(height: context.space.sm),
          Text('إدخال · Western (phone & OTP entry only)',
              style: t.caption.copyWith(color: context.colors.textMuted)),
          SizedBox(height: context.space.xs),
          Text('+964 771 234 5678 · 419254',
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
              AppButton(
                  label: 'إلغاء الرحلة (لطيف)',
                  variant: AppButtonVariant.dangerTonal,
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
                  AppPill(label: '٣ مقاعد', tone: AppBadgeTone.success, icon: AppIcons.seat),
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


/// The Masar signature components introduced in PR 2: the route rail, seats
/// drawn as seats, and the floating pill nav.
class MasarComponentsGallery extends StatelessWidget {
  const MasarComponentsGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final colors = context.colors;
    final text = context.text;

    Widget cityBlock(String label, String city) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: text.caption.copyWith(color: colors.textMuted)),
            Text(city, style: text.title),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GallerySection(
          title: 'قضيب المسار · Route rail',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                child: RouteRail(
                  divided: true,
                  origin: cityBlock('من', 'النجف'),
                  destination: cityBlock('إلى', 'كربلاء'),
                ),
              ),
              SizedBox(height: space.md),
              AppCard(
                child: RouteRail(
                  variant: RouteRailVariant.compact,
                  origin: Text('النجف', style: text.bodyStrong),
                  destination: Text('كربلاء', style: text.bodyStrong),
                ),
              ),
              SizedBox(height: space.md),
              // On a primary field both endpoints use the on-primary ink and
              // are told apart by shape (filled dot vs stroked ring).
              Container(
                padding: EdgeInsets.all(space.lg),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: context.radii.cardAll,
                ),
                child: RouteRail(
                  onPrimaryField: true,
                  origin: Text('النجف',
                      style: text.title.copyWith(color: colors.onPrimary)),
                  destination: Text('كربلاء',
                      style: text.title.copyWith(color: colors.onPrimary)),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: space.xl2),
        GallerySection(
          title: 'المقاعد · Seat glyphs',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final free in [4, 3, 2, 1, 0]) ...[
                SeatAvailability(total: 4, available: free),
                SizedBox(height: space.sm),
              ],
              SizedBox(height: space.xs),
              Text('مضغوط · compact',
                  style: text.caption.copyWith(color: colors.textMuted)),
              SizedBox(height: space.xs),
              const SeatGlyphs(total: 5, available: 2, compact: true),
            ],
          ),
        ),
        SizedBox(height: space.xl2),
        GallerySection(
          title: 'شريط التنقّل العائم · Floating pill nav',
          child: Column(
            children: [
              // Three tabs: the roomy inset.
              FloatingPillNav(
                currentIndex: 0,
                onSelect: (_) {},
                items: const [
                  FloatingPillNavItem(icon: AppIcons.search, label: 'ابحث'),
                  FloatingPillNavItem(icon: AppIcons.seat, label: 'حجوزاتي'),
                  FloatingPillNavItem(icon: AppIcons.user, label: 'حسابي'),
                ],
              ),
              // The rider's four, with an unread badge on an UNSELECTED tab —
              // the state that has to catch the eye from across the screen.
              FloatingPillNav(
                currentIndex: 0,
                onSelect: (_) {},
                items: const [
                  FloatingPillNavItem(icon: AppIcons.search, label: 'ابحث'),
                  FloatingPillNavItem(icon: AppIcons.seat, label: 'حجوزاتي'),
                  FloatingPillNavItem(
                      icon: AppIcons.bell, label: 'إشعارات', badgeCount: 3),
                  FloatingPillNavItem(icon: AppIcons.user, label: 'حسابي'),
                ],
              ),
              // The driver's five — the pill's documented maximum, at the
              // tightest inset, with the badge on the SELECTED tab (danger on
              // primaryTonal) and its two-glyph «+٩» overflow form.
              FloatingPillNav(
                currentIndex: 3,
                onSelect: (_) {},
                items: const [
                  FloatingPillNavItem(icon: AppIcons.plusCircle, label: 'انشر'),
                  FloatingPillNavItem(icon: AppIcons.route, label: 'رحلاتي'),
                  FloatingPillNavItem(icon: AppIcons.wallet, label: 'أرباحي'),
                  FloatingPillNavItem(
                      icon: AppIcons.bell, label: 'إشعارات', badgeCount: 12),
                  FloatingPillNavItem(icon: AppIcons.user, label: 'حسابي'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
