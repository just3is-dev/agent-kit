#!/usr/bin/env bash
# Смоук-тест хуков: зовут ли они контракт проекта и молчат ли без него.
set -u
cd "$(dirname "$0")/.."
KIT="$PWD"
HOOKS="$KIT/hooks/scripts"

fail=0
pass=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; }

# assert_exit <ожидаемый exit> <описание> <команда...>
assert_exit() {
  local want="$1" name="$2"; shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then ok "$name"; else bad "$name (exit $got, ожидался $want)"; fi
}

run_hook() { # <hook> <payload-json>
  printf '%s' "$2" | "$HOOKS/$1"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp"
export AK_NOTIFY_FILE="$tmp/notify.log"

echo "синтаксис"
for f in "$HOOKS"/*.sh "$HOOKS"/lib/*.sh; do
  assert_exit 0 "bash -n $(basename "$f")" bash -n "$f"
done

echo "post-edit-check"
noc="$tmp/no-contract"; mkdir -p "$noc"; echo x > "$noc/a.ts"
assert_exit 0 "молчит без контракта" run_hook post-edit-check.sh "{\"tool_input\":{\"file_path\":\"$noc/a.ts\"}}"

proj="$tmp/proj"; mkdir -p "$proj/scripts" "$proj/src"
printf '#!/usr/bin/env bash\necho "check $*" >> "%s/calls"\nexit "${CHECK_EXIT:-0}"\n' "$tmp" > "$proj/scripts/check"
printf '#!/usr/bin/env bash\necho "test" >> "%s/calls"\nexit "${TEST_EXIT:-0}"\n' "$tmp" > "$proj/scripts/test"
chmod +x "$proj/scripts/check" "$proj/scripts/test"
echo x > "$proj/src/a.ts"
assert_exit 0 "зовёт scripts/check и проходит" run_hook post-edit-check.sh "{\"tool_input\":{\"file_path\":\"$proj/src/a.ts\"}}"
grep -q "check $proj/src/a.ts" "$tmp/calls" && ok "check получил путь файла" || bad "check не получил путь файла"
CHECK_EXIT=1 assert_exit 2 "блокирует при красном check" run_hook post-edit-check.sh "{\"tool_input\":{\"file_path\":\"$proj/src/a.ts\"}}"
assert_exit 0 "молчит для несуществующего файла" run_hook post-edit-check.sh "{\"tool_input\":{\"file_path\":\"$proj/src/nope.ts\"}}"

tpl="$tmp/kit/templates/node"; mkdir -p "$tpl/scripts"; cp "$proj/scripts/check" "$tpl/scripts/check"; echo x > "$tpl/scripts/test"
assert_exit 0 "не считает templates/ корнем проекта" run_hook post-edit-check.sh "{\"tool_input\":{\"file_path\":\"$tpl/scripts/test\"}}"

echo "stop-test"
export CLAUDE_PROJECT_DIR="$noc"
assert_exit 0 "молчит без контракта" run_hook stop-test.sh '{"stop_hook_active":false}'
export CLAUDE_PROJECT_DIR="$proj"
(cd "$proj" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
assert_exit 0 "молчит при чистом дереве" run_hook stop-test.sh '{"stop_hook_active":false}'
echo y > "$proj/src/a.ts"
: > "$tmp/calls"
TEST_EXIT=1 assert_exit 2 "блокирует при красных тестах" run_hook stop-test.sh '{"stop_hook_active":false}'
assert_exit 0 "пропускает, если Stop вызван самим хуком" run_hook stop-test.sh '{"stop_hook_active":true}'
assert_exit 0 "проходит при зелёных тестах" run_hook stop-test.sh '{"stop_hook_active":false,"session_id":"s1"}'
: > "$tmp/calls"
assert_exit 0 "повторный Stop на том же диффе" run_hook stop-test.sh '{"stop_hook_active":false}'
[ ! -s "$tmp/calls" ] && ok "тесты не перезапущены (кэш)" || bad "тесты перезапущены при неизменном диффе"

echo "уведомления"
run_hook prompt-timestamp.sh '{"session_id":"s2"}' >/dev/null 2>&1
ts="$tmp/agent-kit-notify/s2"
[ -f "$ts" ] && ok "prompt-timestamp пишет метку" || bad "prompt-timestamp не написал метку"
echo $(( $(date +%s) - 100 )) > "$ts"
echo z > "$proj/src/a.ts"
run_hook stop-test.sh '{"stop_hook_active":false,"session_id":"s2"}' >/dev/null 2>&1
grep -q "Задача завершена" "$AK_NOTIFY_FILE" && ok "уведомление после долгого хода" || bad "нет уведомления после долгого хода"
: > "$AK_NOTIFY_FILE"
run_hook notification.sh '{"message":"нужно разрешение"}' >/dev/null 2>&1
grep -q "нужно разрешение" "$AK_NOTIFY_FILE" && ok "notification шлёт сообщение" || bad "notification не отправил сообщение"

echo "guard"
g() { run_hook guard.sh "{\"tool_input\":{\"command\":\"$1\"}}"; }
assert_exit 2 "блокирует git commit --no-verify" g 'git commit --no-verify -m x'
assert_exit 2 "блокирует git push --no-verify" g 'git push --no-verify'
assert_exit 2 "блокирует push -f в main" g 'git push -f origin main'
assert_exit 2 "блокирует push --force в master" g 'git push --force origin master'
assert_exit 2 "блокирует push +main" g 'git push origin +main'
assert_exit 0 "пропускает force-with-lease в ветку" g 'git push --force-with-lease origin spec/001-x'
assert_exit 0 "пропускает обычный push в main" g 'git push origin main'
assert_exit 0 "пропускает git status" g 'git status'
assert_exit 0 "пропускает пустую команду" run_hook guard.sh '{}'

echo
echo "прошло: $pass, упало: $fail"
[ "$fail" -eq 0 ]
