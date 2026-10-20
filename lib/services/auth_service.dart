import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';

/// Signed-in user, role and profile. Roles come from Firebase Auth custom
/// claims (set by the `setUserRole` Cloud Function), so security rules and
/// the app agree on what a user may do.
class AuthService extends ChangeNotifier {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _authOverride = auth,
      _firestoreOverride = firestore;

  // Resolved on first use so the service can be constructed (and faked in
  // widget tests) without an initialised Firebase app.
  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _firestoreOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _profileSubscription;

  AppUser? _user;
  bool _initialized = false;

  AppUser? get user => _user;

  bool get isSignedIn => _user != null;

  /// False until Firebase has reported the persisted sign-in state.
  bool get initialized => _initialized;

  UserRole get role => _user?.role ?? UserRole.viewer;

  bool get canRespondToAlerts => role.canRespondToAlerts;

  bool get isAdmin => role == UserRole.admin;

  void start() {
    _authSubscription ??= _auth.idTokenChanges().listen(_handleAuthUser);
  }

  Future<void> _handleAuthUser(User? firebaseUser) async {
    await _profileSubscription?.cancel();
    _profileSubscription = null;

    if (firebaseUser == null) {
      _user = null;
      _initialized = true;
      notifyListeners();
      return;
    }

    UserRole role = UserRole.viewer;

    try {
      final token = await firebaseUser.getIdTokenResult();
      role = UserRole.fromClaim(token.claims?['role']);
    } catch (error) {
      debugPrint('Could not read role claim: $error');
    }

    _user = AppUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      displayName: firebaseUser.displayName ?? firebaseUser.email ?? 'User',
      role: role,
      subscribedNodes: _user?.uid == firebaseUser.uid
          ? _user!.subscribedNodes
          : const [],
    );
    _initialized = true;
    notifyListeners();

    _profileSubscription = _firestore
        .collection('users')
        .doc(firebaseUser.uid)
        .snapshots()
        .listen(
          (snapshot) {
            final current = _user;

            if (current == null || current.uid != firebaseUser.uid) {
              return;
            }

            _user = current.withProfile(snapshot.data());
            notifyListeners();
          },
          onError: (error) {
            debugPrint('User profile stream error: $error');
          },
        );
  }

  Future<void> signIn({required String email, required String password}) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Creates an account. New accounts are viewers (no role claim): they
  /// see every sensor, its location and alerts, but can't respond to alerts
  /// or add sensors until an administrator gives them a role.
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) return;
    await user.updateDisplayName(name.trim());
    await _firestore.collection('users').doc(user.uid).set({
      'displayName': name.trim(),
      'email': email.trim().toLowerCase(),
      'subscribedNodes': const <String>[],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // The display name is set after the first token; refresh the profile.
    await user.reload();
    await _handleAuthUser(_auth.currentUser);
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _auth.signOut();

  /// Forces a fresh ID token so a role changed by an admin takes effect
  /// without signing out.
  Future<void> refreshRole() async {
    await _auth.currentUser?.getIdToken(true);
  }

  Future<void> updateSubscribedNodes(List<String> nodeIds) async {
    final current = _user;

    if (current == null) {
      return;
    }

    await _firestore.collection('users').doc(current.uid).set({
      'subscribedNodes': nodeIds,
      'email': current.email,
      'displayName': current.displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Human-readable message for a sign-in failure.
  static String describeError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'That email address is not valid.';
        case 'user-disabled':
          return 'This account has been disabled. Contact your administrator.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'too-many-requests':
          return 'Too many attempts. Try again in a few minutes.';
        case 'network-request-failed':
          return 'No network connection.';
        case 'email-already-in-use':
          return 'An account with this email already exists. Sign in instead.';
        case 'weak-password':
          return 'Choose a stronger password (at least 6 characters).';
        case 'operation-not-allowed':
          return 'New accounts are turned off. Ask your administrator.';
      }

      return error.message ?? 'Sign-in failed (${error.code}).';
    }

    return 'Sign-in failed. Please try again.';
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }
}
