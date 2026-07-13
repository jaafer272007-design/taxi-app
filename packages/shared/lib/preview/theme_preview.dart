import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../theme/app_theme.dart';
import '../widgets/app_avatar.dart';
import '../widgets/app_badge.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_text_field.dart';
import '../widgets/rating_stars.dart';

/// A self-contained screen that renders EVERY design token and base widget.
///
/// It is the re-skin test surface: change `primary` (or any value) in the token
/// files and this whole screen updates with no edits here. Renders both light
/// and dark side by side, RTL.
///
/// [ThemePreviewApp] wires it up as a runnable app; [ThemePreview] is the panel
/// you can embed anywhere a themed [BuildContext] is available.
class ThemePreviewApp extends StatelessWidget {
  const ThemePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Design System',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      // Required so Material widgets (AppBar, TextField) resolve Arabic
      // localizations — without these, the default only supports 'en' and the
      // widgets throw "No MaterialLocalizations found" under locale 'ar'.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Default the whole tree to RTL, Arabic-first.
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _SideBySide(),
    );
  }
}

/// Shows the gallery twice — once under the light theme and once under dark —
/// so a re-skin can be eyeballed in both at a glance. On narrow screens the two
/// panels stack; on wide screens they sit side by side.
class _SideBySide extends StatelessWidget {
  const _SideBySide();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final light = _ThemedPanel(theme: AppTheme.light(), label: 'Light');
        final dark = _ThemedPanel(theme: AppTheme.dark(), label: 'Dark');

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: light),
              const VerticalDivider(width: 1),
              Expanded(child: dark),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: light),
            Expanded(child: dark),
          ],
        );
      },
    );
  }
}

/// Applies [theme] to a subtree and renders the gallery inside it, so every
/// child reads tokens from the theme it is under (the point of the split view).
class _ThemedPanel extends StatelessWidget {
  const _ThemedPanel({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => AppScaffold(
          title: 'نظام التصميم · $label',
          scrollable: true,
          body: const ThemePreview(),
        ),
      ),
    );
  }
}

/// The gallery body. Reads everything from `context` tokens.
class ThemePreview extends StatefulWidget {
  const ThemePreview({super.key});

  @override
  State<ThemePreview> createState() => _ThemePreviewState();
}

class _ThemePreviewState extends State<ThemePreview> {
  final _fieldController = TextEditingController();
  bool _loadingDemo = false;
  double _rating = 4;

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _colorsSection(context),
        SizedBox(height: space.xl2),
        _typographySection(context),
        SizedBox(height: space.xl2),
        _spacingSection(context),
        SizedBox(height: space.xl2),
        _radiiSection(context),
        SizedBox(height: space.xl2),
        _elevationSection(context),
        SizedBox(height: space.xl2),
        _buttonsSection(context),
        SizedBox(height: space.xl2),
        _inputsSection(context),
        SizedBox(height: space.xl2),
        _badgesSection(context),
        SizedBox(height: space.xl2),
        _miscSection(context),
        SizedBox(height: space.xl2),
      ],
    );
  }

  // ── Section scaffolding ────────────────────────────────────────────────
  Widget _section(BuildContext context, String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.text.h2.copyWith(color: context.colors.textPrimary)),
        SizedBox(height: context.space.md),
        child,
      ],
    );
  }

  // ── Colors ─────────────────────────────────────────────────────────────
  Widget _colorsSection(BuildContext context) {
    final c = context.colors;
    final swatches = <_Swatch>[
      _Swatch('primary', c.primary, c.onPrimary),
      _Swatch('primaryPressed', c.primaryPressed, c.onPrimary),
      _Swatch('accent', c.accent, c.onAccent),
      _Swatch('success', c.success, c.onSuccess),
      _Swatch('warning', c.warning, c.onWarning),
      _Swatch('danger', c.danger, c.onDanger),
      _Swatch('info', c.info, c.onInfo),
      _Swatch('surface', c.surface, c.textPrimary),
      _Swatch('surfaceMuted', c.surfaceMuted, c.textPrimary),
      _Swatch('background', c.background, c.textPrimary),
      _Swatch('border', c.border, c.textPrimary),
      _Swatch('borderStrong', c.borderStrong, c.textPrimary),
    ];
    return _section(
      context,
      'الألوان · Colors',
      Wrap(
        spacing: context.space.sm,
        runSpacing: context.space.sm,
        children: swatches.map((s) => _swatchTile(context, s)).toList(),
      ),
    );
  }

  Widget _swatchTile(BuildContext context, _Swatch s) {
    return Container(
      width: 104,
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
        style: context.text.caption.copyWith(color: s.onColor, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ── Typography ─────────────────────────────────────────────────────────
  Widget _typographySection(BuildContext context) {
    final t = context.text;
    Widget row(String name, TextStyle style) => Padding(
          padding: EdgeInsets.only(bottom: context.space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 92,
                child: Text(name, style: t.caption.copyWith(color: context.colors.textMuted)),
              ),
              Expanded(child: Text('رحلة النجف كربلاء', style: style)),
            ],
          ),
        );
    return _section(
      context,
      'الخطوط · Typography (Cairo)',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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

  // ── Spacing ────────────────────────────────────────────────────────────
  Widget _spacingSection(BuildContext context) {
    final space = context.space;
    final steps = <(String, double)>[
      ('xs', space.xs),
      ('sm', space.sm),
      ('md', space.md),
      ('lg', space.lg),
      ('xl', space.xl),
      ('xl2', space.xl2),
      ('xl3', space.xl3),
      ('xl4', space.xl4),
    ];
    return _section(
      context,
      'المسافات · Spacing (4/8)',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: steps.map((e) {
          return Padding(
            padding: EdgeInsets.only(bottom: space.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text('${e.$1} ${e.$2.toInt()}',
                      style: context.text.caption.copyWith(color: context.colors.textMuted)),
                ),
                Container(
                  width: e.$2,
                  height: 16,
                  decoration: BoxDecoration(
                    color: context.colors.primary,
                    borderRadius: context.radii.smAll,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Radii ──────────────────────────────────────────────────────────────
  Widget _radiiSection(BuildContext context) {
    final radii = context.radii;
    final items = <(String, BorderRadius)>[
      ('sm 8', radii.smAll),
      ('md 12', radii.mdAll),
      ('lg 16', radii.lgAll),
      ('pill', radii.pillAll),
    ];
    return _section(
      context,
      'الحواف · Radii',
      Wrap(
        spacing: context.space.md,
        runSpacing: context.space.md,
        children: items.map((e) {
          return Column(
            children: [
              Container(
                width: 72,
                height: 56,
                decoration: BoxDecoration(
                  color: context.colors.surfaceMuted,
                  borderRadius: e.$2,
                  border: Border.all(color: context.colors.borderStrong),
                ),
              ),
              SizedBox(height: context.space.xs),
              Text(e.$1, style: context.text.caption.copyWith(color: context.colors.textMuted)),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Elevation ──────────────────────────────────────────────────────────
  Widget _elevationSection(BuildContext context) {
    return _section(
      context,
      'الظل · Elevation',
      AppCard(
        child: Row(
          children: [
            Icon(AppIcons.car, color: context.colors.primary),
            SizedBox(width: context.space.md),
            Expanded(
              child: Text('بطاقة بظل ناعم', style: context.text.body),
            ),
          ],
        ),
      ),
    );
  }

  // ── Buttons ────────────────────────────────────────────────────────────
  Widget _buttonsSection(BuildContext context) {
    return _section(
      context,
      'الأزرار · Buttons',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            label: 'احجز مقعد',
            icon: AppIcons.seat,
            onPressed: () {},
          ),
          SizedBox(height: context.space.sm),
          AppButton(
            label: 'ثانوي',
            variant: AppButtonVariant.secondary,
            onPressed: () {},
          ),
          SizedBox(height: context.space.sm),
          AppButton(
            label: 'شفاف',
            variant: AppButtonVariant.ghost,
            onPressed: () {},
          ),
          SizedBox(height: context.space.sm),
          AppButton(
            label: 'إلغاء الرحلة',
            variant: AppButtonVariant.danger,
            icon: AppIcons.close,
            onPressed: () {},
          ),
          SizedBox(height: context.space.sm),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: _loadingDemo ? 'جارٍ…' : 'تحميل',
                  loading: _loadingDemo,
                  onPressed: () async {
                    setState(() => _loadingDemo = true);
                    await Future<void>.delayed(const Duration(seconds: 1));
                    if (mounted) setState(() => _loadingDemo = false);
                  },
                ),
              ),
              SizedBox(width: context.space.sm),
              const Expanded(
                child: AppButton(label: 'معطّل', onPressed: null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Inputs ─────────────────────────────────────────────────────────────
  Widget _inputsSection(BuildContext context) {
    return _section(
      context,
      'الحقول · Inputs',
      Column(
        children: [
          AppTextField(
            label: 'رقم الهاتف',
            hint: '7XX XXX XXXX',
            helper: 'نرسل رمز عبر واتساب',
            prefixIcon: AppIcons.phone,
            controller: _fieldController,
            keyboardType: TextInputType.phone,
          ),
          SizedBox(height: context.space.md),
          const AppTextField(
            label: 'الاسم',
            hint: 'الاسم الكامل',
            error: 'الاسم مطلوب',
          ),
        ],
      ),
    );
  }

  // ── Badges & pills ─────────────────────────────────────────────────────
  Widget _badgesSection(BuildContext context) {
    return _section(
      context,
      'الشارات · Badges & Pills',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: context.space.sm,
            runSpacing: context.space.sm,
            children: const [
              AppBadge(label: 'مؤكد', tone: AppBadgeTone.success, icon: AppIcons.success),
              AppBadge(label: 'قيد الانتظار', tone: AppBadgeTone.warning, icon: AppIcons.clock),
              AppBadge(label: 'ملغى', tone: AppBadgeTone.danger, icon: AppIcons.close),
              AppBadge(label: 'معلومة', tone: AppBadgeTone.info, icon: AppIcons.info),
              AppBadge(label: 'عادي', tone: AppBadgeTone.neutral),
            ],
          ),
          SizedBox(height: context.space.md),
          Wrap(
            spacing: context.space.sm,
            runSpacing: context.space.sm,
            children: const [
              AppPill(label: 'النجف → كربلاء', tone: AppBadgeTone.info, icon: AppIcons.route),
              AppPill(label: '3 مقاعد', tone: AppBadgeTone.success, icon: AppIcons.seat),
            ],
          ),
        ],
      ),
    );
  }

  // ── Avatar + rating ────────────────────────────────────────────────────
  Widget _miscSection(BuildContext context) {
    return _section(
      context,
      'أخرى · Avatar & Rating',
      AppCard(
        child: Row(
          children: [
            const AppAvatar(name: 'علي حسن'),
            SizedBox(width: context.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('علي حسن', style: context.text.title),
                  SizedBox(height: context.space.xs),
                  RatingStars(
                    value: _rating,
                    onRate: (v) => setState(() => _rating = v.toDouble()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch {
  const _Swatch(this.name, this.color, this.onColor);
  final String name;
  final Color color;
  final Color onColor;
}
