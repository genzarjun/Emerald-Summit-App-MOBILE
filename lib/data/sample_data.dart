import 'package:flutter/material.dart';

import '../models/models.dart';

/// Placeholder content for the skeleton build. In production this comes
/// from the Supabase/Firebase backend (spec section 05). Names and
/// details here are sample data only.
class SampleData {
  static const eventName = 'Emerald Summit \'27';
  static const eventDate = 'January 2027';
  static const eventVenue = 'Emerald High · Dublin, CA';

  static const List<Discipline> disciplines = [
    Discipline(
      id: 'techverse',
      name: 'TechVerse',
      tagline: 'Coding & software',
      icon: Icons.terminal,
      sessions: [
        Session(
          id: 's1',
          disciplineId: 'techverse',
          title: 'Intro to App Development',
          disciplineName: 'TechVerse',
          track: 'Mobile Track',
          room: 'Room 204',
          expertName: 'Dr. Priya Rao',
          start: '10:00',
          end: '10:45',
          capacity: 30,
          enrolled: 22,
          description:
              'Build your first cross-platform app and pitch it to a '
              'panel of industry mentors. Laptops provided.',
          sponsor: 'Sponsored by NorCal DevWorks',
        ),
        Session(
          id: 's2',
          disciplineId: 'techverse',
          title: 'Competitive Programming Sprint',
          disciplineName: 'TechVerse',
          track: 'Algorithms Track',
          room: 'Room 208',
          expertName: 'Mr. Alan Chen',
          start: '13:00',
          end: '14:00',
          capacity: 24,
          enrolled: 24,
          description:
              'A timed problem-solving challenge. Teams race the clock '
              'on classic algorithmic puzzles.',
        ),
      ],
    ),
    Discipline(
      id: 'robosphere',
      name: 'RoboSphere',
      tagline: 'Robotics & engineering',
      icon: Icons.precision_manufacturing,
      sessions: [
        Session(
          id: 's3',
          disciplineId: 'robosphere',
          title: 'Autonomous Robot Showcase',
          disciplineName: 'RoboSphere',
          track: 'Autonomy Track',
          room: 'Gym A',
          expertName: 'Ms. Deepa Nair',
          start: '10:45',
          end: '11:45',
          capacity: 40,
          enrolled: 31,
          description:
              'Demonstrate an autonomous robot navigating an obstacle '
              'course. Judged on reliability and design.',
        ),
      ],
    ),
    Discipline(
      id: 'biosphere',
      name: 'BioSphere',
      tagline: 'Life sciences',
      icon: Icons.biotech,
      sessions: [
        Session(
          id: 's4',
          disciplineId: 'biosphere',
          title: 'CRISPR & the Future of Medicine',
          disciplineName: 'BioSphere',
          track: 'Genomics Track',
          room: 'Lab 101',
          expertName: 'Dr. Maria Alvarez',
          start: '11:00',
          end: '11:45',
          capacity: 28,
          enrolled: 12,
          description:
              'An interactive session on gene editing, its promise, and '
              'the ethics that surround it.',
        ),
      ],
    ),
    Discipline(
      id: 'novasphere',
      name: 'NovaSphere',
      tagline: 'Space & physics',
      icon: Icons.rocket_launch,
      sessions: [
        Session(
          id: 's5',
          disciplineId: 'novasphere',
          title: 'Model Rocketry Challenge',
          disciplineName: 'NovaSphere',
          track: 'Aerospace Track',
          room: 'Field 2',
          expertName: 'Capt. John Reeves',
          start: '13:00',
          end: '14:00',
          capacity: 20,
          enrolled: 7,
          description:
              'Design, build, and launch a model rocket. Prizes for '
              'apogee and recovery accuracy.',
        ),
      ],
    ),
    Discipline(
      id: 'artverse',
      name: 'ArtVerse',
      tagline: 'Arts & design',
      icon: Icons.palette,
      sessions: [
        Session(
          id: 's6',
          disciplineId: 'artverse',
          title: 'Digital Illustration Workshop',
          disciplineName: 'ArtVerse',
          track: 'Design Track',
          room: 'Art Studio',
          expertName: 'Ms. Lena Park',
          start: '10:00',
          end: '10:45',
          capacity: 25,
          enrolled: 18,
          description:
              'Learn digital painting fundamentals and leave with a '
              'finished piece for your portfolio.',
        ),
      ],
    ),
    Discipline(
      id: 'mathverse',
      name: 'MathVerse',
      tagline: 'Mathematics & logic',
      icon: Icons.functions,
      sessions: [
        Session(
          id: 's7',
          disciplineId: 'mathverse',
          title: 'Math Olympiad Relay',
          disciplineName: 'MathVerse',
          track: 'Problem Solving Track',
          room: 'Room 112',
          expertName: 'Dr. Samuel Osei',
          start: '14:15',
          end: '15:00',
          capacity: 32,
          enrolled: 20,
          description:
              'A fast-paced team relay of olympiad-style problems across '
              'algebra, geometry, and combinatorics.',
        ),
      ],
    ),
  ];

  /// Flattened list of every session across all disciplines.
  static List<Session> get allSessions =>
      [for (final d in disciplines) ...d.sessions];

  static const List<Announcement> announcements = [
    Announcement(
      id: 'a1',
      title: 'Welcome to Emerald Summit \'27!',
      body:
          'Doors open at 8:30 AM. Check in at the main entrance, then head '
          'to the opening ceremony in the auditorium at 9:00 AM.',
      author: 'Summit Admin',
      audience: 'Everyone',
      timeAgo: '2h ago',
      pinned: true,
    ),
    Announcement(
      id: 'a2',
      title: 'Room change: Robotics Showcase',
      body:
          'The Autonomous Robot Showcase has moved from Gym B to Gym A. '
          'Your schedule has been updated automatically.',
      author: 'RoboSphere Team',
      audience: 'RoboSphere',
      timeAgo: '35m ago',
    ),
    Announcement(
      id: 'a3',
      title: 'Lunch is served in the quad',
      body: 'Grab-and-go lunch is available from 12:00–1:00 PM in the quad.',
      author: 'Summit Admin',
      audience: 'Everyone',
      timeAgo: '10m ago',
    ),
  ];

  static const List<ResourceDoc> resources = [
    ResourceDoc(
      id: 'r1',
      title: 'Master Schedule (PDF)',
      category: 'Schedules',
      icon: Icons.calendar_month,
    ),
    ResourceDoc(
      id: 'r2',
      title: 'Campus Map',
      category: 'Navigation',
      icon: Icons.map,
    ),
    ResourceDoc(
      id: 'r3',
      title: 'Code of Conduct',
      category: 'Policies',
      icon: Icons.gavel,
    ),
    ResourceDoc(
      id: 'r4',
      title: 'TechVerse Track Brief',
      category: 'Track Briefs',
      icon: Icons.description,
    ),
    ResourceDoc(
      id: 'r5',
      title: 'Sponsor Directory',
      category: 'Sponsors',
      icon: Icons.handshake,
    ),
  ];

  /// Sample slideshow photos for demo mode (no live backend). With Supabase
  /// configured these come from the `gallery_photos` Storage bucket instead.
  /// Picsum gives stable, hotlink-friendly placeholder photos.
  static const List<GalleryPhoto> galleryPhotos = [
    GalleryPhoto(id: 'g1', imageUrl: 'https://picsum.photos/id/180/1200/675'),
    GalleryPhoto(id: 'g2', imageUrl: 'https://picsum.photos/id/1067/1200/675'),
    GalleryPhoto(id: 'g3', imageUrl: 'https://picsum.photos/id/1084/1200/675'),
    GalleryPhoto(id: 'g4', imageUrl: 'https://picsum.photos/id/366/1200/675'),
  ];
}
