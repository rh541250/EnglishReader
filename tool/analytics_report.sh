#!/usr/bin/env bash
# 埋点汇总脚本：对 App 的 SQLite 数据库跑三个分析查询，输出与 App 内调试面板一致的口径。
#
# 用法：
#   tool/analytics_report.sh                # 自动定位「已启动的 iOS 模拟器」里的 App 数据库
#   tool/analytics_report.sh path/to/english_reader.db
#
# 依赖：sqlite3（macOS 自带，需 JSON1 扩展——系统版本默认带）。
set -euo pipefail

DB="${1:-}"
if [[ -z "$DB" ]]; then
  CONTAINER="$(xcrun simctl get_app_container booted com.rh541250.englishReader data 2>/dev/null || true)"
  DB="$CONTAINER/Documents/english_reader.db"
fi
if [[ ! -f "$DB" ]]; then
  echo "找不到数据库文件: $DB" >&2
  exit 1
fi

# 近 7 日窗口起点：6 天前的本地 0 点（毫秒时间戳）。
SINCE="CAST(strftime('%s','now','localtime','start of day','-6 days','utc') AS INTEGER) * 1000"

run() { sqlite3 -readonly -header -column "$DB" "$1"; }

echo "数据库: $DB"
echo
echo "== 事件队列 =="
run "SELECT CASE status WHEN 0 THEN 'pending' WHEN 1 THEN 'sending' ELSE 'sent' END AS status,
            COUNT(*) AS events
     FROM event_queue GROUP BY status ORDER BY status;"
echo
echo "== 各事件数量 =="
run "SELECT name AS event, COUNT(*) AS n FROM event_queue GROUP BY name ORDER BY n DESC, name;"
echo
echo "== 查询 1：近 7 日阅读时长分布（分钟 / 天） =="
run "SELECT date(ts / 1000, 'unixepoch', 'localtime') AS day,
            ROUND(SUM(json_extract(payload_json, '\$.props.duration_ms')) / 60000.0, 1) AS minutes,
            COUNT(*) AS reads
     FROM event_queue
     WHERE name = 'read_duration' AND ts >= $SINCE
     GROUP BY day ORDER BY day;"
echo
echo "-- 单次阅读时长分桶 --"
run "SELECT CASE
              WHEN d < 60000  THEN '1) <1 分钟'
              WHEN d < 180000 THEN '2) 1-3 分钟'
              WHEN d < 300000 THEN '3) 3-5 分钟'
              ELSE                 '4) >=5 分钟'
            END AS bucket,
            COUNT(*) AS reads
     FROM (SELECT json_extract(payload_json, '\$.props.duration_ms') AS d
           FROM event_queue WHERE name = 'read_duration' AND ts >= $SINCE)
     GROUP BY bucket ORDER BY bucket;"
echo
echo "== 查询 2：近 7 日 曝光 → 打开 → 读到 50% → 读完 漏斗（按 user_id + article_id 去重） =="
run "WITH e AS (
       SELECT name,
              user_id || '|' || json_extract(payload_json, '\$.props.article_id') AS k,
              json_extract(payload_json, '\$.props.depth') AS depth
       FROM event_queue WHERE ts >= $SINCE
     ),
     opened AS (SELECT DISTINCT k FROM e WHERE name = 'article_open'),
     f AS (
       SELECT
         (SELECT COUNT(DISTINCT k) FROM e WHERE name IN ('article_expose', 'article_open')) AS exposed,
         (SELECT COUNT(*) FROM opened) AS opened,
         (SELECT COUNT(DISTINCT k) FROM e WHERE name = 'read_progress' AND depth >= 50
            AND k IN (SELECT k FROM opened)) AS half,
         (SELECT COUNT(DISTINCT k) FROM e WHERE name = 'article_finish'
            AND k IN (SELECT k FROM opened)) AS finished
     )
     SELECT exposed, opened, half, finished,
            ROUND(100.0 * opened / MAX(exposed, 1), 1)  AS open_rate_pct,
            ROUND(100.0 * half / MAX(opened, 1), 1)     AS half_rate_pct,
            ROUND(100.0 * finished / MAX(opened, 1), 1) AS finish_rate_pct
     FROM f;"
echo
echo "== 查询 3：近 7 日取词与收藏 =="
run "SELECT SUM(name = 'word_lookup') AS lookups,
            SUM(name = 'word_collect') AS collects,
            ROUND(100.0 * SUM(name = 'word_collect') / MAX(SUM(name = 'word_lookup'), 1), 1) AS collect_rate_pct
     FROM event_queue
     WHERE name IN ('word_lookup', 'word_collect') AND ts >= $SINCE;"
echo
echo "-- 取词 Top 5 --"
run "SELECT json_extract(payload_json, '\$.props.word') AS word, COUNT(*) AS lookups
     FROM event_queue WHERE name = 'word_lookup' AND ts >= $SINCE
     GROUP BY word ORDER BY lookups DESC, word LIMIT 5;"
echo
echo "== 最近 5 次上报 =="
run "SELECT time(ts / 1000, 'unixepoch', 'localtime') AS at, event_count AS events,
            CASE ok WHEN 1 THEN 'ok' ELSE 'FAIL' END AS result, duration_ms, COALESCE(error, '') AS error
     FROM upload_log ORDER BY id DESC LIMIT 5;"
