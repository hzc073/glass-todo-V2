import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/login_attempt_limiter.dart';
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
    required this.loginAttemptLimiter,
    required this.onLogin,
    required this.onOpenSettings,
  });

  final String appTitle;
  final LoginAttemptLimiter loginAttemptLimiter;
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
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _userController.addListener(_syncLockoutTimer);
    _syncLockoutTimer();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _userController.removeListener(_syncLockoutTimer);
    _userController.dispose();
    _passwordController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final username = _userController.text.trim();
    final lockoutState = widget.loginAttemptLimiter.stateFor(username);
    final locked = lockoutState.isLocked;
    final errorText = locked ? _formatLockoutError(lockoutState) : _error;

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
                        child: AnimatedOpacity(
                          opacity: locked ? 0.55 : 1,
                          duration: const Duration(milliseconds: 200),
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
                                enabled: !_loading && !locked,
                                decoration: const InputDecoration(labelText: '用户名'),
                                validator: (value) => value == null || value.trim().isEmpty
                                    ? '请输入用户名。'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordController,
                                enabled: !_loading && !locked,
                                decoration: const InputDecoration(labelText: '密码'),
                                obscureText: true,
                                validator: (value) => value == null || value.trim().isEmpty
                                    ? '请输入密码。'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: _showInvite
                                    ? TextFormField(
                                        key: const ValueKey('invite'),
                                        controller: _inviteController,
                                        enabled: !_loading && !locked,
                                        decoration: const InputDecoration(labelText: '邀请码'),
                                      )
                                    : const SizedBox.shrink(key: ValueKey('empty')),
                              ),
                              if (errorText != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  errorText,
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
                                  onPressed: _loading || locked ? null : _handleLogin,
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
        ),
      ],
    );
  }

  Future<void> _handleLogin() async {
    final username = _userController.text.trim();
    if (widget.loginAttemptLimiter.stateFor(username).isLocked) {
      _syncLockoutTimer();
      return;
    }

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.onLogin(
      username,
      _passwordController.text,
      _inviteController.text.trim(),
    );
    if (result.success) {
      await widget.loginAttemptLimiter.recordSuccess(username);
    } else if (_shouldCountPasswordFailure(result)) {
      await widget.loginAttemptLimiter.recordFailure(username);
    }
    if (!mounted) return;
    final lockoutState = widget.loginAttemptLimiter.stateFor(username);
    setState(() {
      _loading = false;
      _showInvite = result.needInvite || _showInvite;
      _error = lockoutState.isLocked
          ? null
          : (result.success ? null : (result.error ?? '登录失败。'));
    });
    _syncLockoutTimer();
  }

  void _syncLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = null;

    final username = _userController.text.trim();
    if (!widget.loginAttemptLimiter.stateFor(username).isLocked) return;

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final username = _userController.text.trim();
      final locked = widget.loginAttemptLimiter.stateFor(username).isLocked;
      if (!locked) {
        _lockoutTimer?.cancel();
        _lockoutTimer = null;
      }
      setState(() {});
    });

    if (mounted) setState(() {});
  }

  bool _shouldCountPasswordFailure(LoginOutcome outcome) {
    if (outcome.success) return false;
    if (outcome.needInvite) return false;
    final message = (outcome.error ?? '').trim();
    if (message.isEmpty) return false;
    return message == '密码错误' ||
        message == 'Unauthorized' ||
        message == 'Invalid token' ||
        message == 'Invalid credentials';
  }

  String _formatLockoutError(LoginAttemptState state) {
    final remaining = state.remainingLock ?? Duration.zero;
    final totalSeconds = remaining.inSeconds.clamp(0, 24 * 60 * 60);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '密码错误次数过多，已禁止登录，请 $minutes:$seconds 后重试。';
  }
}
