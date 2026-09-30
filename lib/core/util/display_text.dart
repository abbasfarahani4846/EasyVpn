/// Display helpers for provider-decorated node names.
///
/// Subscriptions often use "fancy" Unicode (𝕋ü𝕣𝕜𝕚𝕪𝕖, 𝐔𝐒𝐀, ᴀɪ) that many desktop
/// fonts (notably on Windows) cannot draw, so names showed boxes or odd
/// glyphs. We map the Mathematical Alphanumeric Symbols block, letter-like
/// symbols and small capitals back to plain letters. Flag emoji are kept and
/// drawn by the bundled "FlagEmoji" font (Twemoji country flags).
library;

const _letterlike = <int, String>{
  0x2102: 'C', 0x210A: 'g', 0x210B: 'H', 0x210C: 'H', 0x210D: 'H', 0x210E: 'h',
  0x2110: 'I', 0x2111: 'I', 0x2112: 'L', 0x2115: 'N', 0x2119: 'P', 0x211A: 'Q',
  0x211B: 'R', 0x211C: 'R', 0x211D: 'R', 0x2124: 'Z', 0x2128: 'Z', 0x212C: 'B',
  0x212D: 'C', 0x212F: 'e', 0x2130: 'E', 0x2131: 'F', 0x2133: 'M', 0x2134: 'o',
  // small capitals (IPA / phonetic extensions)
  0x1D00: 'A', 0x0299: 'B', 0x1D04: 'C', 0x1D05: 'D', 0x1D07: 'E', 0xA730: 'F',
  0x0262: 'G', 0x029C: 'H', 0x026A: 'I', 0x1D0A: 'J', 0x1D0B: 'K', 0x029F: 'L',
  0x1D0D: 'M', 0x0274: 'N', 0x1D0F: 'O', 0x1D18: 'P', 0x0280: 'R', 0xA731: 'S',
  0x1D1B: 'T', 0x1D1C: 'U', 0x1D20: 'V', 0x1D21: 'W', 0x028F: 'Y', 0x1D22: 'Z',
};

/// Returns [s] with decorative letters replaced by plain ASCII.
String plainName(String s) {
  var changed = false;
  final out = StringBuffer();
  for (final r in s.runes) {
    String? rep;
    if (r >= 0x1D400 && r <= 0x1D6A3) {
      final i = (r - 0x1D400) % 52;
      rep = String.fromCharCode(i < 26 ? 0x41 + i : 0x61 + i - 26);
    } else if (r >= 0x1D7CE && r <= 0x1D7FF) {
      rep = String.fromCharCode(0x30 + (r - 0x1D7CE) % 10);
    } else if (r >= 0xFF01 && r <= 0xFF5E) {
      rep = String.fromCharCode(r - 0xFEE0); // full-width ASCII
    } else {
      rep = _letterlike[r];
    }
    if (rep != null) {
      changed = true;
      out.write(rep);
    } else {
      out.writeCharCode(r);
    }
  }
  return changed ? out.toString() : s;
}
