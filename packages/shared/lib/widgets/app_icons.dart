import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Single point of contact with the icon package.
///
/// Every icon used anywhere in the apps is named here. If the `lucide_icons`
/// version is bumped (or the whole set is swapped for another vector pack),
/// THIS is the only file that changes — screens reference `AppIcons.car`, never
/// `LucideIcons.car` directly. No emoji anywhere in the UI.
abstract final class AppIcons {
  // Navigation / chrome
  static const IconData back = LucideIcons.arrowRight; // RTL: "back" points right
  static const IconData forward = LucideIcons.arrowLeft;
  static const IconData close = LucideIcons.x;
  static const IconData menu = LucideIcons.menu;
  static const IconData more = LucideIcons.moreHorizontal;
  static const IconData check = LucideIcons.check;
  static const IconData chevronLeft = LucideIcons.chevronLeft;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData plus = LucideIcons.plus;
  static const IconData minus = LucideIcons.minus;

  // Domain
  static const IconData car = LucideIcons.car;
  static const IconData seat = LucideIcons.armchair;
  static const IconData mapPin = LucideIcons.mapPin;
  static const IconData map = LucideIcons.map;

  /// Hand-off to a maps app for turn-by-turn — the arrow, not the pin: this is
  /// "take me there", while [mapPin] is "it is here".
  static const IconData navigation = LucideIcons.navigation;
  static const IconData route = LucideIcons.route;
  static const IconData swap = LucideIcons.arrowRightLeft;
  static const IconData clock = LucideIcons.clock;
  static const IconData calendar = LucideIcons.calendar;
  static const IconData phone = LucideIcons.phone;

  /// WhatsApp, drawn as a generic chat bubble ON PURPOSE.
  ///
  /// We do not ship WhatsApp's brand mark: reproducing a logo we have no
  /// licensed asset for — or worse, re-drawing an approximation — breaks the
  /// brand's usage guidelines and looks counterfeit. The action always carries
  /// the word «واتساب» beside this icon, which is what actually identifies it.
  static const IconData chat = LucideIcons.messageCircle;
  static const IconData user = LucideIcons.user;
  static const IconData users = LucideIcons.users;
  static const IconData wallet = LucideIcons.wallet;
  static const IconData cash = LucideIcons.banknote;
  static const IconData star = LucideIcons.star;
  static const IconData document = LucideIcons.fileText;
  static const IconData upload = LucideIcons.upload;
  static const IconData plusCircle = LucideIcons.plusCircle;

  // Status / feedback
  static const IconData success = LucideIcons.checkCircle2;
  static const IconData warning = LucideIcons.alertTriangle;
  static const IconData danger = LucideIcons.alertCircle;
  static const IconData info = LucideIcons.info;
  static const IconData bell = LucideIcons.bell;

  // Inputs
  static const IconData search = LucideIcons.search;
  static const IconData eye = LucideIcons.eye;
  static const IconData eyeOff = LucideIcons.eyeOff;
}
