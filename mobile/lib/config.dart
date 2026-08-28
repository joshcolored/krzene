class AppConfig {
  static const _configuredApiBaseUrl = String.fromEnvironment(
    'KRZENE_API_BASE_URL',
  );
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wtlqjlxntbxpwarkbltq.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_Xl6GA7BlZW3jTDI31GKXcA_z0kRXzeG',
  );
  static String get apiBaseUrl {
    if (_configuredApiBaseUrl.isNotEmpty) return _configuredApiBaseUrl;
    return 'https://krzene.site';
  }

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
