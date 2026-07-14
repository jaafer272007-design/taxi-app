import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../widgets/driver_banner.dart';
import 'driver_controller.dart';

/// Vehicle details form (make/model/plate/color/seats). On save the gate advances
/// to the documents step.
class VehicleFormScreen extends StatefulWidget {
  const VehicleFormScreen({super.key});

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _plate = TextEditingController();
  final _color = TextEditingController();
  final _seats = TextEditingController();

  String? _makeErr, _modelErr, _plateErr, _colorErr, _seatsErr;

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _plate.dispose();
    _color.dispose();
    _seats.dispose();
    super.dispose();
  }

  String? _required(String v) => v.trim().isEmpty ? 'مطلوب' : null;

  String? _validateSeats(String v) {
    final n = int.tryParse(v.trim());
    if (n == null) return 'أدخل رقماً';
    if (n < 1) return 'مقعد واحد على الأقل';
    if (n > 50) return 'عدد غير منطقي';
    return null;
  }

  Future<void> _submit(DriverController c) async {
    final makeErr = _required(_make.text);
    final modelErr = _required(_model.text);
    final plateErr = _required(_plate.text);
    final colorErr = _required(_color.text);
    final seatsErr = _validateSeats(_seats.text);
    setState(() {
      _makeErr = makeErr;
      _modelErr = modelErr;
      _plateErr = plateErr;
      _colorErr = colorErr;
      _seatsErr = seatsErr;
    });
    if ([makeErr, modelErr, plateErr, colorErr, seatsErr].any((e) => e != null)) {
      return;
    }
    await c.saveVehicle(
      make: _make.text.trim(),
      model: _model.text.trim(),
      plate: _plate.text.trim(),
      color: _color.text.trim(),
      seats: int.parse(_seats.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverController>();
    final space = context.space;

    return AppScaffold(
      title: 'مركبتك',
      scrollable: true,
      bottomBar: AppButton(
        label: 'حفظ ومتابعة',
        icon: AppIcons.check,
        loading: c.busy,
        onPressed: c.busy ? null : () => _submit(c),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: space.md),
          Text('أدخل بيانات مركبتك',
              style: context.text.h2.copyWith(color: context.colors.textPrimary)),
          SizedBox(height: space.xs),
          Text('تظهر للركّاب عند الحجز.',
              style: context.text.body.copyWith(color: context.colors.textSecondary)),
          SizedBox(height: space.xl),
          AppTextField(
            label: 'النوع',
            hint: 'مثال: Toyota',
            error: _makeErr,
            controller: _make,
            prefixIcon: AppIcons.car,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clear(() => _makeErr = null),
          ),
          SizedBox(height: space.lg),
          AppTextField(
            label: 'الموديل',
            hint: 'مثال: Corolla',
            error: _modelErr,
            controller: _model,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clear(() => _modelErr = null),
          ),
          SizedBox(height: space.lg),
          AppTextField(
            label: 'رقم اللوحة',
            hint: 'مثال: ١٢٣٤٥ بغداد',
            error: _plateErr,
            controller: _plate,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clear(() => _plateErr = null),
          ),
          SizedBox(height: space.lg),
          AppTextField(
            label: 'اللون',
            hint: 'مثال: أبيض',
            error: _colorErr,
            controller: _color,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clear(() => _colorErr = null),
          ),
          SizedBox(height: space.lg),
          AppTextField(
            label: 'عدد المقاعد',
            hint: 'مثال: 4',
            helper: 'عدد مقاعد الركّاب في سيارتك.',
            error: _seatsErr,
            controller: _seats,
            prefixIcon: AppIcons.seat,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => _clear(() => _seatsErr = null),
          ),
          if (c.actionError != null) ...[
            SizedBox(height: space.lg),
            DriverBanner(message: c.actionError!, tone: BannerTone.danger),
          ],
        ],
      ),
    );
  }

  void _clear(VoidCallback setter) {
    setState(setter);
  }
}
