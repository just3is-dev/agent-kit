---
description: Подключить проект к agent-kit — контракт scripts/*, CLAUDE.md, CI, git
argument-hint: "[путь] [--local]"
---

Подключи проект к процессу agent-kit. Шаблоны: `${CLAUDE_PLUGIN_ROOT}/templates/`.
Принцип: существующее не перезаписывается, различия показываются.

`--local` в `$ARGUMENTS` — чужой проект: те же файлы, но ничего не попадает
в git (пути добавляются в `.git/info/exclude`), `CLAUDE.local.md` вместо
`CLAUDE.md`, CI не трогается.

1. **Осмотрись.** Директория — из `$ARGUMENTS` или текущая. Определи, пустая
   она или с кодом, есть ли git, какой стек по маркерам:
   `astro.config.*` → `astro`; иначе `package.json` → `node`; `pyproject.toml` → `python`; `Package.swift`,
   `*.xcodeproj` или `project.yml` → `swift-ios`; маркеры разных стеков в
   поддиректориях (`apps/*`, `services/*`, `packages/*`) → `monorepo`.
   Не очевидно — спроси одним AskUserQuestion. Для пустого проекта там же
   спроси название и одно предложение описания.

2. **Пустой проект — каркас штатным генератором**, не выдумывай структуру:
   `npx create-next-app@latest`, `npx @nestjs/cli new`,
   `npm create astro@latest -- --template minimal --typescript strict
   --no-git --yes`, `uv init`.
   Флаги неинтерактивные. Удали вложенные `.git`, которые создают
   генераторы. Для `swift-ios` генератора нет: минимальный `project.yml`
   для XcodeGen и точка входа, затем `xcodegen generate`.

3. **Наложи шаблоны.** Для каждого файла: нет в проекте — создай; есть и
   совпадает — пропусти молча; есть и отличается — не трогай, покажи
   diff в отчёте.
   - `templates/<стек>/scripts/*` → `scripts/`, исполняемые. Для `monorepo`:
     в каждый пакет скрипты его стека, в корень — диспетчер из
     `templates/monorepo/`. Для `swift-ios` ещё `swift-format` → `.swift-format`.
   - `templates/<стек>/ci.yml` → `.github/workflows/ci.yml`, только если в
     `.github/workflows/` пусто. Не при `--local`.
   - `templates/base/gitignore` → допиши в `.gitignore` недостающие строки.
   - `templates/base/CLAUDE.md` → `CLAUDE.md`, заполни `{{плейсхолдеры}}`;
     секцию про миграции удали, если БД нет. Существующий `CLAUDE.md` не
     переписывай: добавь в конец только секции «Контракт» и «Процесс».
     При `--local` — `templates/base/CLAUDE.local.md` → `CLAUDE.local.md`.
   - `templates/base/backlog.md` → `docs/backlog.md`.
   - При `--local` каждый созданный путь допиши в `.git/info/exclude`
     (`scripts/`, `CLAUDE.local.md`, `docs/`, `.swift-format`).

4. **Другой стек.** Возьми ближайший шаблон за образец и напиши скрипты сам
   с той же семантикой: `check [файлы]` быстрый, `test` без тестов не
   провал, `fix` молчалив. Первая строка комментария — `# agent-kit/<стек>`,
   по ней работает `/sync`.

5. **Проверь контракт вживую.** `./scripts/check` и `./scripts/test` должны
   пройти из корня. Поставь недостающие dev-зависимости тем менеджером,
   что уже в проекте: для node как минимум typescript, prettier, линтер и
   тест-раннер из тех, что уже выбрал генератор (vitest в проект без Vite
   требует ещё `vite`); для astro — `@astrojs/check`, `typescript`,
   `prettier`, `prettier-plugin-astro`, линтер по желанию. Не завершай инициализацию с красным контрактом.

6. **Git.** Нет репозитория — `git init -b main` и первый коммит
   `chore: подключить agent-kit`. Есть — коммит не делай, оставь
   пользователю. GitHub-репозиторий не создавай, упомяни `gh repo create`
   в отчёте, если remote нет.

7. **Отчёт:** что создано, что пропущено как совпадающее, где diff с
   шаблоном; хуки уже активны (check после правки, test перед завершением
   хода); дальше `/spec <идея>`.
