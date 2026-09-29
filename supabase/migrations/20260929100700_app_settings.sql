-- 運営設定（docs/スキーマ定義.md 8節）。
-- 登録直後のレート制限・新規登録停止は固定値でなく本テーブルで運営がトグルする（決定済み）。

create table public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_by uuid references auth.users (id),
  updated_at timestamptz not null default now()
);

comment on table public.app_settings is
  '例：signup_rate_limit, new_signup_halted, post_rate_limit_per_day。既定値は未確定（docs/未決事項.md）。';

create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function public.set_updated_at();

alter table public.app_settings enable row level security;

-- 参照・変更ともに運営者のみ（docs/権限表.md 8節）。変更はEdge Functions経由。
create policy app_settings_select_admin
  on public.app_settings
  for select
  to authenticated
  using (public.is_admin());
