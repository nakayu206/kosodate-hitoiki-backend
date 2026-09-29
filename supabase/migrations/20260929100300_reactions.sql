-- 共感（リアクション）（docs/スキーマ定義.md 4節）。

create table public.reaction_types (
  id smallint generated always as identity primary key,
  label text not null,
  sort_order smallint not null default 0,
  is_active boolean not null default true
);

comment on table public.reaction_types is '運営が用意する定型文（5〜8種）。共感ボタンと統一した単一のリアクション種別。';

alter table public.reaction_types enable row level security;

create policy reaction_types_select_all
  on public.reaction_types
  for select
  to anon, authenticated
  using (true);

create table public.reactions (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  reaction_type_id smallint not null references public.reaction_types (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

comment on table public.reactions is '投稿・利用者ごとに1件。ログイン必須、変更・取消可能（決定済み）。';

create trigger reactions_set_updated_at
  before update on public.reactions
  for each row execute function public.set_updated_at();

alter table public.reactions enable row level security;

-- 自分のリアクションのみ操作可能。他者の行・件数は直接公開しない
-- （件数はSECURITY DEFINER関数 get_post_reaction_count 経由、docs/API契約.md 5節）。
create policy reactions_select_own
  on public.reactions
  for select
  to authenticated
  using (user_id = auth.uid());

create policy reactions_select_admin
  on public.reactions
  for select
  to authenticated
  using (public.is_admin());

create policy reactions_insert_own
  on public.reactions
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy reactions_update_own
  on public.reactions
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy reactions_delete_own
  on public.reactions
  for delete
  to authenticated
  using (user_id = auth.uid());

-- 投稿者のみが件数を取得できるSECURITY DEFINER関数（テーブルのRLSに依存しない）。
create or replace function public.get_post_reaction_count(p_post_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)
  from public.reactions r
  join public.posts p on p.id = r.post_id
  where r.post_id = p_post_id and p.author_id = auth.uid();
$$;

comment on function public.get_post_reaction_count(uuid) is '呼び出し者が投稿者本人の場合のみ件数を返す。それ以外は0を返す。';
