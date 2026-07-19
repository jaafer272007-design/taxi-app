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

final Map<String, String> _cityArByKey = {
  for (final c in kIraqiCities) c.key: c.ar,
};

/// Arabic display name for a stored city key; falls back to the key itself so an
/// unknown/legacy value never renders blank.
String cityArName(String key) => _cityArByKey[key] ?? key;
