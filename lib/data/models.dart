import 'dart:convert';

import '../domain/reading_math.dart';

/// 文章分类。展示名称见 `S.category`（随界面语言变化），这里只保留存储用的 key。
enum ArticleCategory {
  tech('tech'),
  business('business'),
  culture('culture'),
  daily('daily');

  const ArticleCategory(this.key);
  final String key;

  static ArticleCategory fromKey(String key) =>
      values.firstWhere((c) => c.key == key, orElse: () => ArticleCategory.daily);
}

/// 列表用的文章摘要（不含正文），附带当前用户的阅读状态。
class ArticleSummary {
  const ArticleSummary({
    required this.id,
    required this.title,
    required this.titleZh,
    required this.category,
    required this.difficulty,
    required this.author,
    required this.publishedAt,
    required this.summary,
    required this.wordCount,
    this.maxProgress = 0,
    this.completed = false,
    this.lastReadAt,
    this.favoritedAt,
  });

  final String id;
  final String title;
  final String titleZh;
  final ArticleCategory category;
  final int difficulty;
  final String author;
  final String publishedAt;
  final String summary;
  final int wordCount;
  final double maxProgress;
  final bool completed;
  final int? lastReadAt;

  /// 当前用户收藏该文章的时间；未收藏为 null。
  final int? favoritedAt;

  bool get favorited => favoritedAt != null;

  DateTime get publishedDate => DateTime.tryParse(publishedAt) ?? DateTime(1970);

  int get minutes => estimateMinutes(wordCount);

  factory ArticleSummary.fromRow(Map<String, Object?> r) => ArticleSummary(
    id: r['id'] as String,
    title: r['title'] as String,
    titleZh: r['title_zh'] as String? ?? '',
    category: ArticleCategory.fromKey(r['category'] as String),
    difficulty: r['difficulty'] as int,
    author: r['author'] as String? ?? '',
    publishedAt: r['published_at'] as String,
    summary: r['summary'] as String? ?? '',
    wordCount: r['word_count'] as int? ?? 0,
    maxProgress: (r['max_progress'] as num?)?.toDouble() ?? 0,
    completed: (r['completed'] as int? ?? 0) == 1,
    lastReadAt: r['last_read_at'] as int?,
    favoritedAt: r['favorited_at'] as int?,
  );

  ArticleSummary copyWith({double? maxProgress, bool? completed, int? Function()? favoritedAt}) => ArticleSummary(
    id: id,
    title: title,
    titleZh: titleZh,
    category: category,
    difficulty: difficulty,
    author: author,
    publishedAt: publishedAt,
    summary: summary,
    wordCount: wordCount,
    maxProgress: maxProgress ?? this.maxProgress,
    completed: completed ?? this.completed,
    lastReadAt: lastReadAt,
    favoritedAt: favoritedAt == null ? this.favoritedAt : favoritedAt(),
  );
}

class Article {
  const Article({required this.summary, required this.paragraphs});

  final ArticleSummary summary;
  final List<String> paragraphs;

  String get id => summary.id;

  factory Article.fromRow(Map<String, Object?> r) => Article(
    summary: ArticleSummary.fromRow(r),
    paragraphs: (jsonDecode(r['body_json'] as String) as List).cast<String>(),
  );
}

class ReadingProgress {
  const ReadingProgress({
    required this.articleId,
    required this.position,
    required this.progress,
    required this.maxProgress,
    required this.completed,
    required this.durationMs,
    required this.lastReadAt,
    this.completedAt,
  });

  final String articleId;
  final ReadingPosition position;
  final double progress;
  final double maxProgress;
  final bool completed;
  final int durationMs;
  final int lastReadAt;
  final int? completedAt;

  factory ReadingProgress.fromRow(Map<String, Object?> r) => ReadingProgress(
    articleId: r['article_id'] as String,
    position: ReadingPosition(r['paragraph_index'] as int, (r['paragraph_offset'] as num).toDouble()),
    progress: (r['progress'] as num).toDouble(),
    maxProgress: (r['max_progress'] as num).toDouble(),
    completed: (r['completed'] as int) == 1,
    durationMs: r['duration_ms'] as int,
    lastReadAt: r['last_read_at'] as int,
    completedAt: r['completed_at'] as int?,
  );
}

class DictEntry {
  const DictEntry({
    required this.word,
    required this.phonetic,
    required this.pos,
    required this.meaning,
    this.found = true,
  });

  /// 词元（小写），也是生词本的去重键。
  final String word;
  final String phonetic;
  final String pos;
  final String meaning;

  /// Mock 词表是否收录。未收录时仍可收藏，释义为占位文案。
  final bool found;
}

class VocabEntry {
  const VocabEntry({
    required this.id,
    required this.word,
    required this.display,
    required this.phonetic,
    required this.pos,
    required this.meaning,
    required this.articleId,
    required this.paragraphIndex,
    required this.wordIndex,
    required this.context,
    required this.createdAt,
    this.articleTitle,
  });

  final String id;
  final String word;
  final String display;
  final String phonetic;
  final String pos;
  final String meaning;
  final String articleId;
  final int paragraphIndex;
  final int wordIndex;
  final String context;
  final int createdAt;
  final String? articleTitle;

  factory VocabEntry.fromRow(Map<String, Object?> r) => VocabEntry(
    id: r['id'] as String,
    word: r['word'] as String,
    display: r['display'] as String,
    phonetic: r['phonetic'] as String? ?? '',
    pos: r['pos'] as String? ?? '',
    meaning: r['meaning'] as String? ?? '',
    articleId: r['article_id'] as String,
    paragraphIndex: r['paragraph_index'] as int,
    wordIndex: r['word_index'] as int,
    context: r['context'] as String? ?? '',
    createdAt: r['created_at'] as int,
    articleTitle: r['article_title'] as String?,
  );
}

class AppUser {
  const AppUser({required this.id, required this.username});
  final String id;
  final String username;
}

/// 一条划线句子。区间是句子在段落中的字符偏移，与字号、排版无关。
class SentenceMark {
  const SentenceMark({
    required this.id,
    required this.articleId,
    required this.paragraphIndex,
    required this.start,
    required this.end,
    required this.text,
    required this.createdAt,
    this.articleTitle,
  });

  final String id;
  final String articleId;
  final int paragraphIndex;
  final int start;
  final int end;
  final String text;
  final int createdAt;
  final String? articleTitle;

  factory SentenceMark.fromRow(Map<String, Object?> r) => SentenceMark(
    id: r['id'] as String,
    articleId: r['article_id'] as String,
    paragraphIndex: r['paragraph_index'] as int,
    start: r['char_start'] as int,
    end: r['char_end'] as int,
    text: r['text'] as String,
    createdAt: r['created_at'] as int,
    articleTitle: r['article_title'] as String?,
  );
}
