import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  AuthStore._(this._prefs, {this.username, this.token});

  static const _tokenKey = 'glass_auth_token';
  static const _userKey = 'glass_auth_user';

  final SharedPreferences _prefs;
  String? username;
  String? token;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  static Future<AuthStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AuthStore._(
      prefs,
      username: prefs.getString(_userKey),
      token: prefs.getString(_tokenKey),
    );
  }

  Future<void> setSession({required String username, required String token}) async {
    this.username = username;
    this.token = token;
    await _prefs.setString(_userKey, username);
    await _prefs.setString(_tokenKey, token);
  }

  Future<void> clear() async {
    username = null;
    token = null;
    await _prefs.remove(_userKey);
    await _prefs.remove(_tokenKey);
  }
}
