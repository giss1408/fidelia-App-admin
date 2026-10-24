/// Parses an ISO-8601 timestamp from the server. The backend sends naive UTC
/// (no offset), so a value without one is read as UTC, never as local time.
DateTime parseServerTime(String value) {
  final time = value.contains('T') ? value.split('T').last : '';
  final hasOffset = RegExp(r'(Z|[+-]\d{2}(:?\d{2})?)$').hasMatch(time);
  return DateTime.parse(hasOffset ? value : '${value}Z').toUtc();
}

DateTime? _optionalTime(Object? value) => value is String ? parseServerTime(value) : null;

/// One open request the team handles by hand (a code or a temporary password
/// to send over WhatsApp). The phone is already masked by the server.
class AccountCheck {
  const AccountCheck({
    required this.id,
    required this.kind,
    required this.app,
    required this.phoneMasked,
    required this.createdAt,
    required this.sentAt,
    required this.teamCreated,
  });

  factory AccountCheck.fromJson(Map<String, Object?> json) => AccountCheck(
        id: json['id']! as int,
        kind: json['kind']! as String,
        app: json['app']! as String,
        phoneMasked: json['phone_masked']! as String,
        createdAt: parseServerTime(json['created_at']! as String),
        sentAt: _optionalTime(json['sent_at']),
        teamCreated: json['team_created'] == true,
      );

  final int id;
  final String kind;
  final String app;
  final String phoneMasked;
  final DateTime createdAt;
  final DateTime? sentAt;
  final bool teamCreated;
}

/// One of the shared test logins (fidelia-BE app/seed.py).
class TestAccount {
  const TestAccount({required this.phoneMasked, required this.role, required this.hasPassword});

  factory TestAccount.fromJson(Map<String, Object?> json) => TestAccount(
        phoneMasked: json['phone_masked']! as String,
        role: json['role']! as String,
        hasPassword: json['has_password'] == true,
      );

  final String phoneMasked;
  final String role;
  final bool hasPassword;
}

/// An account as the admin sees it after a search.
class AdminUserView {
  const AdminUserView({
    required this.id,
    required this.phoneMasked,
    required this.roles,
    required this.disabled,
    required this.verified,
    required this.lastLoginAt,
  });

  factory AdminUserView.fromJson(Map<String, Object?> json) => AdminUserView(
        id: json['id']! as int,
        phoneMasked: json['phone_masked']! as String,
        roles: [for (final r in (json['roles'] as List? ?? const [])) r as String],
        disabled: json['disabled'] == true,
        verified: json['verified'] == true,
        lastLoginAt: _optionalTime(json['last_login_at']),
      );

  final int id;
  final String phoneMasked;
  final List<String> roles;
  final bool disabled;
  final bool verified;
  final DateTime? lastLoginAt;
}
