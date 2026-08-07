# Real Time Chat

Real Time Chat is a full-stack real-time messaging application. It combines a Phoenix JSON API, PostgreSQL persistence and Phoenix Channels with a
Vue 3 single-page frontend focused on contacts, private conversations, groups, inbox search,
message history and live delivery.

The repository is organized as a small product, not as isolated technical demos: the backend owns
authentication, authorization, persistence, pagination, search and realtime contracts; the frontend
consumes those contracts through typed feature slices, explicit state boundaries and automated
quality gates.

## Product Scope

- Account registration and login with JWT authentication.
- Contact management by `@username`.
- Private one-to-one conversations.
- Named group conversations with member selection.
- Persisted message history with cursor pagination.
- Realtime message delivery through Phoenix Channels.
- Conversation inbox with previews, unread state and search.
- In-conversation message search with result navigation.
- Presence and last-seen rendering.
- Seeded demo data for immediate manual review.

## Repository Layout

```text
.
├── backend/   # Phoenix API, contexts, database, channels, seeds and backend docs
└── frontend/  # Vue 3 SPA, feature modules, UI, realtime client and frontend docs
```

Start with the focused README for the part you are working on:

- [`backend/README.md`](backend/README.md) — API setup, seeded accounts, tests, environment and
  design decisions.
- [`frontend/README.md`](frontend/README.md) — SPA setup, architecture, production config and
  frontend quality gates.

## Tech Stack

### Backend

- Elixir 1.20
- Phoenix 1.8
- PostgreSQL 16
- Ecto
- Phoenix Channels and PubSub
- JWT bearer authentication
- ExUnit, Credo, Dialyzer and coverage gates

### Frontend

- Vue 3 with Composition API and `<script setup lang="ts">`
- Vite
- TypeScript
- Pinia
- Vue Router
- Tailwind CSS
- Phoenix JavaScript client
- Vitest, Testing Library and Playwright
- ESLint, Dependency Cruiser, Knip and `vue-tsc`

## Quick Start

### 1. Start the backend

```bash
cd backend
cp .env.example .env
docker compose -f docker-compose.dev.yml up
```

The API listens on `http://localhost:4000`.

Check health:

```bash
curl http://localhost:4000/api/health
```

Expected response:

```json
{"status":"ok","database":"up"}
```

### 2. Start the frontend

In another terminal:

```bash
cd frontend
cp .env.example .env
npm install
npm run dev
```

The SPA runs at `http://localhost:5173`.

## Demo Accounts

The backend seed creates realistic users, contacts, private conversations, groups and messages.
Every seeded account uses the same password: `senha123`.

| Username | Name |
| --- | --- |
| `@demo` | Usuário Demo |
| `@anabeatriz` | Ana Beatriz |
| `@carlosedu` | Carlos Eduardo |
| `@joaopedro` | João Pedro |
| `@leticiam` | Letícia Moraes |
| `@marianas` | Mariana Silva |
| `@rafaelalves` | Rafael Alves |

For a broad review, start with `@demo`; it participates in every seeded conversation and owns both
seeded groups.

## Environment Overview

### Backend

Backend configuration is loaded from `backend/.env` outside the test environment. The most relevant
variables are:

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | Database connection override. |
| `SECRET_KEY_BASE` | Phoenix signing/encryption secret. |
| `JWT_SECRET` | JWT signing secret. |
| `PORT` | HTTP port, defaulting to `4000`. |
| `CORS_ORIGINS` | Browser origins allowed to call the API. |

See [`backend/README.md`](backend/README.md#environment-variables) for the complete table.

### Frontend

Frontend configuration is read by Vite:

| Variable | Local default | Purpose |
| --- | --- | --- |
| `VITE_API_URL` | `http://localhost:4000/api` | REST API base URL. |
| `VITE_SOCKET_URL` | `ws://localhost:4000/socket` | Phoenix socket endpoint. |

Production builds must set both explicitly and must not point to `localhost`.

## Quality Gates

Run the backend gate from `backend/`:

```bash
mix precommit
```

Run the frontend gate from `frontend/`:

```bash
npm run verify
git diff --check
```

The frontend CI is intentionally split by concern, with separate workflows for architecture,
dependency graph, lint, unused code/dependencies, typecheck, tests, build and whitespace checks.

## Smoke Test Checklist

Use this as a release-facing manual smoke script after both services are running:

1. Open `http://localhost:5173`.
2. Log in with `@demo` / `senha123`.
3. Confirm the inbox loads seeded private and group conversations.
4. Open a private conversation and send a message with `Ctrl + Enter`.
5. Confirm the optimistic message is replaced by the persisted message.
6. Search the inbox by a contact name and by a group name.
7. Open the conversation search, type a known term, and navigate matches with previous/next.
8. Open contacts, filter by name or username, and start a private conversation.
9. Create a group and select multiple contacts; selected names should stay in a horizontal rail.
10. Refresh the browser and confirm the session, inbox and history recover correctly.

For deeper frontend browser coverage, run from `frontend/`:

```bash
npm run verify:all
```

## Architecture Notes

The backend is organized around Phoenix contexts: accounts, contacts, conversations, messages,
presence and seeds. Authorization is enforced server-side for REST endpoints and channel joins.
Messages are persisted before realtime fan-out, and history uses cursor pagination rather than
offset pagination.

The frontend follows feature-oriented vertical slices. Route views compose workflows, feature
modules own product behavior, and shared infrastructure handles HTTP, realtime, config and storage.
Runtime payloads are decoded at transport boundaries before entering UI state.

## Production Notes

- Serve the frontend as a static Vite build with SPA fallback to `index.html`.
- Use HTTPS/WSS URLs for split frontend/backend deployments.
- Keep backend secrets out of version control.
- Configure CORS for the production frontend origin.
- Use the backend health endpoint for readiness checks.
- Run both backend and frontend gates before cutting a release.

## API Documentation

REST endpoints, WebSocket topics, channel events and error codes are documented in
[`backend/docs/api.md`](backend/docs/api.md).
