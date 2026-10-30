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
assert_exit 0 "не смотрит в строку echo" g 'echo \"git commit --no-verify\"'
assert_exit 2 "ловит git после &&" g 'cd x && git commit --no-verify -m x'
assert_exit 2 "ловит git в подоболочке" g '(git push -f origin main)'
assert_exit 0 "не смотрит в тело heredoc" g 'cat > note.md <<EOF\nзапрещено git commit --no-verify и git push -f origin main\nEOF'
assert_exit 2 "ловит git перед heredoc" g 'git commit --no-verify -F- <<EOF\nmsg\nEOF'

echo "monorepo dispatcher"
mono="$tmp/mono"; mkdir -p "$mono/scripts" "$mono/apps/web/scripts" "$mono/apps/api/scripts" "$mono/apps/web/src" "$mono/apps/api/src"
cp "$KIT/templates/monorepo/scripts/"* "$mono/scripts"
for pkg in web api; do
  printf '#!/usr/bin/env bash\necho "%s check $*" >> "%s/mono-calls"\n' "$pkg" "$tmp" > "$mono/apps/$pkg/scripts/check"
  printf '#!/usr/bin/env bash\necho "%s test" >> "%s/mono-calls"\n' "$pkg" "$tmp" > "$mono/apps/$pkg/scripts/test"
  printf '#!/usr/bin/env bash\necho "%s fix $*" >> "%s/mono-calls"\n' "$pkg" "$tmp" > "$mono/apps/$pkg/scripts/fix"
  chmod +x "$mono/apps/$pkg/scripts/"*
done
chmod +x "$mono/scripts/"*
echo x > "$mono/apps/web/src/a.ts"
: > "$tmp/mono-calls"
assert_exit 0 "check по файлу идёт в свой пакет" "$mono/scripts/check" "$mono/apps/web/src/a.ts"
grep -q "web check $mono/apps/web/src/a.ts" "$tmp/mono-calls" && ok "web получил файл" || bad "web не получил файл"
grep -q "api" "$tmp/mono-calls" && bad "api вызван без своих файлов" || ok "api не вызван"
: > "$tmp/mono-calls"
assert_exit 0 "check без аргументов — все пакеты" "$mono/scripts/check"
[ "$(grep -c check "$tmp/mono-calls")" -eq 2 ] && ok "оба пакета проверены" || bad "не все пакеты проверены"
: > "$tmp/mono-calls"
assert_exit 0 "test — все пакеты" "$mono/scripts/test"
[ "$(grep -c test "$tmp/mono-calls")" -eq 2 ] && ok "оба пакета протестированы" || bad "не все пакеты протестированы"
printf '#!/usr/bin/env bash\nexit 1\n' > "$mono/apps/api/scripts/test"
assert_exit 1 "падение пакета — провал корня" "$mono/scripts/test"

echo "шаблоны"
for s in "$KIT"/templates/*/scripts/check "$KIT"/templates/*/scripts/test "$KIT"/templates/*/scripts/fix; do
  head -3 "$s" | grep -q '^# agent-kit/' && ok "маркер в $(echo "$s" | sed "s|$KIT/templates/||")" || bad "нет маркера agent-kit/<стек> в $s"
done

echo "тексты процесса"
# Тексты команд и скилла ссылаются друг на друга: формат имени теста и правила
# вычёркивания критериев должны совпадать везде, иначе /verify не найдёт тест.
contains() { grep -qF -- "$2" "$KIT/$1"; }
for f in skills/tdd/SKILL.md commands/work.md commands/verify.md; do
  contains "$f" 'SPEC-NNN AC-' && ok "$f: имя теста с номером спеки" || bad "$f: нет формата «SPEC-NNN AC-N:»"
done
for f in skills/tdd/SKILL.md commands/work.md; do
  # Пример имени теста — это «`AC-N: текст`»; голое «`AC-1:`» без текста допустимо как контрпример.
  grep -qE '`AC-[0-9N]+: ' "$KIT/$f" && bad "$f: пример имени теста без номера спеки" || ok "$f: нет голого «AC-N:» в примерах"
done
for f in skills/tdd/SKILL.md commands/work.md; do
  contains "$f" 'проверен мутацией' && ok "$f: правило про сразу зелёные тесты" || bad "$f: нет правила про мутацию"
done
contains skills/tdd/SKILL.md 'вычеркнут в спеке' && ok "tdd: исключение для вычеркнутых критериев" || bad "tdd: нет исключения для вычеркнутых критериев"
contains commands/verify.md 'отсылка' && ok "verify: проверяет отсылку у зачёркнутых" || bad "verify: не проверяет отсылку у зачёркнутых"
contains commands/spec.md '## Спека меняет или забирает критерии закрытой спеки' && ok "spec: раздел про правку закрытых спек" || bad "spec: нет раздела про правку закрытых спек"
contains commands/spec.md 'одной задачей целиком' && ok "spec: критерий закрывается одной задачей" || bad "spec: нет правила «один критерий — одна задача»"
contains templates/process/spec-template.md 'ровно в одной задаче' && ok "шаблон спеки: подсказка про одну задачу" || bad "шаблон спеки: нет подсказки про одну задачу"
[ "$(grep -c 'молча' "$KIT/commands/spec.md")" -eq 1 ] && ok "spec: правило про совет со стороны записано один раз" || bad "spec: правило про совет со стороны пропало или продублировано"

echo "тексты инициализации и документация"
contains commands/init.md '@types/node' && ok "init: ставит @types/node для astro с vitest" || bad "init: нет @types/node"
contains commands/init.md 'AGENTS.md' && ok "init: решение про AGENTS.md от генератора" || bad "init: нет решения про AGENTS.md"
contains commands/init.md 'py.typed' && ok "init: py.typed для python" || bad "init: нет py.typed для python"
contains commands/init.md 'command -v uv' && ok "init: проверяет наличие uv" || bad "init: не проверяет uv"
contains commands/init.md 'workspaces' && ok "init: workspaces → monorepo" || bad "init: не распознаёт workspaces"
contains commands/init.md 'в корне проекта' && ok "init: предупреждает про Stop-хук вне корня сессии" || bad "init: нет предупреждения про Stop-хук"
contains skills/tdd/SKILL.md 'docstring' && ok "tdd: маркер в docstring/комментарии для pytest и XCTest" || bad "tdd: нет формы маркера для pytest/XCTest"
contains skills/tdd/SKILL.md 'заглушка' && ok "tdd: заглушка перед красным тестом в компилируемом коде" || bad "tdd: нет правила про заглушку"
contains templates/base/CLAUDE.local.md '/review' && bad "CLAUDE.local.md: ссылается на /review, которого нет" || ok "CLAUDE.local.md: без /review"
for f in templates/node/tsconfig.json templates/swift-ios/project.yml templates/swift-ios/App.swift templates/swift-ios/gitignore; do
  [ -f "$KIT/$f" ] && ok "есть $f" || bad "нет $f"
done
python3 -m json.tool "$KIT/templates/node/tsconfig.json" >/dev/null && ok "tsconfig шаблона node валиден" || bad "tsconfig шаблона node невалиден"
grep -q '{{Name}}' "$KIT/templates/swift-ios/project.yml" && ok "project.yml: плейсхолдер {{Name}}" || bad "project.yml: нет {{Name}}"
grep -q 'setup-uv@v5' "$KIT/templates/python/ci.yml" && bad "python ci.yml: устаревший setup-uv@v5" || ok "python ci.yml: setup-uv не v5"
grep -q -- '--log-level warn' "$KIT/templates/node/scripts/fix" && ok "node fix: prettier молчит" || bad "node fix: prettier шумит"
for f in commands/spec.md commands/init.md; do
  grep -qE '^#+ .*\$ARGUMENTS' "$KIT/$f" && bad "$f: \$ARGUMENTS в заголовке" || ok "$f: \$ARGUMENTS не в заголовках"
done
contains commands/verify.md 'lock-файлы' && ok "verify: инфраструктура не считается расхождением" || bad "verify: нет списка инфраструктурных файлов"
contains templates/base/CLAUDE.md '## Внешние материалы' && ok "CLAUDE.md шаблона: секция про внешние материалы" || bad "CLAUDE.md шаблона: нет секции про внешние материалы"
contains templates/astro/ci.yml 'playwright install' && ok "astro ci.yml: подсказка про браузер Playwright" || bad "astro ci.yml: нет подсказки про Playwright"
contains README.md 'settings.local.json' && ok "README: подключение через settings.local.json" || bad "README: нет подключения через settings.local.json"
contains README.md '"source": "directory"' && ok "README: пример для локального клона (проверенный)" || bad "README: нет примера с directory"
for f in "$KIT"/commands/*.md; do
  lines=$(wc -l < "$f" | tr -d ' ')
  [ "$lines" -le 80 ] && ok "$(basename "$f"): $lines строк (принцип: не длиннее 80)" || bad "$(basename "$f"): $lines строк, больше 80"
done

echo
echo "прошло: $pass, упало: $fail"
[ "$fail" -eq 0 ]
