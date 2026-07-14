import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared/shared.dart';

import '../home/driver_home_shell.dart';
import 'become_driver_screen.dart';
import 'documents_screen.dart';
import 'driver_controller.dart';
import 'driver_models.dart';
import 'pending_review_screen.dart';
import 'vehicle_form_screen.dart';

/// The authenticated driver's home gate: loads the driver profile, then renders
/// the right step — become-a-driver → vehicle → documents → pending review, or
/// the post-a-trip home once APPROVED.
class DriverGate extends StatefulWidget {
  const DriverGate({super.key});

  @override
  State<DriverGate> createState() => _DriverGateState();
}

class _DriverGateState extends State<DriverGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DriverController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverController>();
    return switch (c.loadState) {
      DriverLoad.loading => const _Loading(),
      DriverLoad.error => _ErrorView(
          message: c.loadError ?? 'حدث خطأ. حاول مرة أخرى.',
          onRetry: c.load,
        ),
      DriverLoad.ready => _forProfile(c),
    };
  }

  Widget _forProfile(DriverController c) {
    final p = c.profile;
    if (p == null) return const BecomeDriverScreen();
    switch (p.status) {
      case DriverStatus.approved:
        return DriverHomeShell(vehicleSeats: p.vehicle?.seats ?? 1);
      case DriverStatus.rejected:
      case DriverStatus.suspended:
        return const PendingReviewScreen();
      case DriverStatus.pending:
      case DriverStatus.unknown:
        if (p.vehicle == null) return const VehicleFormScreen();
        if (!p.hasAllDocuments) return const DocumentsScreen();
        return const PendingReviewScreen();
    }
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Center(
        child: CircularProgressIndicator(color: context.colors.primary),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final space = context.space;
    return AppScaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: space.xl4 + space.xl2,
                height: space.xl4 + space.xl2,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.warning, color: colors.danger, size: space.xl2),
              ),
              SizedBox(height: space.lg),
              Text(message,
                  style: context.text.title, textAlign: TextAlign.center),
              SizedBox(height: space.xl),
              AppButton(label: 'إعادة المحاولة', expand: false, onPressed: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}
