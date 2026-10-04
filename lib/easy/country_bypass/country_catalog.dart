enum RuleRepo {
  meta(
    raw: 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo',
    mirror: 'https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@meta/geo',
  ),
  iran(
    raw:
        'https://raw.githubusercontent.com/Chocolate4U/Iran-clash-rules/release',
    mirror: 'https://cdn.jsdelivr.net/gh/Chocolate4U/Iran-clash-rules@release',
  );

  final String raw;
  final String mirror;

  const RuleRepo({required this.raw, required this.mirror});
}

class RuleFile {
  final RuleRepo repo;
  final String path;

  const RuleFile(this.repo, this.path);

  String url({required bool mirror}) =>
      '${mirror ? repo.mirror : repo.raw}/$path';
}

class CountrySource {
  final String code;
  final String nameEn;
  final String nameFa;
  final RuleFile ip;
  final RuleFile? domain;

  const CountrySource({
    required this.code,
    required this.nameEn,
    required this.nameFa,
    required this.ip,
    this.domain,
  });

  String get flag => String.fromCharCodes(
    code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41),
  );

  String get ipProvider => 'easy-$code-ip';
  String get domainProvider => 'easy-$code-domain';
}

/// IP ranges come from MetaCubeX/meta-rules-dat (rebuilt daily from MaxMind
/// and other geo data); domain lists exist only where a maintained one does.
class CountryCatalog {
  const CountryCatalog._();

  static CountrySource _ipOnly(String code, String en, String fa) =>
      CountrySource(
        code: code,
        nameEn: en,
        nameFa: fa,
        ip: RuleFile(RuleRepo.meta, 'geoip/$code.mrs'),
      );

  static final List<CountrySource> all = List.unmodifiable([
    const CountrySource(
      code: 'ir',
      nameEn: 'Iran',
      nameFa: 'ایران',
      ip: RuleFile(RuleRepo.iran, 'ircidr.mrs'),
      domain: RuleFile(RuleRepo.iran, 'ir.mrs'),
    ),
    const CountrySource(
      code: 'cn',
      nameEn: 'China',
      nameFa: 'چین',
      ip: RuleFile(RuleRepo.meta, 'geoip/cn.mrs'),
      domain: RuleFile(RuleRepo.meta, 'geosite/cn.mrs'),
    ),
    const CountrySource(
      code: 'ru',
      nameEn: 'Russia',
      nameFa: 'روسیه',
      ip: RuleFile(RuleRepo.meta, 'geoip/ru.mrs'),
      domain: RuleFile(RuleRepo.meta, 'geosite/category-ru.mrs'),
    ),
    _ipOnly('tr', 'Turkey', 'ترکیه'),
    _ipOnly('ae', 'United Arab Emirates', 'امارات'),
    _ipOnly('iq', 'Iraq', 'عراق'),
    _ipOnly('af', 'Afghanistan', 'افغانستان'),
    _ipOnly('pk', 'Pakistan', 'پاکستان'),
    _ipOnly('in', 'India', 'هند'),
    _ipOnly('kz', 'Kazakhstan', 'قزاقستان'),
    _ipOnly('ua', 'Ukraine', 'اوکراین'),
    _ipOnly('by', 'Belarus', 'بلاروس'),
    _ipOnly('vn', 'Vietnam', 'ویتنام'),
    _ipOnly('id', 'Indonesia', 'اندونزی'),
    _ipOnly('th', 'Thailand', 'تایلند'),
    _ipOnly('eg', 'Egypt', 'مصر'),
    _ipOnly('sa', 'Saudi Arabia', 'عربستان'),
    _ipOnly('sy', 'Syria', 'سوریه'),
    _ipOnly('lb', 'Lebanon', 'لبنان'),
    _ipOnly('jo', 'Jordan', 'اردن'),
    _ipOnly('kw', 'Kuwait', 'کویت'),
    _ipOnly('qa', 'Qatar', 'قطر'),
    _ipOnly('az', 'Azerbaijan', 'آذربایجان'),
    _ipOnly('am', 'Armenia', 'ارمنستان'),
    _ipOnly('ge', 'Georgia', 'گرجستان'),
    _ipOnly('uz', 'Uzbekistan', 'ازبکستان'),
    _ipOnly('tm', 'Turkmenistan', 'ترکمنستان'),
    _ipOnly('kg', 'Kyrgyzstan', 'قرقیزستان'),
    _ipOnly('tj', 'Tajikistan', 'تاجیکستان'),
    _ipOnly('bd', 'Bangladesh', 'بنگلادش'),
    _ipOnly('lk', 'Sri Lanka', 'سری‌لانکا'),
    _ipOnly('hk', 'Hong Kong', 'هنگ‌کنگ'),
    _ipOnly('tw', 'Taiwan', 'تایوان'),
    _ipOnly('jp', 'Japan', 'ژاپن'),
    _ipOnly('kr', 'South Korea', 'کره جنوبی'),
    _ipOnly('sg', 'Singapore', 'سنگاپور'),
    _ipOnly('my', 'Malaysia', 'مالزی'),
    _ipOnly('de', 'Germany', 'آلمان'),
    _ipOnly('fr', 'France', 'فرانسه'),
    _ipOnly('gb', 'United Kingdom', 'بریتانیا'),
    _ipOnly('us', 'United States', 'آمریکا'),
    _ipOnly('ca', 'Canada', 'کانادا'),
    _ipOnly('au', 'Australia', 'استرالیا'),
    _ipOnly('br', 'Brazil', 'برزیل'),
    _ipOnly('ar', 'Argentina', 'آرژانتین'),
    _ipOnly('mx', 'Mexico', 'مکزیک'),
    _ipOnly('za', 'South Africa', 'آفریقای جنوبی'),
    _ipOnly('ma', 'Morocco', 'مراکش'),
    _ipOnly('dz', 'Algeria', 'الجزایر'),
    _ipOnly('tn', 'Tunisia', 'تونس'),
  ]);

  static CountrySource? byCode(String? code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    return null;
  }
}
