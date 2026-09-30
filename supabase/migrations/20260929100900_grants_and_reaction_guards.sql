-- Data APIロール（anon・authenticated・service_role）への権限付与と、共感ポリシーの強化。
--
-- Supabaseの「新しいテーブルを自動的に公開する」をオフにした環境（dev・prod）でも、
-- ローカルと同じ挙動になるよう、必要な権限だけをここで明示する（config.tomlの
-- auto_expose_new_tables = false と対応）。付与した権限はRLSポリシーと合わせて初めて有効になる。
-- 以降のマイグレーションで新しいテーブルを追加するときは、必要な権限を同じマイグレーション内で付与する。

-- 未ログイン（anon）：公開マスタと公開投稿のみ。
grant select on public.topics, public.reaction_types, public.posts to anon;

-- ログイン済み（authenticated）：参照はRLSポリシーが許すテーブルのみ。
grant select on
  public.admin_users,
  public.profiles,
  public.nickname_reservations,
  public.topics,
  public.posts,
  public.comments,
  public.reaction_types,
  public.reports,
  public.moderation_actions,
  public.account_restrictions,
  public.notifications,
  public.app_settings
to authenticated;

-- 自由記述を伴わない本人限定のトグル（CLAUDE.md参照）。
grant select, insert, update, delete on
  public.reactions,
  public.saved_posts,
  public.hidden_items,
  public.muted_topics,
  public.muted_words,
  public.notification_settings,
  public.push_devices
to authenticated;

grant select, insert, delete on public.blocks to authenticated;

-- 通知は既読フラグの更新のみ許可する（他の列は変更させない）。
grant update (is_read) on public.notifications to authenticated;

-- サーバー処理（Edge Functions）用。RLSをバイパスするが、テーブル権限自体は必要。
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;

-- RLSポリシーやビューから呼ばれる関数。
grant execute on function public.post_comment_count(uuid) to anon, authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_restricted(uuid) to authenticated;
grant execute on function public.get_post_reaction_count(uuid) to authenticated;

-- 共感の登録・変更は、利用停止中の利用者と一時非表示の投稿には行えない（Issue #7決定・権限表）。
-- 取消（削除）は常に本人が行える。ブロック関係の確認は#14で追加する。
drop policy reactions_insert_own on public.reactions;
drop policy reactions_update_own on public.reactions;

create policy reactions_insert_own
  on public.reactions
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and not public.is_restricted(auth.uid())
    and exists (
      select 1 from public.posts p
      where p.id = reactions.post_id and p.hidden_at is null
    )
  );

create policy reactions_update_own
  on public.reactions
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and not public.is_restricted(auth.uid())
    and exists (
      select 1 from public.posts p
      where p.id = reactions.post_id and p.hidden_at is null
    )
  );

-- 関数のEXECUTEは既定で全員（PUBLIC）に付くため、未ログインに不要なものは外す。
revoke execute on function public.is_admin() from public;
revoke execute on function public.is_restricted(uuid) from public;
revoke execute on function public.get_post_reaction_count(uuid) from public;
grant execute on function public.is_admin() to authenticated, service_role;
grant execute on function public.is_restricted(uuid) to authenticated, service_role;
grant execute on function public.get_post_reaction_count(uuid) to authenticated, service_role;
