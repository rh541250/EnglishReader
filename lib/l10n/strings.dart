import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app/theme.dart';
import '../data/auth_service.dart' show AuthError;
import '../data/models.dart';

/// 界面语言设置。[system] 跟随系统：系统语言是中文时用中文，其余一律用英文。
enum AppLanguage {
  system('system'),
  zh('zh'),
  en('en');

  const AppLanguage(this.key);
  final String key;

  /// 传给 MaterialApp.locale；跟随系统时为 null。
  Locale? get locale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.zh => const Locale('zh'),
    AppLanguage.en => const Locale('en'),
  };

  static AppLanguage fromKey(String? key) => values.firstWhere((l) => l.key == key, orElse: () => AppLanguage.system);
}

const List<Locale> kSupportedLocales = [Locale('zh'), Locale('en')];

/// 把系统 / 用户选择的语言归一到支持的两种之一。
Locale resolveAppLocale(Locale? locale) => locale?.languageCode == 'zh' ? const Locale('zh') : const Locale('en');

/// 与「今天」相差的自然日数（按本地日期计算，不受时分影响）。
int daysBefore(DateTime date, DateTime now) {
  final a = DateTime(date.year, date.month, date.day);
  final b = DateTime(now.year, now.month, now.day);
  return b.difference(a).inHours ~/ 24;
}

/// 界面文案。
///
/// 没有用 ARB + 代码生成：文案量不大，手写一个抽象类、两份实现，
/// 任何一种语言漏写条目都会直接编译失败，比运行时缺 key 更早暴露问题。
/// 只翻译界面文字；文章正文、中文标题与释义属于学习内容，不随语言切换。
abstract class S {
  const S();

  static S of(BuildContext context) => Localizations.of<S>(context, S)!;

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  static S forLocale(Locale locale) => resolveAppLocale(locale).languageCode == 'zh' ? const SZh() : const SEn();

  // ---- 通用 ----
  String get undo;
  String get cancel;
  String category(ArticleCategory c);
  String difficulty(int level);
  String themeName(ReaderTheme t);
  String languageName(AppLanguage l);
  String minutes(int n);

  /// 列表卡片上的发布时间：7 天内用相对时间，更早的显示日期。
  String publishDate(DateTime date, DateTime now) {
    final d = daysBefore(date, now);
    if (d >= 0 && d < 7) return relativeDays(d);
    return shortDate(date, now);
  }

  String relativeDays(int days);
  String shortDate(DateTime date, DateTime now);
  String fullDate(DateTime date);

  // ---- 登录 ----
  String get loginTagline;
  String get registerTagline;
  String get username;
  String get password;
  String get login;
  String get registerAndLogin;
  String get toRegister;
  String get toLogin;
  String get fillDemo;
  String authError(AuthError e);

  // ---- 底部导航 ----
  String get tabRead;
  String get tabNotebook;
  String get tabMe;

  // ---- 文章列表 ----
  String greeting(String name) => 'Hi, $name';
  String get homeTitle;
  String get searchHint;
  String get allCategories;
  String get allLevels;
  String get emptyFilter;
  String get listEnd;
  String streakChip(int days);
  String get continueReading;

  // ---- 搜索 ----
  String get searchHistory;
  String get clearHistory;
  String resultCount(int n);
  String get noResults;
  String get noResultsHint;

  // ---- 阅读页 ----
  String restoredPosition(int percent);
  String shareText(String title, String summary) => '$title\n$summary\n— English Reader';
  String get shareCopied;
  String wordsAndMinutes(int words, int minutes);
  String get previousArticle;
  String get nextArticle;
  String get noMore;
  String get back;
  String get readerSettings;
  String get share;
  String get favoriteArticle;
  String get favoritedToast;
  String get unfavoritedToast;
  String get finished;
  String get finishHint;
  String get finishTitle;
  String get streakPrefix;
  String streakSuffix(int minutes);
  String get fontSize;
  String get lineHeight;
  String get theme;

  // ---- 取词气泡 ----
  String get notInDictionary;
  String get collectWord;
  String get uncollectWord;
  String get markSentence;
  String get unmarkSentence;
  String get sentenceMarkedToast;

  // ---- 笔记 ----
  String get notebookTitle;
  String notebookWords(int n);
  String notebookSentences(int n);
  String deleted(String text);
  String get emptyWordsTitle;
  String get emptyWordsHint;
  String get emptySentencesTitle;
  String get emptySentencesHint;
  String source(String title);

  // ---- 收藏的文章 ----
  String get favoritesTitle;
  String favoritedAt(String date);
  String get emptyFavoritesTitle;
  String get emptyFavoritesHint;

  // ---- 我的 ----
  String get localAccount;
  String get statStreak;
  String get statFinished;
  String get statTotal;
  String get statNotes;
  String get unitDays;
  String get unitArticles;
  String get unitMinutes;
  String get unitItems;
  String get weekChartTitle;
  String todayMinutes(String m);
  String get today;
  String get language;
  String get debugPanel;
  String get debugPanelSubtitle;
  String get logout;
  String get logoutSubtitle;
}

class SZh extends S {
  const SZh();

  @override
  String get undo => '撤销';
  @override
  String get cancel => '取消';
  @override
  String category(ArticleCategory c) => switch (c) {
    ArticleCategory.tech => '科技',
    ArticleCategory.business => '商业',
    ArticleCategory.culture => '文化',
    ArticleCategory.daily => '日常',
  };
  @override
  String difficulty(int level) => switch (level) {
    1 => '初级',
    2 => '中级',
    _ => '高级',
  };
  @override
  String themeName(ReaderTheme t) => switch (t) {
    ReaderTheme.light => '日间',
    ReaderTheme.sepia => '护眼',
    ReaderTheme.dark => '夜间',
  };
  @override
  String languageName(AppLanguage l) => switch (l) {
    AppLanguage.system => '跟随系统',
    AppLanguage.zh => '简体中文',
    AppLanguage.en => 'English',
  };
  @override
  String minutes(int n) => '$n 分钟';
  @override
  String relativeDays(int days) => switch (days) {
    0 => '今天',
    1 => '昨天',
    _ => '$days 天前',
  };
  @override
  String shortDate(DateTime date, DateTime now) =>
      date.year == now.year ? '${date.month}月${date.day}日' : fullDate(date);
  @override
  String fullDate(DateTime date) => '${date.year}年${date.month}月${date.day}日';

  @override
  String get loginTagline => '每天一篇，离线也能读';
  @override
  String get registerTagline => '创建一个本地账号';
  @override
  String get username => '用户名';
  @override
  String get password => '密码';
  @override
  String get login => '登录';
  @override
  String get registerAndLogin => '注册并登录';
  @override
  String get toRegister => '没有账号？去注册';
  @override
  String get toLogin => '已有账号？去登录';
  @override
  String get fillDemo => '填入演示账号';
  @override
  String authError(AuthError e) => switch (e) {
    AuthError.invalidUsername => '用户名需为 3-20 位字母、数字或下划线',
    AuthError.passwordTooShort => '密码至少 6 位',
    AuthError.usernameTaken => '该用户名已被注册',
    AuthError.wrongCredentials => '账号或密码错误',
  };

  @override
  String get tabRead => '阅读';
  @override
  String get tabNotebook => '笔记';
  @override
  String get tabMe => '我的';

  @override
  String get homeTitle => '今天读点什么？';
  @override
  String get searchHint => '搜索标题、正文关键词';
  @override
  String get allCategories => '全部';
  @override
  String get allLevels => '全部难度';
  @override
  String get emptyFilter => '这个筛选条件下还没有文章';
  @override
  String get listEnd => '— 已经到底啦 —';
  @override
  String streakChip(int days) => '$days 天';
  @override
  String get continueReading => '继续阅读';

  @override
  String get searchHistory => '搜索历史';
  @override
  String get clearHistory => '清空';
  @override
  String resultCount(int n) => '找到 $n 篇文章';
  @override
  String get noResults => '没有找到相关文章';
  @override
  String get noResultsHint => '换个关键词试试，支持空格分隔多个词';

  @override
  String restoredPosition(int percent) => '已回到上次阅读位置 · $percent%';
  @override
  String get shareCopied => '分享文案已复制到剪贴板';
  @override
  String wordsAndMinutes(int words, int minutes) => '$words 词 · 约 $minutes 分钟';
  @override
  String get previousArticle => '上一篇';
  @override
  String get nextArticle => '下一篇';
  @override
  String get noMore => '没有了';
  @override
  String get back => '返回';
  @override
  String get readerSettings => '阅读设置';
  @override
  String get share => '分享';
  @override
  String get favoriteArticle => '收藏文章';
  @override
  String get favoritedToast => '已收藏，可在「我的」中查看';
  @override
  String get unfavoritedToast => '已取消收藏';
  @override
  String get finished => '已读完';
  @override
  String get finishHint => '读到这里就完成啦';
  @override
  String get finishTitle => '读完啦！';
  @override
  String get streakPrefix => '连续打卡 ';
  @override
  String streakSuffix(int minutes) => ' 天 · 本文累计 $minutes 分钟';
  @override
  String get fontSize => '字号';
  @override
  String get lineHeight => '行距';
  @override
  String get theme => '主题';

  @override
  String get notInDictionary => 'Mock 词表暂未收录该词';
  @override
  String get collectWord => '收藏单词';
  @override
  String get uncollectWord => '取消收藏单词';
  @override
  String get markSentence => '划线本句';
  @override
  String get unmarkSentence => '取消划线';
  @override
  String get sentenceMarkedToast => '已划线，可在「笔记」中查看';

  @override
  String get notebookTitle => '笔记';
  @override
  String notebookWords(int n) => '单词 $n';
  @override
  String notebookSentences(int n) => '句子 $n';
  @override
  String deleted(String text) => '已删除「$text」';
  @override
  String get emptyWordsTitle => '还没有生词';
  @override
  String get emptyWordsHint => '阅读时长按任意单词即可取词收藏';
  @override
  String get emptySentencesTitle => '还没有划线的句子';
  @override
  String get emptySentencesHint => '长按句子里的任意单词，点「划线本句」';
  @override
  String source(String title) => '原文：$title';

  @override
  String get favoritesTitle => '收藏的文章';
  @override
  String favoritedAt(String date) => '收藏于 $date';
  @override
  String get emptyFavoritesTitle => '还没有收藏的文章';
  @override
  String get emptyFavoritesHint => '阅读时点右上角的书签即可收藏';

  @override
  String get localAccount => '本地账号 · 数据仅保存在这台设备';
  @override
  String get statStreak => '连续打卡';
  @override
  String get statFinished => '读完文章';
  @override
  String get statTotal => '累计阅读';
  @override
  String get statNotes => '笔记';
  @override
  String get unitDays => ' 天';
  @override
  String get unitArticles => ' 篇';
  @override
  String get unitMinutes => ' 分钟';
  @override
  String get unitItems => ' 条';
  @override
  String get weekChartTitle => '近 7 日阅读时长';
  @override
  String todayMinutes(String m) => '今日 $m 分钟';
  @override
  String get today => '今天';
  @override
  String get language => '语言';
  @override
  String get debugPanel => '埋点与性能调试面板';
  @override
  String get debugPanelSubtitle => '事件队列 · 上报结果 · 分析查询 · 帧耗时';
  @override
  String get logout => '退出登录';
  @override
  String get logoutSubtitle => '吊销本地 Token，阅读数据保留';
}

class SEn extends S {
  const SEn();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _plural(int n, String one, String many) => n == 1 ? '$n $one' : '$n $many';

  @override
  String get undo => 'Undo';
  @override
  String get cancel => 'Cancel';
  @override
  String category(ArticleCategory c) => switch (c) {
    ArticleCategory.tech => 'Tech',
    ArticleCategory.business => 'Business',
    ArticleCategory.culture => 'Culture',
    ArticleCategory.daily => 'Daily',
  };
  @override
  String difficulty(int level) => switch (level) {
    1 => 'Easy',
    2 => 'Medium',
    _ => 'Hard',
  };
  @override
  String themeName(ReaderTheme t) => switch (t) {
    ReaderTheme.light => 'Light',
    ReaderTheme.sepia => 'Sepia',
    ReaderTheme.dark => 'Dark',
  };
  @override
  String languageName(AppLanguage l) => switch (l) {
    AppLanguage.system => 'System',
    AppLanguage.zh => '简体中文',
    AppLanguage.en => 'English',
  };
  @override
  String minutes(int n) => '$n min';
  @override
  String relativeDays(int days) => switch (days) {
    0 => 'Today',
    1 => 'Yesterday',
    _ => '$days days ago',
  };
  @override
  String shortDate(DateTime date, DateTime now) =>
      date.year == now.year ? '${_months[date.month - 1]} ${date.day}' : fullDate(date);
  @override
  String fullDate(DateTime date) => '${_months[date.month - 1]} ${date.day}, ${date.year}';

  @override
  String get loginTagline => 'One article a day, even offline';
  @override
  String get registerTagline => 'Create a local account';
  @override
  String get username => 'Username';
  @override
  String get password => 'Password';
  @override
  String get login => 'Log in';
  @override
  String get registerAndLogin => 'Sign up';
  @override
  String get toRegister => 'No account? Sign up';
  @override
  String get toLogin => 'Have an account? Log in';
  @override
  String get fillDemo => 'Use demo account';
  @override
  String authError(AuthError e) => switch (e) {
    AuthError.invalidUsername => 'Username must be 3-20 letters, digits or underscores',
    AuthError.passwordTooShort => 'Password must be at least 6 characters',
    AuthError.usernameTaken => 'This username is already taken',
    AuthError.wrongCredentials => 'Wrong username or password',
  };

  @override
  String get tabRead => 'Read';
  @override
  String get tabNotebook => 'Notebook';
  @override
  String get tabMe => 'Me';

  @override
  String get homeTitle => 'What to read today?';
  @override
  String get searchHint => 'Search titles and full text';
  @override
  String get allCategories => 'All';
  @override
  String get allLevels => 'All levels';
  @override
  String get emptyFilter => 'No articles match these filters';
  @override
  String get listEnd => '— You have reached the end —';
  @override
  String streakChip(int days) => _plural(days, 'day', 'days');
  @override
  String get continueReading => 'Continue reading';

  @override
  String get searchHistory => 'Recent searches';
  @override
  String get clearHistory => 'Clear';
  @override
  String resultCount(int n) => _plural(n, 'article', 'articles');
  @override
  String get noResults => 'No matching articles';
  @override
  String get noResultsHint => 'Try other keywords; separate words with spaces';

  @override
  String restoredPosition(int percent) => 'Back to where you left off · $percent%';
  @override
  String get shareCopied => 'Share text copied to clipboard';
  @override
  String wordsAndMinutes(int words, int minutes) => '$words words · $minutes min';
  @override
  String get previousArticle => 'Previous';
  @override
  String get nextArticle => 'Next';
  @override
  String get noMore => 'None';
  @override
  String get back => 'Back';
  @override
  String get readerSettings => 'Reading settings';
  @override
  String get share => 'Share';
  @override
  String get favoriteArticle => 'Save article';
  @override
  String get favoritedToast => 'Saved · find it under Me';
  @override
  String get unfavoritedToast => 'Removed from saved articles';
  @override
  String get finished => 'Finished';
  @override
  String get finishHint => 'Read to here to finish';
  @override
  String get finishTitle => 'Well done!';
  @override
  String get streakPrefix => 'Streak ';
  @override
  String streakSuffix(int minutes) => ' days · $minutes min on this article';
  @override
  String get fontSize => 'Font size';
  @override
  String get lineHeight => 'Line spacing';
  @override
  String get theme => 'Theme';

  @override
  String get notInDictionary => 'Not in the mock dictionary yet';
  @override
  String get collectWord => 'Save word';
  @override
  String get uncollectWord => 'Remove word';
  @override
  String get markSentence => 'Highlight sentence';
  @override
  String get unmarkSentence => 'Remove highlight';
  @override
  String get sentenceMarkedToast => 'Highlighted · find it in Notebook';

  @override
  String get notebookTitle => 'Notebook';
  @override
  String notebookWords(int n) => 'Words $n';
  @override
  String notebookSentences(int n) => 'Sentences $n';
  @override
  String deleted(String text) => 'Deleted "$text"';
  @override
  String get emptyWordsTitle => 'No words yet';
  @override
  String get emptyWordsHint => 'Long-press any word while reading to save it';
  @override
  String get emptySentencesTitle => 'No highlights yet';
  @override
  String get emptySentencesHint => 'Long-press a word, then tap "Highlight sentence"';
  @override
  String source(String title) => 'From: $title';

  @override
  String get favoritesTitle => 'Saved articles';
  @override
  String favoritedAt(String date) => 'Saved $date';
  @override
  String get emptyFavoritesTitle => 'No saved articles';
  @override
  String get emptyFavoritesHint => 'Tap the bookmark at the top right while reading';

  @override
  String get localAccount => 'Local account · data stays on this device';
  @override
  String get statStreak => 'Streak';
  @override
  String get statFinished => 'Finished';
  @override
  String get statTotal => 'Reading';
  @override
  String get statNotes => 'Notes';
  @override
  String get unitDays => ' d';
  @override
  String get unitArticles => '';
  @override
  String get unitMinutes => ' min';
  @override
  String get unitItems => '';
  @override
  String get weekChartTitle => 'Reading time, last 7 days';
  @override
  String todayMinutes(String m) => 'Today $m min';
  @override
  String get today => 'Today';
  @override
  String get language => 'Language';
  @override
  String get debugPanel => 'Analytics & performance panel';
  @override
  String get debugPanelSubtitle => 'Event queue · uploads · queries · frame timing';
  @override
  String get logout => 'Log out';
  @override
  String get logoutSubtitle => 'Revokes the local token; reading data is kept';
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  bool isSupported(Locale locale) => const ['zh', 'en'].contains(locale.languageCode);

  @override
  Future<S> load(Locale locale) => SynchronousFuture<S>(S.forLocale(locale));

  @override
  bool shouldReload(_SDelegate old) => false;
}
