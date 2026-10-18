enum UserRole {
  viewer,
  officer,
  admin;

  static UserRole fromClaim(dynamic value) {
    switch (value?.toString()) {
      case 'admin':
        return UserRole.admin;
      case 'officer':
        return UserRole.officer;
      default:
        return UserRole.viewer;
    }
  }

  bool get canRespondToAlerts => this == officer || this == admin;

  String get label {
    switch (this) {
      case UserRole.viewer:
        return 'Viewer';
      case UserRole.officer:
        return 'Officer';
      case UserRole.admin:
        return 'Administrator';
    }
  }
}

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final UserRole role;

  /// Nodes this user receives push alerts for. Empty means all nodes.
  final List<String> subscribedNodes;

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.subscribedNodes = const [],
  });

  AppUser withProfile(Map<String, dynamic>? profile) {
    if (profile == null) {
      return this;
    }

    final nodes = profile['subscribedNodes'];
    final name = profile['displayName'];

    return AppUser(
      uid: uid,
      email: email,
      displayName: name is String && name.isNotEmpty ? name : displayName,
      role: role,
      subscribedNodes: nodes is List
          ? nodes.map((node) => node.toString()).toList()
          : subscribedNodes,
    );
  }
}
