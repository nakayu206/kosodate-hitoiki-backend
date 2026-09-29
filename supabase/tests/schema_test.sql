-- スキーマ構造の検証（docs/スキーマ定義.md）。
-- Issue #10チェックリスト：空DBから再構築でき、外部キー・一意制約が機能する。

BEGIN;
SELECT plan(16);

-- テスト用の認証ユーザーを用意（RLSより上位のpostgresロールで実行）。
INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-000000000001');

-- 主要テーブルの存在
SELECT has_table('public', 'profiles', 'profiles テーブルが存在する');
SELECT has_table('public', 'posts', 'posts テーブルが存在する');
SELECT has_table('public', 'comments', 'comments テーブルが存在する');
SELECT has_table('public', 'reactions', 'reactions テーブルが存在する');
SELECT has_table('public', 'reports', 'reports テーブルが存在する');
SELECT has_table('public', 'account_restrictions', 'account_restrictions テーブルが存在する');

-- 全テーブルでRLSが有効（自動生成APIに晒しても安全なように）
SELECT results_eq(
  $$select count(*)::int from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity$$,
  $$values (0)$$,
  'public スキーマの全テーブルでRLSが有効になっている'
);

-- profiles.normalized_nickname の一意制約
SELECT col_is_unique('public', 'profiles', array['normalized_nickname'], 'normalized_nickname は一意');

-- reactions の複合主キー
SELECT col_is_pk('public', 'reactions', array['post_id', 'user_id'], 'reactions の主キーは (post_id, user_id)');

-- posts.post_type のCHECK制約（有効なauthor_idで、post_typeのみ不正な値にする）
SELECT throws_ok(
  $$insert into public.posts (id, author_id, post_type, body)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 'invalid_type', 'test')$$,
  '23514',
  null,
  '不正な post_type は CHECK 制約で拒否される'
);

-- comment_acceptance は reaction_mode = want_comments のときのみ設定可能
SELECT throws_ok(
  $$insert into public.posts (id, author_id, post_type, body, reaction_mode, comment_acceptance)
    values (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 'guchi', 'test', 'quiet_support', 'open')$$,
  '23514',
  null,
  'quiet_support では comment_acceptance を設定できない'
);

-- blocks の自己ブロック禁止制約
SELECT throws_ok(
  $$insert into public.blocks (blocker_id, blocked_id)
    values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001')$$,
  '23514',
  null,
  '自分自身へのブロックは CHECK 制約で拒否される'
);

-- reportsの部分unique index（未対応通報のみ一意）
SELECT has_index('public', 'reports', 'reports_unique_unresolved',
  '未対応通報の重複を防ぐ部分unique indexが存在する');

-- account_restrictions: stage=3（無期限）はends_atを持てない
SELECT throws_ok(
  $$insert into public.account_restrictions (user_id, stage, ends_at, created_by)
    values ('00000000-0000-0000-0000-000000000001', 3, now() + interval '1 day', '00000000-0000-0000-0000-000000000001')$$,
  '23514',
  null,
  'stage=3（無期限）に ends_at は設定できない'
);

-- admin_users, app_settingsの存在（運営機能の土台）
SELECT has_table('public', 'admin_users', 'admin_users テーブルが存在する');
SELECT has_table('public', 'app_settings', 'app_settings テーブルが存在する');

SELECT * FROM finish();
ROLLBACK;
