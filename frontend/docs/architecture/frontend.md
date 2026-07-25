# Frontend Architecture

## Goal

Organize the frontend as a modular Vue 3 application, oriented around features and implemented as
vertical slices. Each delivery should cross contract, state, interaction and tests without spreading
the same feature across technical folders with no clear owner.

The architecture must support:

- authentication shared between HTTP and WebSocket;
- contacts, private conversations and groups;
- cursor-paginated history;
- realtime messages with optimistic reconciliation;
- ordered inbox, unread state, search and presence;
- incremental implementation following PRD dependencies;
- fast tests without real network or backend access.

This is not an architecture of ceremonial layers. Interfaces, stores, composables and components
should exist only when real behavior justifies their creation.

## Sources of Truth

Use this precedence when implementing a feature:

1. The PRD and feature specification define intent and acceptance criteria.
2. Router, controllers, JSON renderers, channels and backend tests define the integration contract
   that is available.
3. Existing frontend behavior defines compatibility that must be preserved.
4. This document defines organization and dependency direction in the frontend.

Never invent an endpoint, field, error code, topic or event to resolve a mismatch. If the documented
contract is not implemented, separate the work that remains true and explicitly record what is still
not integrated.

## Architectural Style

Adopt a modular feature architecture, with vertical slices and shared infrastructure at input and
output boundaries.

```text
src/
├── app/                    # bootstrap and global composition
├── domain/                 # pure types shared between features
├── shared/
│   ├── api/                # HTTP client and error normalization
│   ├── realtime/           # Phoenix Socket and connection lifecycle
│   ├── config/             # centralized configuration reading
│   ├── storage/            # session persistence
│   ├── ui/                 # shared elements with a real contract
│   └── utils/              # reusable pure functions
├── features/
│   ├── auth/
│   ├── contacts/
│   ├── conversations/
│   ├── messaging/
│   ├── search/
│   └── presence/
├── views/                  # route composition
└── router/                 # routes and guards
```

This structure is an incremental destination. Do not move the whole prototype before implementing
the first feature. Create a module when the corresponding vertical slice begins, and migrate only
the code it needs.

## Dependency Direction

```text
main and router
      ↓
    views
      ↓
   features
    ↙     ↘
 domain   shared
```

Mandatory rules:

- `app`, router and views may compose features.
- Features may depend on `domain` and `shared`.
- `domain` contains only types and pure functions; it does not import Vue, Pinia or transport.
- `shared` does not import features, views or domain stores.
- Views do not call `fetch`, create sockets or interpret external payloads.
- API modules do not import components, router or stores.
- Stores do not access the DOM and do not perform navigation.
- A feature does not import internal files from another feature. Share pure types through the domain
  or compose both features in the view.
- A circular dependency is an architectural failure, not a reason to create a global singleton.

## Feature Anatomy

A feature starts small and grows on demand:

```text
features/auth/
├── auth.api.ts             # feature HTTP operations
├── auth.contracts.ts       # schemas, decoders and transport types
├── auth.store.ts           # only if state is shared
├── auth.spec.ts
├── components/             # UI exclusive to the feature
└── views/                  # optional when the route belongs to the feature
```

Do not create all of these files by default:

- state used by a single component remains local;
- a simple call can stay in a single feature module;
- create a composable when there is lifecycle, a reusable effect or coordination between sources;
- create a store when state crosses components, routes or realtime events;
- extract a component when it has its own responsibility and contract;
- types used by only one feature remain in that feature;
- move a type to `domain` only when two or more features consume it.

## Feature Map

| Module | Responsibility | PRD |
| --- | --- | --- |
| `auth` | session, identity, bootstrap and guards | F02 |
| `contacts` | contact list, add, remove and selection | F03 |
| `conversations` | private conversation, groups, details and inbox | F04, F05, F08 |
| `messaging` | history, cursor, send and message events | F06, F07 |
| `search` | inbox filtering and in-conversation search | F09 |
| `presence` | online state and last seen | F10 |
| `shared` | HTTP, socket, configuration, errors and persisted session | F01 |

F11 provides demo data consumed by existing modules and does not require a dedicated frontend
feature. F12 documents the contracts used by the frontend.

Implement in product dependency order:

```text
shared → auth → contacts → conversations → messaging
                                  ↘          ↙
                                    search
auth + messaging → presence
```

## State and Ownership

The backend is the source of truth for persisted data. Pinia keeps session, cache and client
coordination; it does not replicate authorization rules that belong to the server.

| State | Recommended owner | Reason |
| --- | --- | --- |
| user, token and bootstrap | `authStore` | used by routes, HTTP and socket |
| contacts | `contactsStore` | reused in contacts, private conversation and groups |
| summaries, order and unread | `inboxStore` | updated by REST and personal topic |
| history by conversation | `messagesStore` | cursor, deduplication and reconciliation |
| presence for the open conversation | feature composable | lifecycle tied to the current route |
| form, modal and draft | local component or composable | does not need to be global |
| search results | local composable | belongs to the open interaction |

State guidelines:

- normalize collections with `byId` and id lists when there is incremental update;
- derive ordering, grouping and labels with `computed`;
- do not copy derived data into another `ref`;
- do not use `watch` to keep two copies synchronized;
- shared mutations go through actions;
- use `storeToRefs` when destructuring state or getters;
- keep navigation in views or guards, outside stores.

## HTTP Boundary

`src/shared/api/` should provide only common capabilities:

- `VITE_API_URL` resolution;
- JSON serialization and reading;
- common headers;
- `AbortSignal` support;
- normalization of the `{ errors: { code, detail, fields? } }` envelope;
- distinct errors for network failure, invalid response and API error.

Each feature declares its endpoints and contracts in its own module. Authenticated functions receive
the token explicitly; the shared client does not import `authStore`.

External payload enters as `unknown`. Validate the fields used for state or control flow before
turning it into a trusted type. TypeScript types do not replace runtime validation.

Do not duplicate server messages inside components. The presentation layer receives normalized
errors and only decides how to display them.

## WebSocket Boundary

`src/shared/realtime/` owns Phoenix Socket creation and connection. It receives the token at
connection time and does not know stores or components.

Feature composables control topics and events:

- the authenticated session opens a connection;
- the inbox joins `user:<user_id>`;
- the open conversation joins `conversation:<conversation_id>`;
- unmounting or route changes close the previous channel and remove handlers;
- logout closes all channels and the connection;
- reconnect triggers REST recovery because the channel does not replay events.

Stores receive data already decoded by callbacks or actions. The socket module never mutates UI
state directly.

## REST and Realtime

REST and WebSocket have different roles:

```text
REST
├── session bootstrap
├── initial inbox list
├── details and history
├── cursor pagination
└── recovery after reconnect

WebSocket
├── new messages
├── send acknowledgements
├── incremental inbox updates
├── membership revocation
└── presence
```

Reconciliation rules:

- REST history arrives in chronological order and is stored without client-side reordering;
- older pages are inserted before existing messages;
- realtime messages are deduplicated by server id;
- optimistic send uses `client_ref` and a transient state;
- acknowledgement replaces the transient message with the persisted record;
- the sender does not add the same record again from the broadcast;
- send failure removes or marks the transient message and preserves the text for retry;
- after reconnect, reload history and inbox to fill missed events;
- the personal topic updates summary, unread and conversation position without joining every topic.

## Routes and Composition

Views are UI composition roots:

- read route params;
- initialize the required stores and composables;
- coordinate navigation after business results;
- compose loading, empty, success and failure states;
- pass typed data and callbacks to components.

Guards depend only on public session state. Preserve a safe return destination when sending an
unauthenticated user to login. Never trust an external URL as a navigation destination.

## Client Security

- Do not render message content with `v-html`.
- Do not write tokens, passwords or sensitive payloads to logs or fixtures.
- Centralize session persistence in `shared/storage`.
- Clear session, socket and authenticated caches on logout or expired token.
- Handle 401 by code: `token_expired` and `unauthenticated` end the session; invalid credentials
  belong to the login form.
- Do not replicate contact or membership authorization as a client guarantee. The UI may hide an
  action, but the server remains responsible for authorizing it.
- Escaping is Vue template default behavior; do not bypass this protection for messages.

## Testing Strategy

Place tests close to the behavior they protect:

- feature contracts: method, path, headers, body, response and normalized error;
- store/composable: state transitions, deduplication, pagination and cleanup;
- component: accessible interaction and states perceived by the user;
- router: guards and params with `createMemoryHistory`;
- socket: join, leave, acknowledgement and reconnect with fake transport.

Rules:

- each test creates its own Pinia and router;
- real network and WebSocket remain blocked;
- do not select Tailwind classes;
- do not use large snapshots;
- restore timers and mocks;
- do not use arbitrary waits to synchronize tests;
- fake transport proves client integration, not real backend availability.

Each vertical slice should map acceptance criteria to tests or to an explicit manual verification.
Before finishing, run targeted tests, related tests and `npm run verify`.

## Incremental Prototype Evolution

Avoid an isolated structural migration. For each feature:

1. read the PRD, feature folder and executable contract;
2. write the feature brief;
3. create the feature folder and only the infrastructure it consumes;
4. move from the view only the state and behavior that belong to the feature;
5. preserve markup and appearance that are not part of the change;
6. replace mocks only when the vertical slice is tested;
7. run the harness and review the diff for unrelated changes.

The current `InboxView.vue` can be decomposed while F03-F09 are implemented. Do not split it into
empty components or wrappers only to reduce file size.

## Anti-Patterns

Do not introduce:

- a single global store for the whole application;
- HTTP or socket calls inside templates and presentation components;
- a generic services directory without feature ownership;
- duplicated DTOs across multiple layers;
- global events without a contract and cleanup;
- watchers used as the main derivation mechanism;
- repository or use case abstractions for trivial calls without a second consumer;
- structural refactoring before the first vertical slice;
- optimistic behavior without reconciliation by `client_ref` and persisted id;
- trust in tests with fakes as proof of real integration.

## Decision Checklist

Before creating a file, answer:

1. Which feature owns this behavior?
2. Is there a real consumer now?
3. Does the state need to cross a component or route?
4. Does the effect have lifecycle or cleanup?
5. Is the type shared by more than one feature?
6. Did the data come from an external boundary and was it validated?
7. Does the dependency respect the direction defined in this document?
8. Does the behavior have an observable test?

If the answers do not justify a new layer, keep the solution in the smallest possible scope.
