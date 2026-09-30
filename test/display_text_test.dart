import 'package:easyvpn/core/util/display_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decorative provider names become readable', () {
    expect(plainName('🇹🇷𝕋ü𝕣𝕜𝕚𝕪𝕖2🎮🇮🇷'), '🇹🇷Türkiye2🎮🇮🇷');
    expect(plainName('🇺🇸𝕌𝕊𝔸 AI🇮🇷'), '🇺🇸USA AI🇮🇷');
    expect(plainName('🇩🇪𝔾𝕖𝕣𝕞𝕒𝕟𝕪7'), '🇩🇪Germany7');
    expect(plainName('𝐔𝐒𝐀 ᴀɪ'), 'USA AI');
    expect(plainName('ℂℍℕℙℚℝℤ'), 'CHNPQRZ');
    expect(plainName('plain name'), 'plain name');
  });
}
