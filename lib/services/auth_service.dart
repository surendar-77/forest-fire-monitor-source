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
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

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
