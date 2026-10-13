#!/usr/bin/env bash
# PostToolUse(Edit|Write): прогоняет контрактный scripts/check по изменённому
# файлу. Нет контракта — молчим: плагин безопасен в любом репозитории.
set -u

payload=$(cat)
. "$(cd "$(dirname "$0")" && pwd)/lib/json-field.sh"
file_path=$(json_field "$payload" "tool_input.file_path" "")
[ -n "$file_path" ] || exit 0
[ -f "$file_path" ] || exit 0

# Корень проекта — ближайший родитель файла со scripts/check.
# Каталоги внутри templates/ пропускаем: там лежат заготовки контракта
# для других проектов, а не контракт этого.
dir=$(cd "$(dirname "$file_path")" 2>/dev/null && pwd) || exit 0
root=""
while [ "$dir" != "/" ]; do
  case "$dir" in
    */templates/*) ;;
    *) if [ -x "$dir/scripts/check" ]; then root="$dir"; break; fi ;;
  esac
  dir=$(dirname "$dir")
done
[ -n "$root" ] || exit 0

case "$file_path" in
  "$root"/templates/*) exit 0 ;;
esac

output=$(cd "$root" && ./scripts/check "$file_path" 2>&1)
status=$?
if [ "$status" -ne 0 ]; then
  {
    echo "scripts/check провалился для $file_path (exit $status). Исправь ошибки, прежде чем продолжать:"
    printf '%s\n' "$output" | tail -n 60
  } >&2
  exit 2
fi
exit 0
