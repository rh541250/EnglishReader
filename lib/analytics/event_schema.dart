/// 埋点事件模型。
///
/// 命名规范：`对象_动作`，全小写下划线（snake_case），动作用动词原形或名词，
/// 例如 article_open / word_collect。新增事件必须先在这里登记，
/// [EventSpec.validate] 会在 debug 模式下校验必填 / 未登记参数。
class EventSpec {
  const EventSpec(this.name, this.description, {this.required = const [], this.optional = const []});

  final String name;
  final String description;

  /// 必填业务参数。
  final List<String> required;

  /// 选填业务参数。
  final List<String> optional;

  /// 返回问题列表，空表示合法。
  List<String> validate(Map<String, Object?> props) {
    final problems = <String>[];
    for (final k in required) {
      if (props[k] == null) problems.add('$name 缺少必填参数 $k');
    }
    for (final k in props.keys) {
      if (!required.contains(k) && !optional.contains(k)) {
        problems.add('$name 含未登记参数 $k');
      }
    }
    return problems;
  }
}

/// 公共参数：每条事件都会自动带上，业务代码不需要也不允许手动传。
const List<String> kCommonParams = [
  'event_id', // UUID，去重键
  'event', // 事件名
  'ts', // 客户端事件发生时间（毫秒时间戳）
  'device_id', // 安装级设备标识
  'user_id', // 登录用户 id，未登录为空串
  'session_id', // 会话 id
  'app_version',
  'platform', // ios / android
  'network', // online / offline（事件发生时的联网状态）
];

abstract final class Ev {
  static const appOpen = 'app_open';
  static const sessionStart = 'session_start';
  static const pageView = 'page_view';
  static const login = 'user_login';
  static const listRefresh = 'list_refresh';
  static const categorySwitch = 'category_switch';
  static const articleExpose = 'article_expose';
  static const articleOpen = 'article_open';
  static const readProgress = 'read_progress';
  static const readDuration = 'read_duration';
  static const articleFinish = 'article_finish';
  static const wordLookup = 'word_lookup';
  static const wordCollect = 'word_collect';
  static const wordRemove = 'word_remove';
  static const articleShare = 'article_share';
  static const offlineHit = 'offline_hit';
  static const settingChange = 'reader_setting_change';
}

const List<EventSpec> kEventSpecs = [
  EventSpec(Ev.appOpen, '打开 App（冷启动，或后台超过会话阈值后回到前台）', required: ['launch_type'], optional: ['background_ms']),
  EventSpec(Ev.sessionStart, '新会话开始', required: ['reason']),
  EventSpec(Ev.pageView, '页面浏览', required: ['page'], optional: ['from', 'article_id']),
  EventSpec(Ev.login, '登录 / 注册成功', required: ['method']),
  EventSpec(Ev.listRefresh, '列表下拉刷新', optional: ['category', 'difficulty']),
  EventSpec(Ev.categorySwitch, '分类 / 难度筛选切换', required: ['filter_type', 'to'], optional: ['from']),
  EventSpec(
    Ev.articleExpose,
    '文章卡片曝光（可见面积 ≥ 50% 且停留 ≥ 500ms，同一会话内同一文章只报一次）',
    required: ['article_id', 'position'],
    optional: ['category', 'difficulty', 'list_category'],
  ),
  EventSpec(
    Ev.articleOpen,
    '打开文章',
    required: ['article_id', 'source'],
    optional: ['category', 'difficulty', 'resume_progress'],
  ),
  EventSpec(Ev.readProgress, '滚动深度里程碑（25 / 50 / 75 / 100）', required: ['article_id', 'depth']),
  EventSpec(
    Ev.readDuration,
    '阅读时长（离开阅读页或切后台时上报本段有效时长）',
    required: ['article_id', 'duration_ms', 'max_depth'],
    optional: ['reason'],
  ),
  EventSpec(
    Ev.articleFinish,
    '读完文章（首次达到读完阈值）',
    required: ['article_id', 'total_duration_ms'],
    optional: ['streak_days', 'category', 'difficulty'],
  ),
  EventSpec(Ev.wordLookup, '长按取词', required: ['article_id', 'word'], optional: ['found', 'paragraph_index']),
  EventSpec(Ev.wordCollect, '收藏生词', required: ['article_id', 'word'], optional: ['paragraph_index', 'source']),
  EventSpec(Ev.wordRemove, '取消收藏 / 删除生词', required: ['word'], optional: ['source', 'article_id']),
  EventSpec(Ev.articleShare, '分享文章', required: ['article_id'], optional: ['channel']),
  EventSpec(Ev.offlineHit, '离线命中：无网络状态下从本地库成功提供内容', required: ['resource'], optional: ['article_id']),
  EventSpec(Ev.settingChange, '阅读设置变更', required: ['key', 'value']),
];

final Map<String, EventSpec> kEventSpecByName = {for (final s in kEventSpecs) s.name: s};
