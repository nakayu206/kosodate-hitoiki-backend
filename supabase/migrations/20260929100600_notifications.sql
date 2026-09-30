-- 通知（docs/スキーマ定義.md 7節）。

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  notification_type text not null
    check (notification_type in ('comment', 'reply', 'reaction_digest', 'moderation')),
  actor_id uuid references auth.users (id),
  post_id uuid references public.posts (id) on delete cascade,
  comment_id uuid references public.comments (id) on delete cascade,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

comment on table public.notifications is '本人向けのお知らせ。集約通知（reaction_digest）の生成方式は未確定（#19）。';

create index notifications_user_id_created_at_idx on public.notifications (user_id, created_at desc);

-- 自由コメントは投稿者へ、返信は返信先コメントの投稿者へ通知する。
-- 自分自身への通知は行わない（決定済み、docs/バックエンド設計.md 3節）。
create or replace function public.comments_after_insert_notify()
returns trigger
language plpgsql
as $$
declare
  post_author uuid;
  parent_author uuid;
begin
  if new.parent_comment_id is null then
    select author_id into post_author from public.posts where id = new.post_id;
    if post_author is not null and post_author <> new.author_id then
      insert into public.notifications (user_id, notification_type, actor_id, post_id, comment_id)
      values (post_author, 'comment', new.author_id, new.post_id, new.id);
    end if;
  else
    select author_id into parent_author from public.comments where id = new.parent_comment_id;
    if parent_author is not null and parent_author <> new.author_id then
      insert into public.notifications (user_id, notification_type, actor_id, post_id, comment_id)
      values (parent_author, 'reply', new.author_id, new.post_id, new.id);
    end if;
  end if;
  return null;
end;
$$;

create trigger comments_after_insert_notify
  after insert on public.comments
  for each row execute function public.comments_after_insert_notify();

create table public.notification_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  comments_enabled boolean not null default true,
  replies_enabled boolean not null default true,
  reactions_enabled boolean not null default true,
  push_enabled boolean not null default true
);

create table public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null check (platform in ('ios', 'android')),
  device_token text not null unique,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table public.push_devices is '配信サービス（FCM等）の選定は未確定（#19）。';

alter table public.notifications enable row level security;
alter table public.notification_settings enable row level security;
alter table public.push_devices enable row level security;

create policy notifications_select_own
  on public.notifications
  for select
  to authenticated
  using (user_id = auth.uid());

create policy notifications_update_own_is_read
  on public.notifications
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy notification_settings_all_own
  on public.notification_settings
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy push_devices_all_own
  on public.push_devices
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
