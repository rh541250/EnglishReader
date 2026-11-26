import 'dart:async';

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../analytics/event_schema.dart';
import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../core/ids.dart';
import '../../data/models.dart';
import '../../data/progress_repository.dart';
import '../../domain/reading_math.dart';
import '../../domain/reading_timer.dart';
import '../../domain/tokenizer.dart';
import '../../motion/app_page_route.dart';
import '../../motion/confetti.dart';
import '../../motion/entrance.dart';
import '../../motion/motion.dart';
import '../../motion/pressable.dart';
import '../../motion/progress_ring.dart';
import '../../widgets/article_cover.dart';
import 'paragraph_view.dart';
import 'reader_settings_sheet.dart';
import 'word_popup.dart';

/// 从生词本「跳回原文出处」时携带的定位。
class ReaderTarget {
  const ReaderTarget(this.paragraphIndex, this.wordIndex);
  final int paragraphIndex;
  final int wordIndex;
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.summary, required this.source, this.heroScope = 'list', this.target});

  /// 列表已经拿到的摘要：首帧就能渲染封面和标题，共享元素转场不需要等数据库。
  final ArticleSummary summary;

  /// 打开来源（埋点 article_open.source）：list / continue / vocab / next / prev。
  final String source;
  final String heroScope;
  final ReaderTarget? target;

  static Route<void> route({
    required ArticleSummary summary,
    required String source,
    String heroScope = 'list',
    ReaderTarget? target,
  }) {
    return AppPageRoute<void>(
      settings: RouteSettings(name: 'reader/${summary.id}'),
      builder: (_) => ReaderPage(summary: summary, source: source, heroScope: heroScope, target: target),
    );
  }

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  static const double _coverHeight = 250;
  static const Duration _saveThrottle = Duration(milliseconds: 800);
  static const Duration _heartbeatEvery = Duration(seconds: 5);

  final ScrollController _scroll = ScrollController();
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _contentKey = GlobalKey();
  List<GlobalKey<ParagraphViewState>> _paraKeys = [];

  /// 每个段落「槽位」（段落 + 段后间距）的 key，只用于测量。
  List<GlobalKey> _slotKeys = [];

  // ---- 数据 ----
  Article? _article;
  List<List<Token>> _tokens = const [];
  ReadingProgress? _saved;
  Set<String> _collected = {};
  ArticleSummary? _prev;
  ArticleSummary? _next;

  // ---- 进度 ----
  final ValueNotifier<double> _progress = ValueNotifier(0);
  final ValueNotifier<double> _barOpacity = ValueNotifier(0);
  final ValueNotifier<bool> _coverVisible = ValueNotifier(true);
  List<ParagraphExtent> _extents = const [];
  double _maxProgress = 0;
  bool _completed = false;
  bool _wasCompletedBefore = false;

  /// 布局已测量、位置已恢复，可以开始记录进度。在此之前任何落库都会被跳过，
  /// 否则会用「还没恢复的 0 位置」覆盖掉库里的真实位置。
  bool _ready = false;

  /// 程序性滚动（恢复位置 / 字号变化后的重新锚定）期间为 true，此时滚动不算阅读行为。
  bool _programmaticScroll = false;

  // ---- 计时 ----
  final ReadingTimer _timer = ReadingTimer();
  final String _sessionId = uuidV4();
  late final int _sessionStartedAt = _now;
  int _baseDurationMs = 0;
  int _reportedMs = 0;
  Timer? _saveTimer;
  Timer? _heartbeat;
  bool _inBackground = false;

  // ---- 取词 ----
  WordHit? _hit;
  DictEntry? _hitEntry;
  bool _pressing = false;

  // ---- 动效 ----
  late final AnimationController _bodyIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _check = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _finishCard = AnimationController.unbounded(vsync: this, value: 0);
  final ConfettiController _confetti = ConfettiController();
  int? _flashParagraph;
  int? _flashWord;
  int _streak = 0;
  Timer? _finishCardTimer;
  String? _toast;
  Timer? _toastTimer;

  int get _now => DateTime.now().millisecondsSinceEpoch;
  ArticleSummary get _s => widget.summary;
  String get _coverTag => coverHeroTag(widget.heroScope, _s.id);
  String get _titleTag => titleHeroTag(widget.heroScope, _s.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    app.settings.addListener(_onSettingsChanged);
    app.vocab.revision.addListener(_reloadCollected);
    _load();
  }

  @override
  void dispose() {
    _leaveSegment('exit');
    WidgetsBinding.instance.removeObserver(this);
    app.settings.removeListener(_onSettingsChanged);
    app.vocab.revision.removeListener(_reloadCollected);
    _saveTimer?.cancel();
    _heartbeat?.cancel();
    _finishCardTimer?.cancel();
    _toastTimer?.cancel();
    _scroll.dispose();
    _bodyIn.dispose();
    _flash.dispose();
    _check.dispose();
    _finishCard.dispose();
    _confetti.dispose();
    _progress.dispose();
    _barOpacity.dispose();
    _coverVisible.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // 加载与位置恢复
  // ------------------------------------------------------------------

  Future<void> _load() async {
    final uid = app.userId;
    final results = await Future.wait<Object?>([
      app.articles.getById(_s.id, userId: uid),
      app.progress.get(uid, _s.id),
      app.vocab.collectedWords(uid),
      app.articles.previousOf(_s),
      app.articles.nextOf(_s),
    ]);
    if (!mounted) return;
    final article = results[0] as Article?;
    if (article == null) return;
    final saved = results[1] as ReadingProgress?;

    setState(() {
      _article = article;
      _tokens = [for (final p in article.paragraphs) tokenize(p)];
      _paraKeys = List.generate(article.paragraphs.length, (_) => GlobalKey<ParagraphViewState>());
      _slotKeys = List.generate(article.paragraphs.length, (_) => GlobalKey());
      _saved = saved;
      _collected = results[2] as Set<String>;
      _prev = results[3] as ArticleSummary?;
      _next = results[4] as ArticleSummary?;
      _baseDurationMs = saved?.durationMs ?? 0;
      _maxProgress = saved?.maxProgress ?? 0;
      _wasCompletedBefore = saved?.completed ?? false;
      _completed = _wasCompletedBefore;
    });
    if (_completed) _check.value = 1;

    app.analytics.track(Ev.pageView, {'page': 'reader', 'from': widget.source, 'article_id': _s.id});
    app.analytics.track(Ev.articleOpen, {
      'article_id': _s.id,
      'source': widget.source,
      'category': _s.category.key,
      'difficulty': _s.difficulty,
      'resume_progress': saved == null ? 0 : (saved.progress * 100).round(),
    });
    if (!app.network.isOnline) {
      app.analytics.track(Ev.offlineHit, {'resource': 'article', 'article_id': _s.id});
    }

    _timer.resume(_now);
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) => _save());

    // 正文首屏入场：等转场走过一小段再开始，避免和封面飞行抢视线。
    Future<void>.delayed(const Duration(milliseconds: 160), () {
      if (mounted) _bodyIn.forward();
    });

    // 等首帧布局完成后测量段落，再等转场结束后恢复位置。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
      _whenTransitionDone(_restore);
    });
  }

  void _whenTransitionDone(VoidCallback action) {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      action();
      return;
    }
    late AnimationStatusListener listener;
    listener = (status) {
      if (status == AnimationStatus.completed) {
        animation.removeStatusListener(listener);
        if (mounted) action();
      } else if (status == AnimationStatus.dismissed) {
        animation.removeStatusListener(listener);
      }
    };
    animation.addStatusListener(listener);
  }

  /// 阅读线到视口顶部的距离：状态栏 + 顶栏下沿。
  double get _anchorInset => MediaQuery.paddingOf(context).top + kToolbarHeight + 8;

  /// 测量每个段落槽位在滚动内容坐标系中的位置。
  ///
  /// 量的是槽位（Padding）而不是段落本身，有两个原因：
  /// 1. 段落外面包着入场动效的 Transform，`localToGlobal` 会把动画位移算进去，
  ///    在入场途中测量会整体偏 18px；槽位在 Transform 之外，拿到的是纯布局位置。
  /// 2. 槽位包含段后间距，相邻槽位首尾相接，阅读线落在段间距里也能无损往返换算。
  void _measure() {
    final content = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (content == null) return;
    final extents = <ParagraphExtent>[];
    for (final key in _slotKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      extents.add(ParagraphExtent(box.localToGlobal(Offset.zero, ancestor: content).dy, box.size.height));
    }
    _extents = extents;
  }

  ReadingPosition get _currentPosition => positionForAnchor(_extents, _scroll.position.pixels + _anchorInset);

  double _offsetFor(ReadingPosition p) {
    final raw = anchorForPosition(_extents, p) - _anchorInset;
    return raw.clamp(0.0, _scroll.position.maxScrollExtent);
  }

  Future<void> _restore() async {
    if (!_scroll.hasClients) return;
    final target = widget.target;
    final saved = _saved;

    if (target != null) {
      await _jumpToTarget(target);
    } else if (saved != null && saved.progress < kFinishThreshold) {
      // 上次读完了就从头开始重读；否则回到上次的位置。
      final offset = _offsetFor(saved.position);
      if (offset > 8) {
        _programmaticScroll = true;
        await _scroll.animateTo(offset, duration: const Duration(milliseconds: 520), curve: Motion.standard);
        // 动画曲线的末值可能有亚像素误差，最后用 jumpTo 精确落到目标偏移。
        if (mounted && _scroll.hasClients) _scroll.jumpTo(offset);
        _programmaticScroll = false;
        if (mounted) _showToast('已回到上次阅读位置 · ${(saved.progress * 100).round()}%');
      }
    }
    if (!mounted) return;
    _ready = true;
    _onScroll();

    // 内容不足一屏（无法滚动）时，停留 3 秒视为读完。
    if (_scroll.position.maxScrollExtent <= 0 && !_completed) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted && !_completed) _onFinished();
      });
    }
  }

  Future<void> _jumpToTarget(ReaderTarget target) async {
    if (target.paragraphIndex >= _paraKeys.length) return;
    final rect = _paraKeys[target.paragraphIndex].currentState?.globalRectOfWord(target.wordIndex);
    if (rect == null) return;
    final viewport = MediaQuery.sizeOf(context).height;
    final offset = (_scroll.position.pixels + rect.center.dy - viewport * 0.38).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _programmaticScroll = true;
    await _scroll.animateTo(offset, duration: const Duration(milliseconds: 560), curve: Motion.standard);
    _programmaticScroll = false;
    if (!mounted) return;
    setState(() {
      _flashParagraph = target.paragraphIndex;
      _flashWord = target.wordIndex;
    });
    // 闪三下，然后保持熄灭。
    for (var i = 0; i < 3 && mounted; i++) {
      await _flash.forward(from: 0);
      if (!mounted) return;
      await _flash.reverse();
    }
    if (mounted) setState(() => _flashParagraph = _flashWord = null);
  }

  /// 字号 / 行距变化：记下当前读到哪句话 → 重排 → 重新测量 → 滚回同一句话。
  void _onSettingsChanged() {
    if (!_ready || !_scroll.hasClients || _extents.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    final position = _currentPosition;
    _dismissPopup();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _measure();
      _programmaticScroll = true;
      _scroll.jumpTo(_offsetFor(position));
      _programmaticScroll = false;
    });
  }

  // ------------------------------------------------------------------
  // 滚动 → 进度 → 落库
  // ------------------------------------------------------------------

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final pixels = pos.pixels;
    _progress.value = scrollProgress(pixels, pos.maxScrollExtent);
    final barStart = _coverHeight - _anchorInset - 24;
    _barOpacity.value = ((pixels - barStart) / 36).clamp(0.0, 1.0);
    _coverVisible.value = pixels < _coverHeight * 0.6;

    if (!_ready || _programmaticScroll) return;
    _timer.interact(_now);
    if (_hit != null && !_pressing) _dismissPopup();

    final p = _progress.value;
    if (p > _maxProgress) {
      for (final depth in crossedMilestones(_maxProgress, p)) {
        app.analytics.track(Ev.readProgress, {'article_id': _s.id, 'depth': depth});
      }
      _maxProgress = p;
    }
    if (!_completed && isFinished(p)) _onFinished();
    _scheduleSave();
  }

  /// 节流：滚动期间最多每 800ms 落库一次。
  void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(_saveThrottle, _save);
  }

  Future<void> _save() async {
    if (!_ready || !_scroll.hasClients || _extents.isEmpty) return;
    final now = _now;
    final elapsed = _timer.elapsedMs(now);
    try {
      await app.progress.save(
        ProgressSnapshot(
          userId: app.userId,
          articleId: _s.id,
          position: _currentPosition,
          progress: _progress.value,
          completed: _completed,
          totalDurationMs: _baseDurationMs + elapsed,
          sessionId: _sessionId,
          sessionStartedAt: _sessionStartedAt,
          sessionDurationMs: elapsed,
          nowMs: now,
        ),
      );
    } catch (e) {
      debugPrint('[reader] save failed: $e');
    }
  }

  /// 一段阅读结束（离开页面 / 切后台）：停表、立即落库、上报本段时长。
  void _leaveSegment(String reason) {
    final now = _now;
    _timer.pause(now);
    _saveTimer?.cancel();
    _save();
    final elapsed = _timer.elapsedMs(now);
    final delta = elapsed - _reportedMs;
    if (delta >= 1000) {
      _reportedMs = elapsed;
      app.analytics.track(Ev.readDuration, {
        'article_id': _s.id,
        'duration_ms': delta,
        'max_depth': (_maxProgress * 100).round(),
        'reason': reason,
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (!_inBackground) {
          _inBackground = true;
          _leaveSegment('background');
        }
      case AppLifecycleState.resumed:
        if (_inBackground) {
          _inBackground = false;
          _timer.resume(_now);
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  // ------------------------------------------------------------------
  // 读完
  // ------------------------------------------------------------------

  Future<void> _onFinished() async {
    _completed = true;
    _check.forward();
    setState(() {});
    final first = !_wasCompletedBefore;
    _wasCompletedBefore = true;
    _saveTimer?.cancel();
    await _save();
    if (!mounted || !first) return;

    final stats = await app.progress.stats(app.userId);
    if (!mounted) return;
    _streak = stats.streakDays;
    app.analytics.track(Ev.articleFinish, {
      'article_id': _s.id,
      'total_duration_ms': _baseDurationMs + _timer.elapsedMs(_now),
      'streak_days': _streak,
      'category': _s.category.key,
      'difficulty': _s.difficulty,
    });

    unawaited(HapticFeedback.heavyImpact());
    _confetti.fire();
    setState(() {});
    _finishCard.animateWith(SpringSimulation(Motion.bouncy, _finishCard.value, 1, 0));
    _finishCardTimer?.cancel();
    _finishCardTimer = Timer(const Duration(milliseconds: 5200), _hideFinishCard);
  }

  void _hideFinishCard() {
    _finishCardTimer?.cancel();
    if (!mounted) return;
    _finishCard.animateTo(0, duration: const Duration(milliseconds: 260), curve: Motion.exit);
  }

  // ------------------------------------------------------------------
  // 取词与收藏
  // ------------------------------------------------------------------

  void _onWordHit(WordHit hit) {
    setState(() {
      _pressing = true;
      _hit = hit;
      _hitEntry = app.dictionary.lookup(hit.token.text);
    });
  }

  void _onLongPressEnd() {
    _pressing = false;
    final hit = _hit, entry = _hitEntry;
    if (hit == null || entry == null) return;
    app.analytics.track(Ev.wordLookup, {
      'article_id': _s.id,
      'word': entry.word,
      'found': entry.found,
      'paragraph_index': hit.paragraphIndex,
    });
  }

  void _dismissPopup() {
    if (_hit == null) return;
    setState(() => _hit = _hitEntry = null);
  }

  Future<void> _toggleCollect(bool collect) async {
    final hit = _hit, entry = _hitEntry, article = _article;
    if (hit == null || entry == null || article == null) return;
    final uid = app.userId;
    // 先改内存里的集合让界面立刻响应，再落库。
    setState(() {
      _collected = collect ? {..._collected, entry.word} : ({..._collected}..remove(entry.word));
    });
    if (collect) {
      await app.vocab.add(
        userId: uid,
        entry: entry,
        display: hit.token.text,
        articleId: _s.id,
        paragraphIndex: hit.paragraphIndex,
        wordIndex: hit.token.wordIndex,
        context: _sentenceAround(article.paragraphs[hit.paragraphIndex], hit.token),
      );
      app.analytics.track(Ev.wordCollect, {
        'article_id': _s.id,
        'word': entry.word,
        'paragraph_index': hit.paragraphIndex,
        'source': 'reader',
      });
    } else {
      await app.vocab.remove(uid, entry.word);
      app.analytics.track(Ev.wordRemove, {'word': entry.word, 'source': 'reader', 'article_id': _s.id});
    }
  }

  Future<void> _reloadCollected() async {
    final words = await app.vocab.collectedWords(app.userId);
    if (!mounted) return;
    if (words.length == _collected.length && words.containsAll(_collected)) return;
    setState(() => _collected = words);
  }

  /// 取单词所在的那一句作为生词本里的例句。
  static String _sentenceAround(String paragraph, Token token) {
    var start = token.start;
    while (start > 0 && !'.!?'.contains(paragraph[start - 1])) {
      start--;
    }
    var end = token.end;
    while (end < paragraph.length && !'.!?'.contains(paragraph[end])) {
      end++;
    }
    if (end < paragraph.length) end++;
    return paragraph.substring(start, end).trim();
  }

  // ------------------------------------------------------------------
  // 其它交互
  // ------------------------------------------------------------------

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _share() async {
    await Clipboard.setData(ClipboardData(text: '${_s.title}\n${_s.summary}\n— 来自 English Reader'));
    app.analytics.track(Ev.articleShare, {'article_id': _s.id, 'channel': 'clipboard'});
    if (mounted) _showToast('分享文案已复制到剪贴板');
  }

  void _openSibling(ArticleSummary target, String source) {
    Navigator.of(context).pushReplacement(ReaderPage.route(summary: target, source: source));
  }

  // ------------------------------------------------------------------
  // 构建
  // ------------------------------------------------------------------

  /// 正文首屏入场：第 [i] 个区块延迟 i×70ms，淡入 + 上移 18px。
  Widget _enter(int i, Widget child) {
    return AnimatedBuilder(
      animation: _bodyIn,
      child: child,
      builder: (context, child) {
        final t = Motion.enter.transform(((_bodyIn.value * 620 - i * 70) / 340).clamp(0.0, 1.0));
        if (t >= 1) return child!;
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settings = app.settings;
    final media = MediaQuery.of(context);
    final article = _article;

    final bodyStyle = TextStyle(
      fontFamily: kReadingFont,
      fontFamilyFallback: kReadingFontFallback,
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      color: p.text,
      letterSpacing: 0.1,
    );
    final paragraphGap = settings.fontSize * settings.lineHeight * 0.85;

    final content = Column(
      key: _contentKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _coverHeight,
          width: double.infinity,
          child: ValueListenableBuilder<bool>(
            valueListenable: _coverVisible,
            builder: (context, visible, _) => CoverHero(
              tag: _coverTag,
              articleId: _s.id,
              category: _s.category,
              radius: 0,
              // 封面滚出屏幕后关闭共享元素：否则返回时封面会从屏幕外飞回卡片。
              enabled: visible,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _enter(
                0,
                Row(
                  children: [
                    _Chip(text: _s.category.label, color: p.accent),
                    const SizedBox(width: 8),
                    _Chip(text: kDifficultyLabels[_s.difficulty] ?? '', color: p.textSecondary),
                    const SizedBox(width: 10),
                    Text(
                      '${_s.wordCount} 词 · 约 ${_s.minutes} 分钟',
                      style: TextStyle(fontSize: 12.5, color: p.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ValueListenableBuilder<bool>(
                valueListenable: _coverVisible,
                builder: (context, visible, child) =>
                    TitleHero(tag: _titleTag, isDetail: true, enabled: visible, child: child!),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    _s.title,
                    style: TextStyle(
                      fontFamily: kReadingFont,
                      fontFamilyFallback: kReadingFontFallback,
                      fontSize: 27,
                      height: 1.22,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _enter(1, Text(_s.titleZh, style: TextStyle(fontSize: 15, color: p.textSecondary, height: 1.4))),
              const SizedBox(height: 12),
              _enter(
                2,
                Text('${_s.author} · ${_s.publishedAt}', style: TextStyle(fontSize: 12.5, color: p.textTertiary)),
              ),
              const SizedBox(height: 18),
              _enter(2, Divider(height: 1, color: p.divider)),
              const SizedBox(height: 22),
              if (article != null)
                for (var i = 0; i < article.paragraphs.length; i++)
                  Padding(
                    key: _slotKeys[i],
                    padding: EdgeInsets.only(bottom: paragraphGap),
                    child: _enter(
                      3 + i.clamp(0, 4),
                      ParagraphView(
                        key: _paraKeys[i],
                        index: i,
                        text: article.paragraphs[i],
                        tokens: _tokens[i],
                        style: bodyStyle,
                        collected: _collected,
                        lemmaOf: app.dictionary.lemmaOf,
                        collectedColor: p.accent,
                        highlightColor: p.highlight,
                        activeWordIndex: _hit?.paragraphIndex == i ? _hit!.token.wordIndex : null,
                        flash: _flash,
                        flashWordIndex: _flashParagraph == i ? _flashWord : null,
                        onWordHit: _onWordHit,
                        onLongPressEnd: _onLongPressEnd,
                      ),
                    ),
                  ),
              if (article != null) ...[
                const SizedBox(height: 4),
                _FinishFooter(completed: _completed),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _SiblingCard(
                        label: '上一篇',
                        article: _prev,
                        alignEnd: false,
                        onTap: _prev == null ? null : () => _openSibling(_prev!, 'prev'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SiblingCard(
                        label: '下一篇',
                        article: _next,
                        alignEnd: true,
                        onTap: _next == null ? null : () => _openSibling(_next!, 'next'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: media.padding.bottom + 48),
      ],
    );

    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final hit = _hit;
    final hitEntry = _hitEntry;

    return Scaffold(
      backgroundColor: p.background,
      body: Stack(
        key: _stackKey,
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              child: content,
            ),
          ),

          // 顶栏 + 进度条
          Positioned(top: 0, left: 0, right: 0, child: _buildTopBar(p, media)),

          // 轻提示
          Positioned(
            left: 0,
            right: 0,
            top: media.padding.top + kToolbarHeight + 14,
            child: IgnorePointer(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, -0.5), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: _toast == null
                      ? const SizedBox.shrink()
                      : Container(
                          key: ValueKey(_toast),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: p.text.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _toast!,
                            style: TextStyle(fontSize: 13, color: p.background, fontWeight: FontWeight.w600),
                          ),
                        ),
                ),
              ),
            ),
          ),

          // 取词气泡：点空白处关闭
          if (hit != null && hitEntry != null && stackBox != null) ...[
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _dismissPopup),
            ),
            Positioned.fill(
              child: WordPopup(
                key: ValueKey('${hit.paragraphIndex}:${hit.token.wordIndex}'),
                anchor: stackBox.globalToLocal(hit.globalRect.topLeft) & hit.globalRect.size,
                topInset: media.padding.top + kToolbarHeight,
                display: hit.token.text,
                entry: hitEntry,
                collected: _collected.contains(hitEntry.word),
                onToggleCollect: _toggleCollect,
              ),
            ),
          ],

          // 读完庆祝卡片
          Positioned(
            left: 16,
            right: 16,
            bottom: media.padding.bottom + 16,
            child: AnimatedBuilder(
              animation: _finishCard,
              builder: (context, child) {
                final v = _finishCard.value;
                if (v <= 0.001) return const SizedBox.shrink();
                return Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.translate(offset: Offset(0, 140 * (1 - v)), child: child),
                );
              },
              child: _FinishCard(
                streak: _streak,
                minutes: ((_baseDurationMs + _timer.elapsedMs(_now)) / 60000).ceil(),
                onClose: _hideFinishCard,
              ),
            ),
          ),

          // 彩纸在最上层
          Positioned.fill(child: ConfettiOverlay(controller: _confetti)),
        ],
      ),
    );
  }

  Widget _buildTopBar(AppPalette p, MediaQueryData media) {
    return AnimatedBuilder(
      animation: Listenable.merge([_barOpacity, _progress, _check]),
      builder: (context, _) {
        final o = _barOpacity.value;
        // 顶栏压在封面上时用白色图标 + 半透明深色底，滚过封面后过渡到主题色。
        final fg = Color.lerp(Colors.white, p.text, o)!;
        final buttonBg = Colors.black.withValues(alpha: 0.26 * (1 - o));
        final progress = _completed ? 1.0 : _progress.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.only(top: media.padding.top, left: 6, right: 6),
              height: media.padding.top + kToolbarHeight,
              decoration: BoxDecoration(
                color: p.background.withValues(alpha: o),
                border: Border(
                  bottom: BorderSide(color: p.divider.withValues(alpha: p.divider.a * o)),
                ),
              ),
              child: Row(
                children: [
                  _BarButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    color: fg,
                    background: buttonBg,
                    onTap: () => Navigator.of(context).maybePop(),
                    tooltip: '返回',
                  ),
                  Expanded(
                    child: Opacity(
                      opacity: o,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          _s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text),
                        ),
                      ),
                    ),
                  ),
                  // 进度环：滚动位置直接驱动，读完后闭合并描出对勾。
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: buttonBg, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CustomPaint(
                        painter: ProgressRingPainter(
                          progress: progress,
                          color: Color.lerp(Colors.white, p.accent, o)!,
                          trackColor: fg.withValues(alpha: 0.22),
                          strokeWidth: 2.8,
                          checkT: Curves.easeOutCubic.transform(_check.value),
                          checkColor: Color.lerp(Colors.white, p.success, o),
                        ),
                        child: _check.value > 0
                            ? null
                            : Center(
                                child: Text(
                                  '${(progress * 100).round()}',
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: fg),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _BarButton(
                    icon: Icons.text_fields_rounded,
                    color: fg,
                    background: buttonBg,
                    onTap: () => ReaderSettingsSheet.show(context),
                    tooltip: '阅读设置',
                  ),
                  const SizedBox(width: 6),
                  _BarButton(
                    icon: Icons.ios_share_rounded,
                    color: fg,
                    background: buttonBg,
                    onTap: _share,
                    tooltip: '分享',
                  ),
                ],
              ),
            ),
            // 底部进度条：宽度 = 滚动进度，逐帧跟随滚动，没有额外补间所以不会「滞后」。
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: _completed ? p.success : p.accent,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Pressable(
        pressedScale: 0.88,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Icon(icon, size: 19, color: color),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _FinishFooter extends StatelessWidget {
  const _FinishFooter({required this.completed});
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        child: Row(
          key: ValueKey(completed),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              completed ? Icons.check_circle_rounded : Icons.more_horiz_rounded,
              size: 18,
              color: completed ? p.success : p.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              completed ? '已读完' : '读到这里就完成啦',
              style: TextStyle(
                fontSize: 13,
                color: completed ? p.success : p.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SiblingCard extends StatelessWidget {
  const _SiblingCard({required this.label, required this.article, required this.alignEnd, required this.onTap});
  final String label;
  final ArticleSummary? article;
  final bool alignEnd;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: article == null ? 0.45 : 1,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.divider),
          ),
          child: Column(
            crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: p.textTertiary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  article?.title ?? '没有了',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                  style: TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w700, color: p.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 读完庆祝卡片：连续打卡天数数字滚动。
class _FinishCard extends StatelessWidget {
  const _FinishCard({required this.streak, required this.minutes, required this.onClose});
  final int streak;
  final int minutes;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onClose,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.divider),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 32, offset: const Offset(0, 12)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: const Color(0xFFFF8A3D).withValues(alpha: 0.16), shape: BoxShape.circle),
              child: const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF7A1A), size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '读完啦！',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('连续打卡 ', style: TextStyle(fontSize: 13.5, color: p.textSecondary)),
                      // key 带上天数：数值到位后重建一次，数字从 0 滚到目标值。
                      CountUp(
                        key: ValueKey(streak),
                        value: streak,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFFF7A1A)),
                      ),
                      Text(' 天 · 本文累计 $minutes 分钟', style: TextStyle(fontSize: 13.5, color: p.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.close_rounded, size: 18, color: p.textTertiary),
          ],
        ),
      ),
    );
  }
}
