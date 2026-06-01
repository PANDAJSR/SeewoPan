class WebDavSettings {
  const WebDavSettings({
    required this.port,
    required this.username,
    required this.password,
  });

  static const defaults = WebDavSettings(
    port: 8088,
    username: 'seewopan',
    password: '',
  );

  final int port;
  final String username;
  final String password;

  bool get hasAuth => username.trim().isNotEmpty || password.isNotEmpty;

  WebDavSettings copyWith({
    int? port,
    String? username,
    String? password,
  }) {
    return WebDavSettings(
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}
