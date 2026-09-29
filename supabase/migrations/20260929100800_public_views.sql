-- 公開ビュー（docs/API契約.md）。
--
-- public_profiles：プロフィール本文（bio・child_age_range）を含まない公開列のみ。
--   profilesテーブル自体のRLSは本人・運営者限定のため、あえてsecurity_invokerを付けず
--   （デフォルトのowner権限で実行する）ビュー経由でニックネーム等だけを公開する。
--   PostgreSQL 15以降のsecurity_invoker=trueはこの用途では使わない（RLSに阻まれ0件になるため）。
create view public.public_profiles as
select id, nickname, icon_key
from public.profiles;

grant select on public.public_profiles to anon, authenticated;

comment on view public.public_profiles is '投稿上に表示する公開プロフィール（bio・child_age_rangeは含まない）。';

-- 公開コメント件数はSECURITY DEFINER関数で計算し、コメント本文へのアクセスを必要としない
-- （comments テーブルの直接SELECTはログイン必須のため、未ログイン利用者のcomment_count取得に使う）。
-- public_postsビューより先に定義する（ビュー作成時に関数の存在が必要なため）。
create or replace function public.post_comment_count(p_post_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)
  from public.comments
  where post_id = p_post_id and deleted_at is null and hidden_at is null;
$$;

comment on function public.post_comment_count(uuid) is
  '削除済み・一時非表示を除いた公開コメント件数（決定済み）。未ログインでも参照可。';

-- public_posts：一時非表示・削除済みを除外し、共感件数・通報情報を含まない。
--   postsのSELECT RLS（hidden_at is null を anon/authenticated に許可）に従うよう
--   security_invoker = true とする。
create view public.public_posts
  with (security_invoker = true) as
select
  p.id,
  p.post_type,
  p.topic_id,
  p.body,
  p.reaction_mode,
  p.comment_acceptance,
  p.created_at,
  p.updated_at,
  public.post_comment_count(p.id) as comment_count
from public.posts p
where p.hidden_at is null;

comment on view public.public_posts is '一覧・検索で使う公開投稿ビュー。共感件数・通報情報を含まない。';

grant select on public.public_posts to anon, authenticated;
