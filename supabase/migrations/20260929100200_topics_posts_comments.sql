-- 話題・投稿・コメント（docs/スキーマ定義.md 3節）。

create table public.topics (
  id smallint generated always as identity primary key,
  label text not null,
  sort_order smallint not null default 0,
  is_active boolean not null default true
);

comment on table public.topics is '運営が用意する話題一覧。初期選択肢は未確定（docs/未決事項.md）。';

alter table public.topics enable row level security;

create policy topics_select_all
  on public.topics
  for select
  to anon, authenticated
  using (true);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users (id) on delete cascade,
  post_type text not null check (post_type in ('guchi', 'soudan', 'kotsu')),
  topic_id smallint references public.topics (id),
  body text not null check (char_length(body) between 1 and 1000),
  reaction_mode text not null default 'quiet_support'
    check (reaction_mode in ('quiet_support', 'want_comments')),
  comment_acceptance text check (comment_acceptance in ('open', 'closed')),
  hidden_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint posts_comment_acceptance_requires_want_comments
    check (comment_acceptance is null or reaction_mode = 'want_comments')
);

comment on table public.posts is '投稿。反応モードとコメント受付状態は別概念（docs/バックエンド設計.md 3節）。';

create index posts_created_at_id_idx on public.posts (created_at desc, id desc);
create index posts_author_id_idx on public.posts (author_id);

create trigger posts_set_updated_at
  before update on public.posts
  for each row execute function public.set_updated_at();

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  author_id uuid not null references auth.users (id) on delete cascade,
  parent_comment_id uuid references public.comments (id) on delete cascade,
  body text check (char_length(body) <= 500),
  deleted_at timestamptz,
  hidden_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comments_body_required_unless_deleted
    check (deleted_at is not null or (body is not null and char_length(body) >= 1))
);

comment on table public.comments is 'コメント・返信（1段階のみ）。削除は deleted_at によるソフト削除。';

create index comments_post_id_created_at_idx on public.comments (post_id, created_at asc);
create index comments_author_id_idx on public.comments (author_id);

create trigger comments_set_updated_at
  before update on public.comments
  for each row execute function public.set_updated_at();

-- 親コメントは同じ投稿に属し、返信への返信を禁止する制約（標準FKでは表現できないためトリガーで検証）。
create or replace function public.comments_validate_parent()
returns trigger
language plpgsql
as $$
declare
  parent record;
begin
  if new.parent_comment_id is not null then
    select post_id, parent_comment_id into parent
    from public.comments
    where id = new.parent_comment_id;

    if not found then
      raise exception '親コメントが見つかりません' using errcode = 'P0001';
    end if;

    if parent.post_id <> new.post_id then
      raise exception '親コメントは同じ投稿に属している必要があります' using errcode = 'P0001';
    end if;

    if parent.parent_comment_id is not null then
      raise exception '返信への返信はできません' using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

create trigger comments_before_insert_validate_parent
  before insert on public.comments
  for each row execute function public.comments_validate_parent();

-- 削除（deleted_at設定）時は本文を保持しない。
create or replace function public.comments_before_soft_delete()
returns trigger
language plpgsql
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    new.body := null;
  end if;
  return new;
end;
$$;

create trigger comments_before_update_soft_delete
  before update of deleted_at on public.comments
  for each row execute function public.comments_before_soft_delete();

alter table public.posts enable row level security;
alter table public.comments enable row level security;

-- posts・commentsへの直接INSERT/UPDATE/DELETEは許可しない。
-- 送信前チェック・受付状態・ブロック確認を伴うため、Edge Functions（service_role）
-- 経由でのみ書き込む（docs/バックエンド設計.md 1・4節、docs/API契約.md）。

create policy posts_select_public
  on public.posts
  for select
  to anon, authenticated
  using (hidden_at is null);

create policy posts_select_own_hidden
  on public.posts
  for select
  to authenticated
  using (author_id = auth.uid());

create policy posts_select_admin
  on public.posts
  for select
  to authenticated
  using (public.is_admin());

-- コメント本文はログイン必須。一時非表示は運営者のみ参照可（docs/権限表.md 3節）。
-- 親投稿が一時非表示の間はコメント・返信も一般利用者から隠す（Issue #7決定）。
create policy comments_select_authenticated
  on public.comments
  for select
  to authenticated
  using (
    hidden_at is null
    and exists (
      select 1 from public.posts p
      where p.id = comments.post_id and p.hidden_at is null
    )
  );

create policy comments_select_admin
  on public.comments
  for select
  to authenticated
  using (public.is_admin());
