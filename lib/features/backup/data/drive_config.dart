/// Google OAuth "Web application" client ID, used as `serverClientId` by
/// google_sign_in on Android (D22). It is not a secret.
///
/// Google Cloud project `hisab-516008`, client "Hisab Web". The Android
/// client "Hisab Android" in the same project holds the package name and the
/// signing key's SHA-1. While this is empty, sign-in shows "not set up".
const String kGoogleServerClientId = '362653692742-vfpr9s59bomuveakivnm22d0pk7js6uq.apps.googleusercontent.com';

/// Whether [kGoogleServerClientId] was filled in.
bool get isGoogleConfigured => kGoogleServerClientId.endsWith('.apps.googleusercontent.com');

/// The Drive folder the app keeps its backups in.
const String kDriveFolderName = 'Hisab Backup';
