/// High schools in the Tri-Valley (Dublin, Pleasanton, Livermore, San Ramon,
/// Danville), offered as the choices for the sign-up `school` question.
/// Anything not listed is typed in under "Other". The stored value
/// (`profiles.details.school`) is the school's [TriValleySchool.name], or the
/// typed name for "Other".
class TriValleySchool {
  const TriValleySchool(this.name, this.city, {this.aliases = const []});

  final String name;
  final String city;

  /// Other ways people write the name (lowercase), so older typed answers
  /// like "Cal High" or "DVHS" count toward the right school.
  final List<String> aliases;
}

/// Alphabetical, with public, private, and charter schools together.
const triValleySchools = <TriValleySchool>[
  TriValleySchool(
    'Amador Valley High School',
    'Pleasanton',
    aliases: ['avhs', 'amador'],
  ),
  TriValleySchool(
    'California High School',
    'San Ramon',
    aliases: ['cal high', 'cal'],
  ),
  TriValleySchool('Del Amigo High School', 'Danville'),
  TriValleySchool('Del Valle High School', 'Livermore'),
  TriValleySchool(
    'Dougherty Valley High School',
    'San Ramon',
    aliases: ['dvhs', 'dougherty'],
  ),
  TriValleySchool('Dublin High School', 'Dublin', aliases: ['dhs']),
  TriValleySchool('Emerald High School', 'Dublin', aliases: ['ehs', 'pehs']),
  TriValleySchool('Foothill High School', 'Pleasanton', aliases: ['fhs']),
  TriValleySchool('Granada High School', 'Livermore', aliases: ['ghs']),
  TriValleySchool('Livermore High School', 'Livermore', aliases: ['lhs']),
  TriValleySchool(
    'Livermore Valley Charter Preparatory',
    'Livermore',
    aliases: ['lvcp', 'livermore valley charter prep'],
  ),
  TriValleySchool(
    'Monte Vista High School',
    'Danville',
    aliases: ['mvhs', 'monte vista'],
  ),
  TriValleySchool(
    'San Ramon Valley High School',
    'Danville',
    aliases: ['srvhs'],
  ),
  TriValleySchool('The Athenian School', 'Danville', aliases: ['athenian']),
  TriValleySchool('The Quarry Lane School', 'Dublin', aliases: ['quarry lane']),
  TriValleySchool(
    'Valley Christian High School',
    'Dublin',
    aliases: ['valley christian'],
  ),
  TriValleySchool('Valley High School', 'Dublin'),
  TriValleySchool('Village High School', 'Pleasanton'),
];

/// Lowercase, punctuation stripped, and a trailing "high school" / "high" /
/// "school" / "hs" dropped, so "Dublin High" and "dublin high school." match.
String _key(String raw) {
  var s = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.startsWith('the ')) s = s.substring(4);
  for (final suffix in [' high school', ' high', ' school', ' hs']) {
    if (s.endsWith(suffix)) {
      s = s.substring(0, s.length - suffix.length);
      break;
    }
  }
  return s.trim();
}

/// The listed school a typed answer refers to, or null when it isn't one of
/// [triValleySchools].
TriValleySchool? matchTriValleySchool(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final key = _key(raw);
  final lower = raw.trim().toLowerCase();
  for (final s in triValleySchools) {
    if (_key(s.name) == key ||
        s.aliases.contains(lower) ||
        s.aliases.contains(key)) {
      return s;
    }
  }
  return null;
}

/// The name to count a school answer under in metrics: the listed name when
/// it matches one, else the typed answer tidied up (so "  ohlone college "
/// and "Ohlone College" land together). Null when blank.
String? canonicalSchoolName(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final listed = matchTriValleySchool(raw);
  if (listed != null) return listed.name;
  const small = {'of', 'the', 'and', 'at', 'for', 'in'};
  final words = raw.trim().split(RegExp(r'\s+'));
  return [
    for (final (i, w) in words.indexed)
      if (w.length <= 4 && w.toUpperCase() == w)
        w // an acronym like "ISB"
      else if (i > 0 && small.contains(w.toLowerCase()))
        w.toLowerCase()
      else
        '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
  ].join(' ');
}
