-- プロフィール・ニックネーム予約（docs/スキーマ定義.md 2節）。

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null,
  normalized_nickname text not null,
  icon_key text,
  bio text,
  child_age_range text,
  nickname_changed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_nickname_length check (char_length(nickname) between 1 and 24),
  constraint profiles_bio_length check (bio is null or char_length(bio) <= 100),
  constraint profiles_normalized_nickname_unique unique (normalized_nickname)
);

comment on table public.profiles is '認証ユーザーに対応する表示名・アイコン・自己紹介・子どもの年齢帯。';
comment on column public.profiles.normalized_nickname is '重複判定用の正規化済み値。トリガーで自動生成する。';

create table public.nickname_reservations (
  normalized_nickname text primary key,
  reserved_until timestamptz not null,
  previous_owner_id uuid,
  reason text not null check (reason in ('changed', 'withdrawn')),
  created_at timestamptz not null default now()
);

comment on table public.nickname_reservations is '変更前・退会時のニックネームの再利用禁止期限（30日）。';

-- ニックネーム変更時の正規化・変更間隔・予約チェックをまとめて行う。
-- （複数のBEFOREトリガーに分けると実行順序に依存してしまうため1つにまとめる）
create or replace function public.profiles_before_write()
returns trigger
language plpgsql
as $$
declare
  reservation record;
begin
  new.normalized_nickname := public.normalize_nickname(new.nickname);
  new.updated_at := now();

  if tg_op = 'UPDATE' and old.normalized_nickname is distinct from new.normalized_nickname then
    if now() - old.nickname_changed_at < interval '30 days' then
      raise exception 'ニックネームは30日に1回まで変更できます' using errcode = 'P0001';
    end if;
    new.nickname_changed_at := now();
  end if;

  select * into reservation
  from public.nickname_reservations
  where normalized_nickname = new.normalized_nickname
    and reserved_until > now();

  if found and reservation.previous_owner_id is distinct from new.id then
    raise exception 'この名前は現在使用できません' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger profiles_before_insert_update
  before insert or update of nickname on public.profiles
  for each row execute function public.profiles_before_write();

-- ニックネーム変更時に旧名を30日間予約する。
create or replace function public.profiles_after_nickname_change()
returns trigger
language plpgsql
as $$
begin
  if old.normalized_nickname is distinct from new.normalized_nickname then
    insert into public.nickname_reservations (normalized_nickname, reserved_until, previous_owner_id, reason)
    values (old.normalized_nickname, now() + interval '30 days', old.id, 'changed')
    on conflict (normalized_nickname) do update
      set reserved_until = excluded.reserved_until,
          previous_owner_id = excluded.previous_owner_id,
          reason = excluded.reason;
  end if;
  return null;
end;
$$;

create trigger profiles_after_update_reserve_old_nickname
  after update of nickname on public.profiles
  for each row execute function public.profiles_after_nickname_change();

alter table public.profiles enable row level security;
alter table public.nickname_reservations enable row level security;

-- profiles・nickname_reservationsへの直接INSERT/UPDATE/DELETEは許可しない。
-- ニックネーム・自己紹介は送信前チェック対象のため、Edge Functions（service_role）
-- 経由でのみ書き込む（docs/バックエンド設計.md 4節）。

create policy profiles_select_self_or_admin
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid() or public.is_admin());

-- nickname_reservationsは一般利用者に公開しない（重複判定はEdge Function・トリガー内で行う）。
create policy nickname_reservations_select_admin_only
  on public.nickname_reservations
  for select
  to authenticated
  using (public.is_admin());
