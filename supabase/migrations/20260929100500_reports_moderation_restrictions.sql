-- 通報・運営操作・利用制限（docs/スキーマ定義.md 6節）。

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users (id) on delete cascade,
  target_type text not null check (target_type in ('post', 'comment')),
  target_id uuid not null,
  reason text not null,
  detail text,
  resolved_at timestamptz,
  resolved_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

comment on table public.reports is
  '通報。target_id は削除後も記録を残すため posts/comments へ物理FKを張らない（docs/スキーマ定義.md 6節）。';

-- 同一通報者・同一対象の「未対応」通報は1件のみ。対応済み後は新たな通報を受け付けられる
-- （部分unique indexにより、resolved_atがnullの行だけを一意制約の対象にする）。
create unique index reports_unique_unresolved
  on public.reports (reporter_id, target_type, target_id)
  where resolved_at is null;

create index reports_target_idx on public.reports (target_type, target_id);

-- 異なる通報者が3人到達したら対象を自動で一時非表示にする。
create or replace function public.reports_auto_hide()
returns trigger
language plpgsql
as $$
declare
  distinct_reporters integer;
begin
  -- 同一対象への同時通報で「3人到達」を取りこぼさないよう、対象単位で直列化する。
  -- ロック取得後のselectは新しいスナップショットで実行されるため、先に確定した通報も数えられる。
  perform pg_advisory_xact_lock(hashtextextended(new.target_type || ':' || new.target_id::text, 0));

  -- 運営が一度再表示した対象は、新たな通報が3人に達しても自動非表示を繰り返さない
  -- （運営が個別に確認する。Issue #7決定）。再表示の事実はmoderation_actionsに残っている。
  if exists (
    select 1 from public.moderation_actions
    where target_type = new.target_type
      and target_id = new.target_id
      and action = 'unhide'
  ) then
    return null;
  end if;

  select count(distinct reporter_id) into distinct_reporters
  from public.reports
  where target_type = new.target_type
    and target_id = new.target_id
    and resolved_at is null;

  if distinct_reporters >= 3 then
    if new.target_type = 'post' then
      update public.posts set hidden_at = now() where id = new.target_id and hidden_at is null;
    elsif new.target_type = 'comment' then
      update public.comments set hidden_at = now() where id = new.target_id and hidden_at is null;
    end if;
  end if;

  return null;
end;
$$;

create trigger reports_after_insert_auto_hide
  after insert on public.reports
  for each row execute function public.reports_auto_hide();

create table public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users (id),
  target_type text not null check (target_type in ('post', 'comment')),
  target_id uuid not null,
  target_owner_id uuid,
  action text not null check (action in ('unhide', 'delete', 'warn', 'suspend')),
  reason text,
  created_at timestamptz not null default now()
);

comment on table public.moderation_actions is '運営者の全操作を記録する（docs/スキーマ定義.md 6節）。';
comment on column public.moderation_actions.target_owner_id is
  '対象の投稿者・コメント投稿者。削除操作後も本人への理由通知を参照できるよう、挿入時点で記録する。';

-- 削除前に対象の所有者を記録しておく（削除後は posts/comments から引けなくなるため）。
create or replace function public.moderation_actions_before_insert()
returns trigger
language plpgsql
as $$
begin
  if new.target_type = 'post' then
    select author_id into new.target_owner_id from public.posts where id = new.target_id;
  elsif new.target_type = 'comment' then
    select author_id into new.target_owner_id from public.comments where id = new.target_id;
  end if;
  return new;
end;
$$;

create trigger moderation_actions_before_insert_set_owner
  before insert on public.moderation_actions
  for each row execute function public.moderation_actions_before_insert();

-- unhide：未対応通報をまとめて解消し、対象の一時非表示を解除する。
-- delete：投稿は削除、コメントはソフト削除する。
create or replace function public.moderation_actions_apply()
returns trigger
language plpgsql
as $$
begin
  if new.action = 'unhide' then
    update public.reports
      set resolved_at = now(), resolved_by = new.admin_id
      where target_type = new.target_type and target_id = new.target_id and resolved_at is null;

    if new.target_type = 'post' then
      update public.posts set hidden_at = null where id = new.target_id;
    elsif new.target_type = 'comment' then
      update public.comments set hidden_at = null where id = new.target_id;
    end if;
  elsif new.action = 'delete' then
    if new.target_type = 'post' then
      delete from public.posts where id = new.target_id;
    elsif new.target_type = 'comment' then
      update public.comments set deleted_at = now() where id = new.target_id and deleted_at is null;
    end if;
  end if;

  return new;
end;
$$;

create trigger moderation_actions_after_insert_apply
  after insert on public.moderation_actions
  for each row execute function public.moderation_actions_apply();

create table public.account_restrictions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  stage smallint not null check (stage in (1, 2, 3)),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  reason text,
  created_by uuid not null references auth.users (id),
  lifted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint account_restrictions_stage3_no_end check (stage < 3 or ends_at is null)
);

comment on table public.account_restrictions is
  '利用停止は段階的（初回7日→再発30日→無期限、決定済み）。判定基準・異議申立ては未確定。';

create index account_restrictions_user_id_idx on public.account_restrictions (user_id);

create or replace function public.is_restricted(target_user_id uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.account_restrictions
    where user_id = target_user_id
      and lifted_at is null
      and (ends_at is null or ends_at > now())
  );
$$;

comment on function public.is_restricted(uuid) is '対象利用者が現在利用停止中かどうかを判定する。Edge Functionsの書き込み前確認に使用する。';

alter table public.reports enable row level security;
alter table public.moderation_actions enable row level security;
alter table public.account_restrictions enable row level security;

-- reports・moderation_actions・account_restrictionsへの直接INSERT/UPDATE/DELETEは許可しない。
-- 通報登録・運営操作はEdge Functions（service_role）経由でのみ行う。

create policy reports_select_own_or_admin
  on public.reports
  for select
  to authenticated
  using (reporter_id = auth.uid() or public.is_admin());

create policy moderation_actions_select_admin
  on public.moderation_actions
  for select
  to authenticated
  using (public.is_admin());

-- 本人が対象（投稿者・コメント投稿者）の場合は理由通知として自分宛ての記録のみ参照できる
-- （docs/権限表.md 6節）。通報者情報は含まないためこの参照だけでは漏れない。
-- target_owner_idは挿入時点の所有者を記録しているため、削除後も参照できる。
create policy moderation_actions_select_target_owner
  on public.moderation_actions
  for select
  to authenticated
  using (target_owner_id = auth.uid());

create policy account_restrictions_select_own_or_admin
  on public.account_restrictions
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin());
