-- 保存・自分だけの非表示・ブロック・ミュート（docs/スキーマ定義.md 5節）。
-- いずれも自由記述を伴わない単純な関係のトグルのため、本人限定でRLSから直接操作可能とする。

create table public.saved_posts (
  user_id uuid not null references auth.users (id) on delete cascade,
  post_id uuid not null references public.posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

comment on table public.saved_posts is '利用者と保存対象投稿。他者へ保存数・保存した事実を公開しない。';

alter table public.saved_posts enable row level security;

create policy saved_posts_all_own
  on public.saved_posts
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table public.hidden_items (
  user_id uuid not null references auth.users (id) on delete cascade,
  target_type text not null check (target_type in ('post', 'comment')),
  target_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (user_id, target_type, target_id)
);

comment on table public.hidden_items is '本人だけに非表示とする投稿・コメント。運営の一時非表示（hidden_at）とは独立。';

alter table public.hidden_items enable row level security;

create policy hidden_items_all_own
  on public.hidden_items
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table public.blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_no_self_block check (blocker_id <> blocked_id)
);

comment on table public.blocks is 'ブロックした利用者と対象利用者。相手には通知しない（決定済み）。';

alter table public.blocks enable row level security;

create policy blocks_select_own
  on public.blocks
  for select
  to authenticated
  using (blocker_id = auth.uid());

create policy blocks_insert_own
  on public.blocks
  for insert
  to authenticated
  with check (blocker_id = auth.uid());

create policy blocks_delete_own
  on public.blocks
  for delete
  to authenticated
  using (blocker_id = auth.uid());

-- ブロックされている事実は相手に公開しない（blocked_id = auth.uid() でのSELECTは許可しない）。

create table public.muted_topics (
  user_id uuid not null references auth.users (id) on delete cascade,
  topic_id smallint not null references public.topics (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, topic_id)
);

alter table public.muted_topics enable row level security;

create policy muted_topics_all_own
  on public.muted_topics
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table public.muted_words (
  user_id uuid not null references auth.users (id) on delete cascade,
  word text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, word)
);

comment on table public.muted_words is '上限件数は未確定（docs/未決事項.md）。上限はEdge Function側で検証する。';

alter table public.muted_words enable row level security;

create policy muted_words_all_own
  on public.muted_words
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
