import 'package:flutter/material.dart';

/// The roles a Summit account can hold. Picked during sign-up; drives which
/// onboarding fields we collect and which management privileges the user gets.
/// Stored as `profiles.role` (the enum `name`, e.g. "volunteer").
///
/// `participant`, `expert`, `parent` are open to anyone. `volunteer` and `admin`
/// are gated: the email must be on the synced `role_allowlist` (from the Google
/// Sheets) or the server forces the account back to `participant`. Volunteers
/// carry a [VolunteerSubtype] plus fine-grained capability flags (all set by the
/// server from the sheet); admins are global.
enum SummitRole { participant, expert, parent, volunteer, admin }

/// The kind of volunteer, set from the Google Sheet's `subtype` column and
/// stored on `profiles.volunteer_subtype`. Drives the profile badge and the
/// default capability set the enforcement trigger applies:
///   * [eafAmbassador]   — manages a discipline (edits sessions; may post
///     announcements to it).
///   * [parentVolunteer] / [studentVolunteer] — operational help; no content
///     editing by default. Any subtype can be assigned to sessions (for roster
///     + attendance) and can be granted front-desk check-in.
enum VolunteerSubtype { eafAmbassador, parentVolunteer, studentVolunteer }

extension VolunteerSubtypeX on VolunteerSubtype {
  /// Value stored in the database (matches the sheet's `subtype` column).
  String get id => switch (this) {
        VolunteerSubtype.eafAmbassador => 'eaf_ambassador',
        VolunteerSubtype.parentVolunteer => 'parent_volunteer',
        VolunteerSubtype.studentVolunteer => 'student_volunteer',
      };

  String get label => switch (this) {
        VolunteerSubtype.eafAmbassador => 'EAF Ambassador',
        VolunteerSubtype.parentVolunteer => 'Parent Volunteer',
        VolunteerSubtype.studentVolunteer => 'Student Volunteer',
      };

  /// Parses the stored id, or null for an unknown/absent value.
  static VolunteerSubtype? fromId(String? id) {
    if (id == null) return null;
    for (final s in VolunteerSubtype.values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// One extra field collected during onboarding for a given role. The [key]
/// is where the answer lands in `profiles.details` (a jsonb bag), so roles
/// can ask for different things without a column per field.
class ProfileField {
  const ProfileField({
    required this.key,
    required this.label,
    this.hint,
    this.required = false,
    this.keyboardType = TextInputType.text,
  });

  final String key;
  final String label;
  final String? hint;
  final bool required;
  final TextInputType keyboardType;
}

extension SummitRoleX on SummitRole {
  /// Value stored in the database.
  String get id => name;

  String get label => switch (this) {
        SummitRole.participant => 'Participant',
        SummitRole.expert => 'Expert / Speaker',
        SummitRole.parent => 'Parent / Spectator',
        SummitRole.volunteer => 'Volunteer',
        SummitRole.admin => 'Admin',
      };

  String get blurb => switch (this) {
        SummitRole.participant =>
          'Build your schedule and follow your summit day.',
        SummitRole.expert => 'Lead a session or speak at the summit.',
        SummitRole.parent => 'Follow along and stay in the loop.',
        SummitRole.volunteer =>
          'Help run the summit — EAF ambassadors, parent and student volunteers.',
        SummitRole.admin => 'Manage the summit, announcements, and content.',
      };

  IconData get icon => switch (this) {
        SummitRole.participant => Icons.school_outlined,
        SummitRole.expert => Icons.mic_none_outlined,
        SummitRole.parent => Icons.family_restroom_outlined,
        SummitRole.volunteer => Icons.volunteer_activism_outlined,
        SummitRole.admin => Icons.admin_panel_settings_outlined,
      };

  /// Whether this role must be verified against the synced allowlist at sign-up.
  bool get isGated => this == SummitRole.volunteer || this == SummitRole.admin;

  /// Role-specific onboarding questions, asked after name + role.
  ///
  /// The design intent (per spec): ask volunteers for full contact details since
  /// they're staffing the event, but keep experts light — we don't want to
  /// over-collect from busy speakers. Admins need nothing extra.
  ///
  /// TODO(volunteer-subtypes): tailor these per [VolunteerSubtype] once the
  /// subtype is known at onboarding (deferred — the subtype currently arrives
  /// from the sheet after sign-up).
  List<ProfileField> get onboardingFields => switch (this) {
        SummitRole.participant => const [
            ProfileField(key: 'school', label: 'School', hint: 'e.g. Emerald High'),
            ProfileField(key: 'grade', label: 'Grade', hint: 'e.g. 11'),
            ProfileField(
                key: 'dietary',
                label: 'Dietary needs (optional)',
                hint: 'e.g. vegetarian, nut allergy'),
          ],
        SummitRole.volunteer => const [
            ProfileField(key: 'school', label: 'School', hint: 'e.g. Emerald High'),
            ProfileField(key: 'grade', label: 'Grade', hint: 'e.g. 11'),
            ProfileField(
                key: 'phone',
                label: 'Mobile number',
                required: true,
                hint: 'For day-of coordination',
                keyboardType: TextInputType.phone),
            ProfileField(
                key: 'emergency_contact',
                label: 'Emergency contact name',
                required: true),
            ProfileField(
                key: 'emergency_phone',
                label: 'Emergency contact number',
                required: true,
                keyboardType: TextInputType.phone),
            ProfileField(
                key: 'dietary',
                label: 'Dietary needs (optional)',
                hint: 'e.g. vegetarian, nut allergy'),
          ],
        SummitRole.expert => const [
            ProfileField(
                key: 'organization',
                label: 'Organization',
                required: true,
                hint: 'Company, lab, or school'),
            ProfileField(
                key: 'expertise',
                label: 'Area of expertise',
                required: true,
                hint: 'e.g. Robotics, Bioengineering'),
          ],
        SummitRole.parent => const [
            ProfileField(
                key: 'phone',
                label: 'Mobile number',
                required: true,
                keyboardType: TextInputType.phone),
            ProfileField(
                key: 'student_name',
                label: "Student's name",
                required: true),
          ],
        SummitRole.admin => const [],
      };

  static SummitRole fromId(String? id) => SummitRole.values.firstWhere(
        (r) => r.name == id,
        orElse: () => SummitRole.participant,
      );
}

/// A user's app-facing profile — mirrors a row in the `profiles` table. Bound
/// to the auth account (and therefore the email) by [id], so it follows the
/// user across devices and across a future switch from OTP to Google sign-in.
class UserProfile {
  UserProfile({
    required this.id,
    required this.email,
    this.fullName = '',
    this.role = SummitRole.participant,
    this.onboarded = false,
    this.notificationsEnabled = true,
    this.volunteerHours = 0,
    this.volunteerSubtype,
    this.canEditSessions = false,
    this.canPostAnnouncements = false,
    this.canCheckInFrontDesk = false,
    List<String>? managedDisciplines,
    Map<String, dynamic>? details,
  })  : managedDisciplines = managedDisciplines ?? const [],
        details = details ?? <String, dynamic>{};

  final String id;
  final String email;
  String fullName;
  SummitRole role;
  bool onboarded;

  /// Per-user app state, stored on the profile row so it follows the account
  /// across devices (was in-memory in AppState before Phase 1).
  bool notificationsEnabled;
  double volunteerHours;

  /// The volunteer's subtype (EAF ambassador / parent / student), or null for
  /// non-volunteers. Set by the server from the sheet; read-only here.
  final VolunteerSubtype? volunteerSubtype;

  /// Fine-grained capabilities, all **server-owned** (set by the enforcement
  /// trigger from the Google Sheet; never written back by the app):
  ///   * [canEditSessions]      — create/edit/delete sessions in
  ///     [managedDisciplines] (EAF ambassadors by default).
  ///   * [canPostAnnouncements] — post announcements to a managed discipline.
  ///   * [canCheckInFrontDesk]  — mark any attendee arrived at the front desk.
  /// Admins implicitly have all of these regardless of the flags.
  final bool canEditSessions;
  final bool canPostAnnouncements;
  final bool canCheckInFrontDesk;

  /// Discipline ids a volunteer may manage, or `['*']` for a volunteer who
  /// manages every discipline. Set by the server (the allowlist enforcement
  /// trigger), read-only from the app's perspective. Empty for other roles.
  final List<String> managedDisciplines;

  /// True if this account may manage content in the given discipline (admins:
  /// always; volunteers: only when [canEditSessions] AND scoped to it — or the
  /// `*` wildcard).
  bool canManageDiscipline(String disciplineId) {
    if (role == SummitRole.admin) return true;
    if (role != SummitRole.volunteer || !canEditSessions) return false;
    return managedDisciplines.contains('*') ||
        managedDisciplines.contains(disciplineId);
  }

  /// True if this account may post an announcement targeting the given
  /// discipline (admins: any; volunteers: [canPostAnnouncements] AND scoped).
  bool canPostToDiscipline(String disciplineId) {
    if (role == SummitRole.admin) return true;
    if (role != SummitRole.volunteer || !canPostAnnouncements) return false;
    return managedDisciplines.contains('*') ||
        managedDisciplines.contains(disciplineId);
  }

  /// Role-specific answers (phone, school, org…) → `profiles.details` jsonb.
  final Map<String, dynamic> details;

  factory UserProfile.fromMap(Map<String, dynamic> row) => UserProfile(
        id: row['id'] as String,
        email: (row['email'] ?? '') as String,
        fullName: (row['full_name'] ?? '') as String,
        role: SummitRoleX.fromId(row['role'] as String?),
        onboarded: (row['onboarded'] ?? false) as bool,
        notificationsEnabled: (row['notifications_enabled'] ?? true) as bool,
        volunteerHours: (row['volunteer_hours'] as num?)?.toDouble() ?? 0,
        volunteerSubtype:
            VolunteerSubtypeX.fromId(row['volunteer_subtype'] as String?),
        canEditSessions: (row['can_edit_sessions'] ?? false) as bool,
        canPostAnnouncements: (row['can_post_announcements'] ?? false) as bool,
        canCheckInFrontDesk: (row['can_check_in_front_desk'] ?? false) as bool,
        managedDisciplines:
            (row['managed_disciplines'] as List?)?.cast<String>() ?? const [],
        details: (row['details'] as Map?)?.cast<String, dynamic>() ?? {},
      );

  /// Columns the app writes back. Deliberately omits per-user state that has its
  /// own targeted update path (notifications_enabled, volunteer_hours) and any
  /// role-scope columns the server owns, so a profile save never clobbers them.
  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'role': role.id,
        'details': details,
        'onboarded': onboarded,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}
