/// Google OAuth "Web application" client ID, used as `serverClientId` by
/// google_sign_in on Android (D22). It is not a secret.
///
/// TODO(owner): paste the Web client ID from Google Cloud Console →
/// APIs & Services → Credentials (it ends in `.apps.googleusercontent.com`).
/// While this is empty, "Sign in with Google" shows "backup is not set up".
const String kGoogleServerClientId = '';

/// Whether [kGoogleServerClientId] was filled in.
bool get isGoogleConfigured => kGoogleServerClientId.endsWith('.apps.googleusercontent.com');

/// The Drive folder the app keeps its backups in.
const String kDriveFolderName = 'Hisab Backup';
