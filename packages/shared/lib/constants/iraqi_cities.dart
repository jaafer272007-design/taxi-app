/// One canonical hub city per Iraqi governorate (18 total). [key] is the value
/// stored server-side in `Corridor.originCity` / `destCity`; [ar] is the Arabic
/// (RTL) display name. Kept in sync with `services/api/src/corridor/cities.ts`.
class IraqiCity {
  const IraqiCity({required this.key, required this.ar});

  final String key;
  final String ar;
}

/// The canonical list, in a stable display order (prominent hubs first).
const List<IraqiCity> kIraqiCities = [
  IraqiCity(key: 'Baghdad', ar: 'بغداد'),
  IraqiCity(key: 'Basra', ar: 'البصرة'),
  IraqiCity(key: 'Najaf', ar: 'النجف'),
  IraqiCity(key: 'Karbala', ar: 'كربلاء'),
  IraqiCity(key: 'Erbil', ar: 'أربيل'),
  IraqiCity(key: 'Mosul', ar: 'الموصل'),
  IraqiCity(key: 'Kirkuk', ar: 'كركوك'),
  IraqiCity(key: 'Sulaymaniyah', ar: 'السليمانية'),
  IraqiCity(key: 'Duhok', ar: 'دهوك'),
  IraqiCity(key: 'Ramadi', ar: 'الرمادي'),
  IraqiCity(key: 'Baqubah', ar: 'بعقوبة'),
  IraqiCity(key: 'Kut', ar: 'الكوت'),
  IraqiCity(key: 'Amarah', ar: 'العمارة'),
  IraqiCity(key: 'Nasiriyah', ar: 'الناصرية'),
  IraqiCity(key: 'Samawah', ar: 'السماوة'),
  IraqiCity(key: 'Diwaniyah', ar: 'الديوانية'),
  IraqiCity(key: 'Hilla', ar: 'الحلة'),
  IraqiCity(key: 'Tikrit', ar: 'تكريت'),
];

/// The city pair both apps open on before the user picks anything.
///
/// Once every ordered pair of the 18 governorates has a corridor, "the first
/// corridor the API returned" is alphabetical accident — it would default both
/// apps to العمارة→بغداد. The opening pair is a product decision, so it is
/// stated here rather than emerging from list order: النجف↔كربلاء is the
/// flagship route and the busiest in the pilot.
///
/// Both controllers fall back to the first served corridor if this pair is
/// missing or deactivated, so the default can never strand the form.
const String kDefaultOriginCity = 'Najaf';
const String kDefaultDestCity = 'Karbala';

final Map<String, String> _cityArByKey = {
  for (final c in kIraqiCities) c.key: c.ar,
};

/// Arabic display name for a stored city key; falls back to the key itself so an
/// unknown/legacy value never renders blank.
String cityArName(String key) => _cityArByKey[key] ?? key;
