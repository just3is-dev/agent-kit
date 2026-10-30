---
description: Подключить проект к agent-kit — контракт scripts/*, CLAUDE.md, CI, git
argument-hint: "[путь] [--local]"
---

Аргумент: `$ARGUMENTS` (путь и/или `--local`).
Подключи проект к процессу agent-kit. Шаблоны: `${CLAUDE_PLUGIN_ROOT}/templates/`.
`--local` — чужой проект: те же файлы, но ничего не попадает в git (пути
добавляются в `.git/info/exclude`), `CLAUDE.local.md` вместо `CLAUDE.md`,
CI не трогается.

1. **Осмотрись.** Директория — из аргумента или текущая. Определи, пустая
   она или с кодом, есть ли git, какой стек по маркерам: `workspaces` в
   `package.json` или маркеры разных стеков в поддиректориях (`apps/*`,
   `services/*`, `packages/*`) → `monorepo`; `astro.config.*` → `astro`;
   иначе `package.json` → `node`; `pyproject.toml` → `python`;
   `Package.swift`, `*.xcodeproj` или `project.yml` → `swift-ios`.
   Не очевидно — спроси одним AskUserQuestion; для пустого проекта там же
   стек, название и одно предложение описания.

2. **Пустой проект — каркас штатным генератором**, не выдумывай структуру:
   `npx create-next-app@latest`, `npx @nestjs/cli new`,
   `npm create astro@latest -- --template minimal --typescript strict
   --no-git --yes`. Библиотека или CLI на node — `npm init -y`,
   `templates/node/tsconfig.json`, dev-зависимости typescript,
   `@types/node`, oxlint, prettier, vitest. Python — сначала `command -v uv`
   (нет — остановись, предложи `brew install uv`), затем
   `uv init --package --vcs none --author-from none --name <имя>
   --description <описание>` и пустой `src/<пакет>/py.typed`: без него
   mypy не видит типов своего пакета в тестах. Флаги неинтерактивные.
   Удали вложенные `.git`, которые создают генераторы. Для `swift-ios`
   генератора нет: `templates/swift-ios/project.yml` → `project.yml`,
   `App.swift` → `<Name>/App.swift`, замени `{{Name}}` и `{{BundleIdPrefix}}`
   (из вопроса или `dev.local`), затем `xcodegen generate`. `.xcodeproj`
   в git не хранится: его пересобирает `scripts/test`.

3. **Наложи шаблоны.** Для каждого файла: нет в проекте — создай; есть и
   совпадает — пропусти молча; есть и отличается — не трогай, покажи
   diff в отчёте.
   - `templates/<стек>/scripts/*` → `scripts/`, исполняемые. Для `monorepo`:
     в каждый пакет скрипты его стека, в корень — диспетчер из
     `templates/monorepo/`; файлы вне пакетов никто не проверяет. Для
     `swift-ios` ещё `swift-format` → `.swift-format`.
   - `templates/<стек>/ci.yml` → `.github/workflows/ci.yml`, только если в
     `.github/workflows/` пусто. Не при `--local`.
   - `templates/base/gitignore` и `templates/<стек>/gitignore`, если есть,
     → допиши в `.gitignore` недостающие строки.
   - `AGENTS.md` от генератора оставь; в начало `CLAUDE.md` строку «Правила
     для агентов — в этом файле; `AGENTS.md` сгенерирован стеком, его не редактируем»;
   - `templates/base/CLAUDE.md` → `CLAUDE.md`, заполни `{{плейсхолдеры}}`;
     секции с условием в комментарии (миграции, внешние материалы) удали,
     если условие не выполнено. Существующий `CLAUDE.md` не переписывай:
     добавь в конец только секции «Контракт» и «Процесс». При `--local` —
     `templates/base/CLAUDE.local.md` → `CLAUDE.local.md`.
   - `templates/base/backlog.md` → `docs/backlog.md`.
   - При `--local` каждый созданный путь допиши в `.git/info/exclude`
     (`scripts/`, `CLAUDE.local.md`, `docs/`, `.swift-format`).

4. **Другой стек.** Ближайший шаблон за образец, та же семантика: `check
   [файлы]` быстрый, `test` без тестов не провал, `fix` молчалив. Первая
   строка комментария — `# agent-kit/<стек>`, по ней работает `/sync`.

5. **Проверь контракт вживую.** `./scripts/check` и `./scripts/test` должны
   пройти из корня. Поставь недостающие dev-зависимости тем менеджером,
   что уже в проекте: для node как минимум typescript, prettier, линтер и
   тест-раннер из тех, что уже выбрал генератор; для astro — `@astrojs/check`,
   `typescript`, `prettier`, `prettier-plugin-astro`, линтер по желанию;
   если тесты на vitest читают файлы или `dist/` через `node:*` — ещё
   `@types/node` и `"types": ["node"]` в tsconfig пакета не в корне. В
   monorepo dev-зависимости могут жить в корне: скрипты ищут их по
   родительским `package.json`. Не завершай инициализацию с красным контрактом.

6. **Git.** Нет репозитория — `git init -b main` и коммит `chore: подключить
   agent-kit`. Есть — коммит оставь пользователю. GitHub не создавай; нет
   remote — упомяни `gh repo create`.

7. **Отчёт:** что создано, что пропущено как совпадающее, где diff с
   шаблоном; хуки активны: check после правки — сразу, test перед концом
   хода — только когда сессия открыта в корне проекта (init запускался с
   путём — открой сессию в папке проекта); дальше `/spec <идея>`.
