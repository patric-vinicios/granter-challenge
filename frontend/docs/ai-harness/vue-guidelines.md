# Vue Engineering Guidelines

This project uses Vue 3 with the Composition API and `<script setup lang="ts">`. In templates,
refs are automatically unwrapped; in scripts, a `ref` requires `.value`.

## State and Reactivity

- Use `ref` for primitive values or values that will be replaced as a whole.
- Use `reactive` for cohesive objects mutated by property.
- Do not destructure reactive objects directly. Use `toRefs` or `storeToRefs` when you need to
  preserve reactivity.
- Model derived values with `computed`, keeping the getter pure.
- Avoid duplicating state that can be calculated from another source.

## Components

- Declare props with `defineProps<T>()` and treat them as readonly.
- Declare events with `defineEmits<T>()`; do not mutate received props.
- Use typed `v-model` only when the component has a real two-way editing contract.
- Keep views responsible for orchestration and reusable components focused on presentation.
- Use stable keys based on identifiers, never the list index when order can change.

## Effects and Composables

- Use `watch` and lifecycle hooks only for external effects, not to synchronize derived state.
- Remove listeners, timers, subscriptions and sockets in the matching cleanup.
- Extract reusable logic into composables named with the `use` prefix.
- Keep transport in `src/api`; composables coordinate effects, but do not mix UI and protocol.

## Pinia and Router

- Use Pinia only for state shared across routes or distant components.
- Keep mutations in actions and use `storeToRefs` when destructuring state or getters.
- Use `useRoute` and `useRouter` inside Vue context; do not import the router singleton in tests.
- Each test must create a router with `createMemoryHistory` and a fresh Pinia instance.

## Tests

- Verify observable behavior through role, label or text.
- Do not use Tailwind classes, internal structure or large snapshots as contracts.
- Await interactions and async updates; use `nextTick` only for direct mutation.
- Do not access the real network. Install explicit stubs for `fetch`, WebSocket or the Phoenix client.
- Restore timers, mocks, router and Pinia between tests.

## Diagnostics

- `vue-tsc` reports type issues in TypeScript and SFCs.
- ESLint reports unsafe or inconsistent static patterns.
- Vitest reports executed behavior that diverged from expectations.
- Fix the layer that failed; do not silence the tool or update the test without understanding the cause.

## Review Checklist

- Does the component use `<script setup lang="ts">` and typed boundaries?
- Is derived state in `computed`, without duplicated refs?
- Does destructuring preserve reactivity?
- Do props remain readonly and do changes leave through events or `v-model`?
- Do watchers and lifecycle hooks represent external effects and include cleanup?
- Does global state really deserve Pinia?
- Do views orchestrate while presentation components stay focused?
- Do tests use role, label or text instead of style classes?
- Does each test get its own Pinia and router and avoid real network access?
- Are `npm run verify` and `git diff --check` green?
