// Home's Support EAF, Sponsors and About the app sections, matching the
// website's src/components/home/AboutSections.tsx (Nov 14, 2026). EAF links
// and the sponsor tiers come from EAF's real site, ehsacademics.org
// (Initiatives → Emerald Summit '27 → Sponsor). The old Google Sites page is
// out of date: don't link it.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'summit_logo.dart';

const _eafSite = 'https://www.ehsacademics.org';

/// EAF's Zeffy donation form. Opens in the phone's browser, like the website
/// does on phones.
const eafDonateUrl =
    'https://www.zeffy.com/en-US/donation-form/'
    'be-the-catalyst-for-learning-and-discovery';
const eafVolunteerUrl = '$_eafSite/get-involved/parent-volunteering';
const sponsorshipDetailsUrl = '$_eafSite/initiatives/emerald-summit-27/sponsor';
const sponsorEmail = 'contact@ehsacademics.org';

/// A sponsorship level, highest first in [sponsorTiers].
class SponsorTier {
  const SponsorTier(this.name, this.amount, this.perks);
  final String name;
  final String amount;
  final String perks;
}

/// From the Sponsorship Tiers table on EAF's sponsor page; each includes the
/// ones below it.
const sponsorTiers = [
  SponsorTier(
    'Capstone',
    r'$5,000',
    'Everything in Keystone, plus a year-long portal link',
  ),
  SponsorTier(
    'Keystone',
    r'$2,000',
    'Everything in Pillar, plus a month-long portal link, visibility on the '
        "EAF portal and an ad on the ES'27 app",
  ),
  SponsorTier(
    'Pillar',
    r'$1,500',
    'Everything in Foundation, plus a table or flyers in the Student Union '
        'for 2 hours, or a banner at a discipline of your choice',
  ),
  SponsorTier(
    'Foundation',
    r'$1,000',
    'Everything in Cornerstone, plus a banner at the entrance',
  ),
  SponsorTier(
    'Cornerstone',
    r'$500',
    'A mention in the keynote and your logo on the event slides',
  ),
];

/// One of EAF's sponsors. The logo (on a white background) links to [url].
class Sponsor {
  const Sponsor(this.name, this.tier, this.url, this.logo);
  final String name;
  final String tier;
  final String url;
  final String logo;
}

/// EAF's current sponsors (Nov 14, 2026), the same list as the website's
/// `SPONSORS`. Add one here with its logo in assets/sponsors/ and it shows
/// under its tier.
const sponsors = [
  Sponsor(
    'Brightfox',
    'Keystone',
    'https://gobrightfox.com/',
    'assets/sponsors/brightfox.png',
  ),
  Sponsor(
    'Prepaze Academy',
    'Cornerstone',
    'https://prepazeacademy.com/',
    'assets/sponsors/prepaze-academy.png',
  ),
  Sponsor(
    'YoungWonks',
    'Cornerstone',
    'https://www.youngwonks.com/',
    'assets/sponsors/youngwonks.png',
  ),
  Sponsor(
    'Praan Health',
    'Cornerstone',
    'https://praan.health/',
    'assets/sponsors/praan-health.png',
  ),
];

const _leadDevelopers = ['Arjun Mahajan', 'Akhil Muthyala'];
const _developersAndTesters = [
  'Nithali Anand',
  'Arush Singh',
  'Guhan Bala',
  'Deep Shah',
];

/// "A, B and C".
String joinNames(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

/// The subject line an open sponsor spot emails with.
String sponsorSubject(String tier) => "$tier sponsorship, Emerald Summit '27";

Future<void> _open(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Couldn't open $uri"),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

void _openUrl(BuildContext context, String url) =>
    _open(context, Uri.parse(url));

void _email(BuildContext context, {String? subject}) => _open(
  context,
  Uri(
    scheme: 'mailto',
    path: sponsorEmail,
    query: subject == null ? null : 'subject=${Uri.encodeComponent(subject)}',
  ),
);

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

/// Support EAF: what EAF does, with Donate and Volunteer with EAF.
class SupportEafSection extends StatelessWidget {
  const SupportEafSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Title('Support EAF'),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SummitLogo(size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'This Emerald Summit App is brought to you 100% built '
                        'by students and free for all to use.',
                        style: body,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Emerald Academic Foundation (EAF) supports '
                  'student-initiated projects, like this app, along with '
                  'several others that bring opportunities to students '
                  'across areas, ultimately empowering leadership, '
                  'student-initiative, and collaboration.',
                  style: body,
                ),
                const SizedBox(height: 10),
                Text(
                  'Please consider supporting EAF and its mission.',
                  style: body?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openUrl(context, eafDonateUrl),
                      icon: const Icon(Icons.volunteer_activism, size: 18),
                      label: const Text('Donate'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(context, eafVolunteerUrl),
                      icon: const Icon(Icons.north_east, size: 16),
                      label: const Text('Volunteer with EAF'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sponsors: the five tiers, highest first, each with its
/// sponsors' logos and open spots that email EAF.
class SponsorsSection extends StatelessWidget {
  const SponsorsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Title('Sponsors'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Local businesses and organizations help make the Summit '
                    'happen. Funds go through EAF, so sponsorships are fully '
                    'tax-deductible.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _email(context),
                        icon: const Icon(Icons.mail_outline, size: 18),
                        label: const Text('Become a sponsor'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _openUrl(context, sponsorshipDetailsUrl),
                        icon: const Icon(Icons.north_east, size: 16),
                        label: const Text('Sponsorship details'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < sponsorTiers.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _TierStep(index: i),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierStep extends StatelessWidget {
  const _TierStep({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tier = sponsorTiers[index];
    // The top two are solid emerald; the rest fade to a light tint.
    final solid = index < 2;
    final Color band = switch (index) {
      0 => EmeraldTheme.deepEmerald,
      1 => EmeraldTheme.emerald,
      _ => scheme.primary.withValues(alpha: [0.15, 0.09, 0.04][index - 2]),
    };
    final onBand = solid ? Colors.white : scheme.onSurface;
    final accent = solid
        ? Colors.white.withValues(alpha: 0.85)
        : (dark ? EmeraldTheme.mint : EmeraldTheme.emerald);
    final inTier = [
      for (final s in sponsors)
        if (s.tier == tier.name) s,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: band,
        borderRadius: BorderRadius.circular(8),
        border: solid
            ? null
            : Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  tier.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: onBand,
                  ),
                ),
              ),
              Text(
                tier.amount,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            tier.perks,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: solid
                  ? Colors.white.withValues(alpha: 0.75)
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _TierRow(tier: tier.name, inTier: inTier, solid: solid),
        ],
      ),
    );
  }
}

/// A tier's logos, then open spots filling out the last row so every row is
/// full (a whole row of them when the tier is empty or its logos end a row).
class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tier,
    required this.inTier,
    required this.solid,
  });
  final String tier;
  final List<Sponsor> inTier;
  final bool solid;

  static const _minTile = 104.0;
  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + _gap) / (_minTile + _gap))
            .floor()
            .clamp(1, 6);
        final width = (constraints.maxWidth - _gap * (columns - 1)) / columns;
        final open = columns - inTier.length % columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final s in inTier)
              SizedBox(
                width: width,
                child: _SponsorLogo(sponsor: s),
              ),
            for (var k = 0; k < open; k++)
              SizedBox(
                width: width,
                child: _OpenSpot(tier: tier, solid: solid, first: k == 0),
              ),
          ],
        );
      },
    );
  }
}

class _SponsorLogo extends StatelessWidget {
  const _SponsorLogo({required this.sponsor});
  final Sponsor sponsor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: sponsor.name,
      child: Material(
        color: Colors.white,
        elevation: 1,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _openUrl(context, sponsor.url),
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Image.asset(
                sponsor.logo,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An open spot in a tier; it emails EAF about sponsoring at that level. The
/// first says "Your company logo could go here"; the rest are quieter empty
/// slots with a small +.
class _OpenSpot extends StatelessWidget {
  const _OpenSpot({
    required this.tier,
    required this.solid,
    required this.first,
  });
  final String tier;
  final bool solid;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final base = solid
        ? Colors.white
        : (Theme.of(context).brightness == Brightness.dark
              ? EmeraldTheme.mint
              : EmeraldTheme.emerald);
    final color = base.withValues(alpha: first ? 0.85 : 0.35);
    return Semantics(
      button: true,
      label: 'Your company logo could go here: become a $tier sponsor',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _email(context, subject: sponsorSubject(tier)),
        child: CustomPaint(
          painter: _DashedBorder(
            color: base.withValues(alpha: first ? 0.45 : 0.22),
            width: first ? 1.5 : 1,
          ),
          child: SizedBox(
            height: 60,
            child: Center(
              child: first
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Your company logo could go here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    )
                  : Icon(Icons.add, size: 16, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.width});
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final rect =
        Offset(width / 2, width / 2) &
        Size(size.width - width, size.height - width);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.width != width;
}

/// About the app: who built it.
class AboutAppSection extends StatelessWidget {
  const AboutAppSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final names = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Title('About the app'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This app has been 100% built by Emerald High School '
                    'students.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  Text('LEAD DEVELOPERS', style: label),
                  const SizedBox(height: 4),
                  Text(joinNames(_leadDevelopers), style: names),
                  const SizedBox(height: 12),
                  Text('DEVELOPERS AND TESTERS', style: label),
                  const SizedBox(height: 4),
                  Text(joinNames(_developersAndTesters), style: names),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
