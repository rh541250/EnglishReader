/// 数据库迁移脚本。
///
/// 策略：`PRAGMA user_version` 记录当前版本（由 sqflite 的 version 机制维护），
/// 打开数据库时按版本号从小到大依次执行 [kMigrations] 中尚未执行的脚本，
/// 整个升级过程在同一个事务内，失败则整体回滚、版本号不前进。
///
/// 约定：已发布的版本脚本只增不改；新增字段 / 表一律追加新的版本号。
const int kSchemaVersion = 1;

const Map<int, List<String>> kMigrations = {
  1: [
    // ---- 账号与会话（Mock 鉴权） ----
    '''
    CREATE TABLE users (
      id            TEXT PRIMARY KEY,
      username      TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      salt          TEXT NOT NULL,
      created_at    INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE sessions (
      jti        TEXT PRIMARY KEY,
      user_id    TEXT NOT NULL REFERENCES users(id),
      issued_at  INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      revoked    INTEGER NOT NULL DEFAULT 0
    )
    ''',

    // ---- 文章（种子导入 / 可被远端同步覆盖） ----
    '''
    CREATE TABLE articles (
      id           TEXT PRIMARY KEY,
      title        TEXT NOT NULL,
      title_zh     TEXT NOT NULL DEFAULT '',
      category     TEXT NOT NULL,
      difficulty   INTEGER NOT NULL,
      author       TEXT NOT NULL DEFAULT '',
      published_at TEXT NOT NULL,
      summary      TEXT NOT NULL DEFAULT '',
      body_json    TEXT NOT NULL,
      word_count   INTEGER NOT NULL DEFAULT 0,
      version      INTEGER NOT NULL DEFAULT 1,
      updated_at   INTEGER NOT NULL
    )
    ''',
    // 列表页：按分类筛选 + 发布时间倒序分页
    'CREATE INDEX idx_articles_category_published ON articles(category, published_at DESC, id)',
    // 列表页：全部分类下的发布时间倒序分页、上下篇查询
    'CREATE INDEX idx_articles_published ON articles(published_at DESC, id)',
    'CREATE INDEX idx_articles_difficulty ON articles(difficulty)',

    // ---- 阅读进度：每个用户每篇文章一行，写入为绝对值 upsert（幂等） ----
    '''
    CREATE TABLE reading_progress (
      user_id          TEXT NOT NULL,
      article_id       TEXT NOT NULL REFERENCES articles(id),
      paragraph_index  INTEGER NOT NULL DEFAULT 0,
      paragraph_offset REAL NOT NULL DEFAULT 0,
      progress         REAL NOT NULL DEFAULT 0,
      max_progress     REAL NOT NULL DEFAULT 0,
      completed        INTEGER NOT NULL DEFAULT 0,
      completed_at     INTEGER,
      duration_ms      INTEGER NOT NULL DEFAULT 0,
      last_read_at     INTEGER NOT NULL,
      version          INTEGER NOT NULL DEFAULT 1,
      updated_at       INTEGER NOT NULL,
      PRIMARY KEY (user_id, article_id)
    )
    ''',
    // 「继续阅读」与最近阅读列表
    'CREATE INDEX idx_progress_user_recent ON reading_progress(user_id, last_read_at DESC)',

    // ---- 阅读会话：一次进入阅读页为一行，时长为绝对值（幂等），用于按天统计与打卡 ----
    '''
    CREATE TABLE reading_sessions (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL,
      article_id  TEXT NOT NULL,
      day         TEXT NOT NULL,
      started_at  INTEGER NOT NULL,
      duration_ms INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_sessions_user_day ON reading_sessions(user_id, day)',
    'CREATE INDEX idx_sessions_user_article ON reading_sessions(user_id, article_id)',

    // ---- 生词本：同一用户同一词（词元）只收藏一次，记录首次出处 ----
    '''
    CREATE TABLE vocabulary (
      id              TEXT PRIMARY KEY,
      user_id         TEXT NOT NULL,
      word            TEXT NOT NULL,
      display         TEXT NOT NULL,
      phonetic        TEXT NOT NULL DEFAULT '',
      pos             TEXT NOT NULL DEFAULT '',
      meaning         TEXT NOT NULL DEFAULT '',
      article_id      TEXT NOT NULL,
      paragraph_index INTEGER NOT NULL,
      word_index      INTEGER NOT NULL,
      context         TEXT NOT NULL DEFAULT '',
      created_at      INTEGER NOT NULL,
      version         INTEGER NOT NULL DEFAULT 1,
      updated_at      INTEGER NOT NULL,
      UNIQUE (user_id, word)
    )
    ''',
    'CREATE INDEX idx_vocab_user_created ON vocabulary(user_id, created_at DESC)',

    // ---- Mock 词表 ----
    '''
    CREATE TABLE dictionary (
      word     TEXT PRIMARY KEY,
      phonetic TEXT NOT NULL DEFAULT '',
      pos      TEXT NOT NULL DEFAULT '',
      meaning  TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE dictionary_forms (
      form  TEXT PRIMARY KEY,
      lemma TEXT NOT NULL
    )
    ''',

    // ---- 埋点事件队列：event_id 为主键保证本地与服务端双重去重 ----
    // status: 0 待上报  1 上报中  2 已上报
    '''
    CREATE TABLE event_queue (
      event_id      TEXT PRIMARY KEY,
      name          TEXT NOT NULL,
      ts            INTEGER NOT NULL,
      session_id    TEXT NOT NULL,
      user_id       TEXT NOT NULL DEFAULT '',
      payload_json  TEXT NOT NULL,
      status        INTEGER NOT NULL DEFAULT 0,
      attempts      INTEGER NOT NULL DEFAULT 0,
      next_retry_at INTEGER NOT NULL DEFAULT 0,
      batch_id      TEXT,
      sent_at       INTEGER,
      last_error    TEXT
    )
    ''',
    // 上报器取批：status=0 且到达重试时间，按时间先后
    'CREATE INDEX idx_events_status_retry ON event_queue(status, next_retry_at, ts)',
    // 分析查询：按事件名 + 时间范围
    'CREATE INDEX idx_events_name_ts ON event_queue(name, ts)',

    // ---- 上报结果日志（调试面板用） ----
    '''
    CREATE TABLE upload_log (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      batch_id    TEXT NOT NULL,
      ts          INTEGER NOT NULL,
      event_count INTEGER NOT NULL,
      ok          INTEGER NOT NULL,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      error       TEXT
    )
    ''',

    // ---- Mock 接收端：模拟服务端按 event_id 去重落库 ----
    '''
    CREATE TABLE mock_server_events (
      event_id    TEXT PRIMARY KEY,
      name        TEXT NOT NULL,
      ts          INTEGER NOT NULL,
      received_at INTEGER NOT NULL
    )
    ''',

    // ---- 杂项键值（种子版本、device_id 等） ----
    '''
    CREATE TABLE meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
  ],
};
