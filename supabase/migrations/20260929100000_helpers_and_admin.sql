-- 共通ヘルパー関数と運営者テーブル。
-- 他の全マイグレーションより先に適用する。

create table public.admin_users (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

comment on table public.admin_users is '運営者アカウント。管理操作の権限判定に使用する（docs/権限表.md）。';

alter table public.admin_users enable row level security;

-- admin_usersへの書き込みはEdge Functions（service_role）専用。
-- 本人・他人の直接INSERT/UPDATE/DELETEは許可しない。

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid());
$$;

comment on function public.is_admin() is '呼び出し中の利用者が運営者かどうかを判定する。RLSポリシーから利用する。';

-- ポリシー内でadmin_usersを直接副問い合わせすると無限再帰になるため、
-- RLSを迂回するsecurity definer関数is_admin()を経由する。
create policy admin_users_select_self_or_admin
  on public.admin_users
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- updated_atを自動更新する共通トリガー関数。
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ニックネームの正規化（NFKC正規化＋大文字小文字統一＋前後空白除去）。
-- 絵文字・結合文字の詳細な扱いは未確定のため、Edge Function側での
-- グラフェムクラスタ単位の文字数検証と合わせて運用する（docs/未決事項.md）。
create or replace function public.normalize_nickname(input text)
returns text
language sql
immutable
as $$
  select lower(trim(both from normalize(input, nfkc)));
$$;
