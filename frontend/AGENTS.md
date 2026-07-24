# AGENTS.md - Frontend (Vue.js)

**Project:** Granter Chat — Real-time messaging SPA.

## Project Overview

- **Main Stack**: Vue 3 (Composition API + `<script setup lang="ts">`), Vite, TypeScript 6.x, Pinia, Vue Router 5.2, Tailwind CSS 4, Phoenix WebSocket client.
- **Architecture**: Vertical feature slices in `src/features/`, shared utilities in `src/shared/`. Views orchestrate, components focus on presentation.
- **Goal**: Implement chat features (auth, contacts, conversations, realtime messages) while respecting the Elixir backend contracts.
- **Key Rules**:
  - Never change backend code from the frontend directory.
  - Preserve existing code. Always read README, docs/, backend contracts and current implementation first.
  - Only create new abstractions/stores/features when there is a real consumer.
  - Always run `npm run verify` before finishing any task.

## Essential Commands

| Purpose                   | Command                                          |
|---------------------------|--------------------------------------------------|
| Dev server + HMR          | `npm run dev`                                    |
| Architecture gate         | `./scripts/architecture`                         |
| Dependency graph gate     | `./scripts/dep-cruiser`                          |
| Lint                      | `./scripts/eslint`                               |
| Unused code/deps gate     | `./scripts/nip`                                  |
| Type check                | `./scripts/tsc`                                  |
| Tests (watch)             | `npm run test`                                   |
| Automated tests           | `./scripts/tests`                                |
| Affected tests            | `npm run test:changed -- <files>`                |
| Full verification         | `./scripts/run-gate`                             |
| Preview build             | `npm run preview`                                |

Always run `./scripts/run-gate && git diff --check` at the end. `npm run verify` remains a
compatibility wrapper for the same full gate.

## Vue Guidelines (Best Practices)

- Use Composition API with `<script setup lang="ts">`.
- **Reactivity**:
  - `ref()` for primitives or full replacement.
  - `reactive()` for cohesive objects.
  - `computed()` for derived state (never duplicate state).
- **Components**: `defineProps<T>()` (readonly), `defineEmits<T>()`, stable `:key` with IDs.
- **Global State**: Pinia only for shared state. Use `storeToRefs()` when destructuring.
- **Router**: `useRoute()`, `useRouter()`, navigation guards. Tests must use `createMemoryHistory`.
- **Side Effects**: `watch` and lifecycle hooks only for external effects with proper cleanup.
- **Composables**: Extract reusable logic with `use*` prefix.
- **Testing**: Assert by `role`, `label`, or text. Stub `fetch`/WebSocket. Each test gets fresh Pinia + Router.

See also: `docs/ai-harness/vue-guidelines.md`, `docs/architecture/frontend.md`, and the UI
direction references in `docs/design-system/directions/`.

## Recommended Libraries for AI Agents in Vue.js

Current 2026 recommendations:

1. **@ai-sdk/vue** (Vercel AI SDK) — Best for chat UI and streaming.
   - `useChat`, `useCompletion`, `useObject` composables.

2. **Eve by Vercel** — Full agent framework with excellent Vue support (`useEveAgent` composable).

3. **vuejs-ai/skills** — Specialized skills for Vue 3 agents (highly recommended).
   - Install: `npx skills add vuejs-ai/skills`

4. **Others**:
   - **a2ui-vue**: For agents to render dynamic UIs via structured JSON.
   - Official: Pinia + Vue Router (already in use).

**Tip**: Prefix prompts with "use vue skill" or load skills via `.agents/skills/`.

## Agent Workflow

**Before editing**:
- Run `git status --short`
- Execute relevant baseline tests.

**During**:
- Make small changes + run targeted test after each behavior.
- Never use real network in unit tests.

**After**:
- Run `npm run verify`
- Review diff and note any pre-existing failures separately.

## Boundaries & Safety

- Do not implement adjacent features without explicit request.
- Never silence lint, type, or test errors.
- Treat all external input as `unknown` and validate at boundaries.
- Keep clear separation: UI → Feature → Shared (API/Realtime).

Follow Vue guidelines and project architecture strictly. Executable code + tests take precedence.
