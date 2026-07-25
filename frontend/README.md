# Granter Chat Frontend

Vue 3 single-page application for Granter Chat, a real-time messaging product with authentication,
contacts, private conversations, groups, inbox search, persisted message history and Phoenix
WebSocket integration.

The frontend is built as a typed, feature-oriented Vue application. Views compose user workflows,
feature modules own domain behavior, and shared infrastructure centralizes HTTP, realtime,
configuration and storage concerns.

## Table Of Contents

- [Tech Stack](#tech-stack)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Environment Variables](#environment-variables)
- [Production Readiness](#production-readiness)
- [Quality Gates](#quality-gates)
- [Available Commands](#available-commands)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Testing](#testing)
- [Design References](#design-references)
- [TypeScript Version](#typescript-version)

## Tech Stack

- Vue 3 with Composition API and `<script setup lang="ts">`
- Vite
- TypeScript 6.x
- Pinia
- Vue Router
- Tailwind CSS 4
- Phoenix JavaScript client
- Vitest, Testing Library, jsdom
- ESLint, Dependency Cruiser, Knip and `vue-tsc`

## Requirements

- Node.js 22 or newer
- npm

This project has been validated with Node.js `22.22.3`.

## Getting Started

Install dependencies:

```bash
npm install
```

Create a local environment file:

```bash
cp .env.example .env
```

Start the development server:

```bash
npm run dev
```

The app runs at `http://localhost:5173` by default.

## Environment Variables

Environment variables are read by Vite and typed in [`src/env.d.ts`](src/env.d.ts).

| Variable | Default local value | Purpose |
| --- | --- | --- |
| `VITE_API_URL` | `http://localhost:4000/api` | REST API base URL |
| `VITE_SOCKET_URL` | `ws://localhost:4000/socket` | Phoenix socket endpoint |

Local development may rely on those defaults. Production builds must configure both variables
explicitly and must not point to `localhost`.

Use [`./.env.production.example`](./.env.production.example) as the production template:

```bash
cp .env.production.example .env.production
```

For split frontend/backend deployments, use HTTPS/WSS absolute URLs. For same-origin deployments,
use `/api` and `/socket`.

## Production Readiness

Before publishing a production build:

1. Configure `VITE_API_URL` and `VITE_SOCKET_URL` for the target environment.
2. Run the full frontend gate:

   ```bash
   npm run verify
   git diff --check
   ```

3. Build the static app:

   ```bash
   npm run build
   ```

4. Smoke the generated bundle locally:

   ```bash
   npm run preview
   ```

The production bundle is emitted to `dist/`. Static hosts should serve `index.html` as the fallback
for application routes such as `/login`, `/register` and `/inbox`. The files
[`public/_redirects`](public/_redirects) and [`public/_headers`](public/_headers) provide SPA
fallback, immutable caching for versioned assets and basic browser hardening on hosts that support
those conventions.

## Quality Gates

Quality gates live in [`scripts/`](scripts/) and should be run directly. This keeps the workflow
the same for developers and AI agents.

| Gate | Command | Purpose |
| --- | --- | --- |
| Architecture | `./scripts/architecture` | Enforces local architectural dependency rules |
| Dependency graph | `./scripts/dep-cruiser` | Detects dependency graph violations with Dependency Cruiser |
| Lint | `./scripts/eslint` | Runs ESLint with zero warnings allowed |
| Unused code and dependencies | `./scripts/nip` | Runs Knip against files, exports and dependencies |
| Type check | `./scripts/tsc` | Runs `vue-tsc` across TypeScript and Vue SFCs |
| Tests | `./scripts/tests` | Runs the automated Vitest suite once |
| Full gate | `./scripts/run-gate` | Runs all quality gates and the production build |

Before finishing a change, run:

```bash
./scripts/run-gate
git diff --check
```

`npm run verify` remains available as a compatibility wrapper for `./scripts/run-gate`.

## Available Commands

| Command | Description |
| --- | --- |
| `npm run dev` | Start the Vite development server with HMR |
| `npm run test` | Run Vitest in watch mode |
| `npm run test:coverage` | Run Vitest once and enforce the global coverage floor |
| `npm run test:e2e` | Run Playwright browser tests in desktop and mobile Chromium |
| `npm run test:changed -- <files>` | Run tests related to the provided files |
| `npm run build` | Type-check and build for production |
| `npm run preview` | Serve the production build locally |
| `npm run verify` | Compatibility wrapper for `./scripts/run-gate` |
| `npm run verify:all` | Run the full gate followed by desktop/mobile Playwright tests |

## Project Structure

```text
src/
├── app/          # Global app composition and bootstrap helpers
├── components/   # Reusable UI components with stable contracts
├── features/     # Vertical feature slices by product domain
├── layouts/      # Route layout shells
├── router/       # Routes and navigation guards
├── shared/       # HTTP, realtime, config, storage and shared utilities
├── stores/       # Shared Pinia state
├── test/         # Test harness and helpers
├── types/        # Shared type declarations
├── views/        # Route-level orchestration components
└── style.css     # Global styles and visual tokens
```

The `@` alias points to `src/` and is configured in `vite.config.ts` and `tsconfig.app.json`.

## Architecture

The frontend follows feature-oriented vertical slices with explicit boundaries between UI, state
and transport.

Core dependency direction:

```text
main and router
      ↓
    views
      ↓
   features
    ↙     ↘
 domain   shared
```

High-level rules:

- Views compose workflows and should not call `fetch`, create sockets or decode external payloads.
- Feature modules own product behavior for auth, contacts, conversations, messaging, search and
  presence.
- Shared infrastructure must not depend on features, views, router or stores.
- API modules stay headless and must not import UI, router or stores.
- Runtime payloads from the backend are treated as `unknown` at transport boundaries.
- Pinia stores are used only for state shared across routes, components or realtime events.

Read [`docs/architecture/frontend.md`](docs/architecture/frontend.md) before implementing or
moving feature code.

## Testing

Tests use Vitest, jsdom and Testing Library. Unit and component tests must not talk to the real
backend.

Testing conventions:

- Assert observable behavior through roles, labels or visible text.
- Stub `fetch` and WebSocket explicitly.
- Use a fresh Pinia and memory router per test.
- Avoid large snapshots and Tailwind class selectors.
- Keep tests close to the behavior they protect.
- Split broad route-level workflows by feature and share only transport fixtures and render helpers.
- Keep browser-dependent behavior such as focus management in the Playwright suite.

The full gate runs Vitest with coverage and enforces the current baseline:

- 90% statements
- 84% branches
- 92% functions
- 90% lines

The HTML report is generated in `coverage/`. Before the first browser run, install the Chromium
binary managed by Playwright:

```bash
npx playwright install chromium
npm run test:e2e
```

For Vue-specific engineering guidance, read
[`docs/ai-harness/vue-guidelines.md`](docs/ai-harness/vue-guidelines.md).

## Design References

UI work should follow the existing product direction and visual references in:

- [`docs/design-system/directions/direction-a.html`](docs/design-system/directions/direction-a.html)
- [`docs/design-system/directions/direction-b.html`](docs/design-system/directions/direction-b.html)
- [`docs/design-system/directions/direction-c.html`](docs/design-system/directions/direction-c.html)

These references define density, spacing, message surfaces, modal treatment and the neutral visual
language used by the chat experience.

## TypeScript Version

The project declares TypeScript `~6.0.2`; the current lockfile resolves it to TypeScript `6.0.3`.

Although newer TypeScript releases may be available, the current Vue toolchain depends on the
TypeScript compiler JavaScript API used by `vue-tsc` and `@vue/language-tools`. The project stays on
TypeScript 6.x so Vue SFC type-checking remains reliable end to end. Migration to a newer major
version should wait until the Vue language tooling supports it cleanly.
