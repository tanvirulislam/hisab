import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' show DriveApi;
import 'package:http/http.dart' as http;

import '../../../core/errors/app_exception.dart';
import '../domain/backup_file.dart';
import 'drive_config.dart';

/// The Google account that owns the Drive backups (D22). Behind an interface
/// so tests use a fake.
abstract interface class GoogleAccount {
  /// Signed-in account's email, or null.
  String? get email;

  /// Signs in without any UI if the user did before. Returns the email, or
  /// null when a prompt would be needed. Never throws.
  Future<String?> signInSilently();

  /// Interactive sign-in plus Drive permission. Throws [BackupException].
  Future<String> signIn();

  Future<void> signOut();

  /// An HTTP client that sends the Drive access token. Throws
  /// [BackupException] with [BackupError.notSignedIn] when no token can be
  /// had without UI (and [interactive] is false).
  Future<http.Client> authClient({bool interactive = false});
}

/// google_sign_in 7.x: authentication (who) and authorization (Drive scope)
/// are separate steps.
class GoogleSignInAccountService implements GoogleAccount {
  static const scopes = [DriveApi.driveFileScope];

  Future<void>? _init;
  GoogleSignInAccount? _user;

  GoogleSignIn get _gsi => GoogleSignIn.instance;

  Future<void> _ensureInit() => _init ??= _gsi.initialize(serverClientId: kGoogleServerClientId);

  @override
  String? get email => _user?.email;

  @override
  Future<String?> signInSilently() async {
    if (!isGoogleConfigured) return null;
    try {
      await _ensureInit();
      _user = await _gsi.attemptLightweightAuthentication();
    } on Object catch (e) {
      debugPrint('Silent sign-in failed: $e');
      _user = null;
    }
    return _user?.email;
  }

  @override
  Future<String> signIn() async {
    if (!isGoogleConfigured) throw const BackupException(BackupError.notConfigured);
    try {
      await _ensureInit();
      final user = await _gsi.authenticate(scopeHint: scopes);
      await user.authorizationClient.authorizeScopes(scopes);
      _user = user;
      return user.email;
    } on GoogleSignInException catch (e) {
      throw BackupException(
        e.code == GoogleSignInExceptionCode.canceled ? BackupError.signInCancelled : BackupError.signInFailed,
        '${e.code}: ${e.description}',
      );
    }
  }

  @override
  Future<void> signOut() async {
    _user = null;
    if (_init == null) return;
    try {
      await _gsi.signOut();
    } on Object catch (e) {
      debugPrint('Sign-out failed: $e');
    }
  }

  @override
  Future<http.Client> authClient({bool interactive = false}) async {
    final user = _user ?? (await signInSilently() == null ? null : _user);
    if (user == null) throw const BackupException(BackupError.notSignedIn);
    try {
      var authz = await user.authorizationClient.authorizationForScopes(scopes);
      if (authz == null && interactive) authz = await user.authorizationClient.authorizeScopes(scopes);
      if (authz == null) throw const BackupException(BackupError.notSignedIn);
      return authz.authClient(scopes: scopes);
    } on GoogleSignInException catch (e) {
      throw BackupException(
        e.code == GoogleSignInExceptionCode.canceled ? BackupError.signInCancelled : BackupError.notSignedIn,
        '${e.code}: ${e.description}',
      );
    }
  }
}
