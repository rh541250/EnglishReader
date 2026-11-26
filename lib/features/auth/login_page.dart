import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/auth_service.dart';
import '../../motion/entrance.dart';

/// 登录 / 注册。本地 Mock 鉴权，校验方式见 [AuthService] 的文档注释。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _username = TextEditingController();
  final _password = TextEditingController();
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    app.analytics.track(Ev.pageView, {'page': 'login'});
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await app.auth.register(_username.text, _password.text);
      } else {
        await app.auth.login(_username.text, _password.text);
      }
      app.analytics.track(Ev.login, {'method': _register ? 'register' : 'password'});
      // 登录成功后由根部监听 currentUser 切换到首页。
    } on AuthException catch (e) {
      if (!mounted) return;
      unawaited(HapticFeedback.heavyImpact());
      setState(() => _error = e.message);
      _shake.forward(from: 0);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillDemo() {
    _username.text = AuthService.demoUsername;
    _password.text = AuthService.demoPassword;
    setState(() {
      _register = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    InputDecoration deco(String label, IconData icon, {Widget? suffix}) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.accent, width: 1.6),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EntranceItem(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(18)),
                      child: Icon(Icons.auto_stories_rounded, color: p.onAccent, size: 32),
                    ),
                  ),
                  const SizedBox(height: 22),
                  EntranceItem(
                    delay: const Duration(milliseconds: 60),
                    child: Text(
                      'English Reader',
                      style: TextStyle(
                        fontFamily: kReadingFont,
                        fontFamilyFallback: kReadingFontFallback,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  EntranceItem(
                    delay: const Duration(milliseconds: 120),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _register ? '创建一个本地账号' : '每天一篇，离线也能读',
                        key: ValueKey(_register),
                        style: TextStyle(fontSize: 15, color: p.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  EntranceItem(
                    delay: const Duration(milliseconds: 180),
                    // 校验失败：表单左右抖动（衰减正弦），配合一次重触感。
                    child: AnimatedBuilder(
                      animation: _shake,
                      builder: (context, child) {
                        final t = _shake.value;
                        final dx = math.sin(t * math.pi * 5) * 10 * (1 - t);
                        return Transform.translate(offset: Offset(dx, 0), child: child);
                      },
                      child: Column(
                        children: [
                          TextField(
                            controller: _username,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: deco('用户名', Icons.person_outline_rounded),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _password,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            decoration: deco(
                              '密码',
                              Icons.lock_outline_rounded,
                              suffix: IconButton(
                                icon: Icon(
                                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topLeft,
                    child: _error == null
                        ? const SizedBox(width: double.infinity, height: 14)
                        : Padding(
                            padding: const EdgeInsets.only(top: 10, left: 4, bottom: 4),
                            child: Text(_error!, style: const TextStyle(color: Color(0xFFE5484D), fontSize: 13)),
                          ),
                  ),
                  const SizedBox(height: 8),
                  EntranceItem(
                    delay: const Duration(milliseconds: 240),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        child: _busy
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                            : Text(_register ? '注册并登录' : '登录'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  EntranceItem(
                    delay: const Duration(milliseconds: 300),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _register = !_register;
                            _error = null;
                          }),
                          child: Text(_register ? '已有账号？去登录' : '没有账号？去注册'),
                        ),
                        TextButton(onPressed: _fillDemo, child: const Text('填入演示账号')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
