#!/usr/bin/env bash
# 同時実行の競合テスト。pgTAPは1セッションのため、2本のpsqlを並行して競合させて検証する。
# 前提：`supabase start`済みで、ローカルDBのコンテナが起動していること。
#   npm run supabase:start && npm run test:concurrency
set -uo pipefail

CONTAINER="${DB_CONTAINER:-supabase_db_kosodate-hitoiki-backend}"
FAILED=0

psql_run() { docker exec -i "$CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -q -t -A "$@"; }

check() { # check <説明> <期待値> <実測値>
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    echo "FAIL - $1（期待: $2 / 実測: $3）"
    FAILED=1
  fi
}

uuid() { printf '00000000-0000-0000-0000-%012x' "$1"; }

# ---------------------------------------------------------------------------
# 1. 通報：既存1件＋別の2人が同時に通報 → 3人到達で必ず自動非表示になる
# ---------------------------------------------------------------------------
U1=$(uuid 0xb1); U2=$(uuid 0xb2); U3=$(uuid 0xb3); U4=$(uuid 0xb4); POST=$(uuid 0xe1)
psql_run <<SQL
insert into auth.users (id) values ('$U1'),('$U2'),('$U3'),('$U4') on conflict do nothing;
insert into public.posts (id, author_id, post_type, body) values ('$POST','$U1','guchi','race') on conflict do nothing;
update public.posts set hidden_at = null where id = '$POST';
delete from public.reports where target_id = '$POST';
insert into public.reports (reporter_id, target_type, target_id, reason) values ('$U2','post','$POST','other');
SQL

( psql_run <<SQL
begin;
insert into public.reports (reporter_id, target_type, target_id, reason) values ('$U3','post','$POST','other');
select pg_sleep(3);
commit;
SQL
) >/dev/null &
sleep 1
psql_run <<SQL >/dev/null
begin;
insert into public.reports (reporter_id, target_type, target_id, reason) values ('$U4','post','$POST','other');
commit;
SQL
wait

check "同時通報で3人到達を取りこぼさない（未対応の通報者数）" "3" \
  "$(psql_run -c "select count(distinct reporter_id) from public.reports where target_id='$POST' and resolved_at is null")"
check "同時通報で3人到達したら自動一時非表示になる" "t" \
  "$(psql_run -c "select hidden_at is not null from public.posts where id='$POST'")"

psql_run <<SQL
delete from public.reports where target_id = '$POST';
delete from public.posts where id = '$POST';
delete from auth.users where id in ('$U1','$U2','$U3','$U4');
SQL

# ---------------------------------------------------------------------------
# 2. ニックネーム：Aが旧名を手放すのと同時にBがその名前を登録 → Bは予約で拒否される
# ---------------------------------------------------------------------------
A=$(uuid 0xc1); B=$(uuid 0xc2)
psql_run <<SQL
delete from public.profiles where id in ('$A','$B');
delete from public.nickname_reservations where normalized_nickname in ('racex','racey');
insert into auth.users (id) values ('$A'),('$B') on conflict do nothing;
insert into public.profiles (id, nickname) values ('$A','RaceX');
-- 30日の変更制限を満たすため、Aの最終変更日を過去にする（nickname列を更新しないためトリガーは動かない）。
update public.profiles set nickname_changed_at = now() - interval '31 days' where id = '$A';
SQL

( psql_run <<SQL >/dev/null
begin;
update public.profiles set nickname = 'RaceY' where id = '$A';
select pg_sleep(3);
commit;
SQL
) &
sleep 1
B_OUT=$(psql_run <<SQL 2>&1
begin;
insert into public.profiles (id, nickname) values ('$B','racex');
commit;
SQL
)
wait

check "旧名を手放すのと同時の登録は、予約により拒否される" "0" \
  "$(psql_run -c "select count(*) from public.profiles where id='$B'")"
case "$B_OUT" in
  *"この名前は現在使用できません"*) echo "ok   - 拒否理由は旧名の予約" ;;
  *) echo "FAIL - 拒否理由が想定と異なる: $B_OUT"; FAILED=1 ;;
esac
check "旧名はAのために予約されている" "racex" \
  "$(psql_run -c "select normalized_nickname from public.nickname_reservations where previous_owner_id='$A'")"

psql_run <<SQL
delete from public.profiles where id in ('$A','$B');
delete from public.nickname_reservations where normalized_nickname in ('racex','racey');
delete from auth.users where id in ('$A','$B');
SQL

# ---------------------------------------------------------------------------
# 3. ニックネーム：同じ名前を2人が同時に新規登録 → 片方だけ成功する
# ---------------------------------------------------------------------------
C=$(uuid 0xc3); D=$(uuid 0xc4)
psql_run <<SQL
delete from public.profiles where id in ('$C','$D');
insert into auth.users (id) values ('$C'),('$D') on conflict do nothing;
SQL

( psql_run <<SQL >/dev/null 2>&1
begin;
insert into public.profiles (id, nickname) values ('$C','Same');
select pg_sleep(2);
commit;
SQL
) &
sleep 1
psql_run <<SQL >/dev/null 2>&1
begin;
insert into public.profiles (id, nickname) values ('$D','ｓａｍｅ');
commit;
SQL
wait

check "同名の同時新規登録は1人だけ成功する" "1" \
  "$(psql_run -c "select count(*) from public.profiles where id in ('$C','$D')")"

psql_run <<SQL
delete from public.profiles where id in ('$C','$D');
delete from auth.users where id in ('$C','$D');
SQL

exit "$FAILED"
