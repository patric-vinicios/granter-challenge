---
name: vue-feature-implementer
description: Implement and validate Vue 3 frontend features from a backend PRD, feature specifications, and implemented API contracts. Use when Codex must plan, build, continue, review, or test a Granter Chat frontend feature identified by F01-F12, a backend docs feature folder, a REST endpoint, a Phoenix Channel event, or a product behavior such as authentication, contacts, conversations, groups, messaging, inbox, search, or presence.
---

# Vue Feature Implementer

Implement one vertical frontend slice from documented intent through tested Vue behavior. Read the
feature documentation and the backend contract before changing the frontend. Never change the
backend unless the user explicitly expands the scope.

## Establish scope and paths

1. Read the nearest `AGENTS.md` and the frontend `README.md` completely.
2. Run `git status --short` and preserve all existing work.
3. Resolve these locations from the repository rather than assuming the current directory:
   - frontend root containing `package.json` and `src/`;
   - repository root;
   - backend root containing `mix.exs`;
   - backend feature docs, normally `<backend>/docs/`.
4. Identify exactly one requested feature. Accept a feature id, feature-folder name, endpoint/event,
   or user-facing behavior. If the request spans independent features, sequence them explicitly and
   complete one vertical slice at a time.

Do not read every feature folder. Read the selected folder completely and load adjacent feature
documents only when the selected feature depends on them.

## Read sources in precedence order

Read all available sources below before planning:

1. The backend PRD, normally `<backend>/docs/prd.md`. If the canonical root PRD is tracked but
   deleted in the worktree, inspect it with `git show HEAD:docs/prd.md` without restoring it.
2. The selected `<backend>/docs/FNN-*/spec.md` and `plan.md` files.
3. Backend router, controllers, JSON renderers, contexts, schemas, channels and tests touched by the
   feature.
4. Existing frontend routes, views, components, stores, composables, API modules, types and tests.
5. Visual references already stored in the repository when the feature changes UI.

Apply this source-of-truth rule:

- PRD and feature specs define intended behavior and acceptance criteria.
- Executable backend code and backend tests define the contract currently available for integration.
- Existing frontend behavior defines compatibility that must be preserved.
- Never invent a route, field, error code, topic or channel event to reconcile a gap.
- If documentation and implementation differ materially, report the exact difference. Continue with
  separable UI/domain work only when it remains truthful; otherwise ask for direction.

## Produce a feature brief

Before editing, state a compact brief containing:

- feature id and user outcome;
- entry route or UI surface;
- required REST methods/paths and request/response/error shapes;
- required socket topic/events, acknowledgements and cleanup, when applicable;
- UI states: initial, loading, empty, success, validation failure, server failure and reconnecting;
- frontend files expected to change;
- acceptance criteria mapped to tests;
- documented contract gaps or explicit assumptions.

If the user asks only for a plan or review, stop before editing. Otherwise implement after presenting
the brief.

## Design the vertical slice

Use the smallest set of layers that gives the feature a clear owner:

- `src/types/`: shared domain and transport types that have real consumers;
- `src/api/`: HTTP/socket transport, serialization and error normalization;
- `src/stores/`: cross-route or cross-component state only;
- `src/composables/`: reusable Vue orchestration, effects and lifecycle cleanup;
- `src/components/`: focused reusable UI;
- `src/views/`: route-level orchestration;
- `src/router/`: routes and guards;
- `*.spec.ts`: behavior and contract tests close to their subject.

Do not add every layer by default. Keep local state in a view or component until it is genuinely
shared. Do not create generic repositories, service locators or speculative abstractions.

## Follow Vue 3 rules

- Use Composition API and `<script setup lang="ts">`.
- Use `ref` for primitive or replaceable values and `reactive` for cohesive objects.
- Access `.value` in script; rely on template unwrapping in templates.
- Derive values with pure `computed` getters. Do not synchronize duplicate state with `watch`.
- Use watchers and lifecycle hooks only for external effects and always register cleanup.
- Treat `defineProps<T>()` results as readonly. Communicate through typed `defineEmits<T>()` or a
  deliberate typed `v-model` contract.
- Use Pinia only for shared state. Use `storeToRefs` when destructuring state/getters and actions for
  mutations.
- Use stable ids as `v-for` keys and never render untrusted content with `v-html`.
- Keep views orchestral and extract UI only when the extracted component has a coherent contract.
- Preserve the established design system and desktop behavior unless the feature requires change.

## Integrate contracts safely

- Centralize base URLs and authentication rather than reading environment or storage throughout UI.
- Treat external payloads as untrusted at the transport boundary. Validate or decode fields that
  drive control flow; do not use an unchecked `as Type` cast.
- Normalize the backend error envelope once and preserve machine-readable error codes.
- Model cancellation or stale responses for route changes and repeated searches.
- Keep credentials out of logs, fixtures and error messages.
- Do not call the real network in unit/component tests.

For Phoenix Channels:

- connect with the documented credential and topic;
- join and leave with component/composable lifecycle;
- register and unregister event handlers deterministically;
- handle join failure, reconnect and duplicate delivery;
- reconcile optimistic messages with persisted acknowledgements by stable id/ref;
- preserve server ordering and do not synthesize delivery guarantees.

## Implement in verified increments

1. Run the smallest relevant baseline before editing. Prefer `npm run verify`; if it already fails,
   record the exact failure and use narrower green commands.
2. Implement transport/types before consumers only when the feature actually uses them.
3. Add state/orchestration, then UI wiring, then route integration.
4. After each behavior, run its targeted test and `npm run typecheck` when types changed.
5. Avoid unrelated cleanup, broad formatting and feature expansion.
6. Do not modify backend files, backend docs or the PRD.

## Test the feature

Cover behavior, not internal implementation:

- component rendering and accessible interaction by role, label or text shown in the UI;
- loading, empty, success and error states that the user can observe;
- store/composable transitions and lifecycle cleanup;
- request method, path, headers, body and normalized errors through explicit fakes;
- channel join, event handling, acknowledgement, deduplication and leave through a fake socket;
- route params and navigation with a fresh `createMemoryHistory` router;
- a fresh Pinia per test and restored timers/mocks after every test.

Never select Tailwind classes, use large snapshots, contact the real backend, reuse the production
router singleton or make sleeps/timeouts the synchronization mechanism.

## Validate completion

Run all of the following that exist:

```bash
npm run test:run -- <changed-specs>
npm run test:changed -- <changed-source-files>
npm run verify
git diff --check
git status --short
```

Before reporting success:

- map every selected acceptance criterion to implemented behavior and a test or explicit manual
  check;
- inspect the final diff for accidental backend or unrelated frontend changes;
- distinguish pre-existing failures from regressions;
- state any part that remains mocked because the backend contract is not implemented;
- never claim live integration from passing fake-based tests alone.

Report the user-facing outcome first, then files/layers changed, validation evidence, assumptions
and remaining contract gaps.
