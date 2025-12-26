import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'widgets/decorative_background.dart';

class LoginOutcome {
  const LoginOutcome({required this.success, this.error, this.needInvite = false});

  final bool success;
  final String? error;
  final bool needInvite;
}

typedef LoginHandler = Future<LoginOutcome> Function(
  String username,
  String password,
  String inviteCode,
);

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.appTitle,
    required this.onLogin,
    required this.onOpenSettings,
  });

  final String appTitle;
  final LoginHandler onLogin;
  final VoidCallback onOpenSettings;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteController = TextEditingController();
  bool _loading = false;
  bool _showInvite = false;
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const DecorativeBackground(),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 18),
                      child: child,
                    ),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.appTitle,
                              style: GoogleFonts.fraunces(
                                textStyle: Theme.of(context).textTheme.headlineSmall,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '欢迎回来。柔和而专注地安排一天。',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.inkSoft),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _userController,
                              decoration: const InputDecoration(labelText: '用户名'),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty ? '请输入用户名。' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              decoration: const InputDecoration(labelText: '密码'),
                              obscureText: true,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty ? '请输入密码。' : null,
                            ),
                            const SizedBox(height: 12),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: _showInvite
                                  ? TextFormField(
                                      key: const ValueKey('invite'),
                                      controller: _inviteController,
                                      decoration: const InputDecoration(labelText: '邀请码'),
                                    )
                                  : const SizedBox.shrink(key: ValueKey('empty')),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.accentDeep),
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _handleLogin,
                                child: _loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('登录'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => setState(() => _showInvite = !_showInvite),
                              child: Text(_showInvite ? '隐藏邀请码' : '有邀请码？'),
                            ),
                            TextButton(
                              onPressed: widget.onOpenSettings,
                              child: const Text('后端地址设置'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleLogin() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.onLogin(
      _userController.text.trim(),
      _passwordController.text,
      _inviteController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _showInvite = result.needInvite || _showInvite;
      _error = result.success ? null : (result.error ?? '登录失败。');
    });
  }
}
