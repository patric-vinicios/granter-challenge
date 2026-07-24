# Implementation Plan: API Documentation

**Prerequisites:**
- Features F01–F11 implemented and merged (all routes, channels, error codes and the seed script exist to be documented).
- Access to the passing test suite under `test/api_web/`, the source of truth for payload examples.
- Existing `backend/README.md` (run, seeds, env vars, error format already present) and no existing `docs/api.md`.

## Stage 1: Inventory and REST Reference

**1. Endpoint and error-code inventory** - Enumerate every REST route from the router and every channel event from the channel modules, and compile the full set of `errors.code` values from the fallback controller and the error-JSON module. Confirm the inventory against the Documentation Coverage Contract in the spec so nothing is omitted before writing begins.

**2. `docs/api.md` scaffold** - Create the file with a table-of-contents header and top-level sections for REST endpoints, the WebSocket contract, and the error-code table, so each subsequent step fills a known slot.

**3. REST endpoint documentation** - Document all 17 REST endpoints, each with method, path, authentication requirement, path/query parameters, a request-body example, a success response with its status code, and at least one error response carrying its `code`. Transcribe request and response examples from the corresponding controller tests rather than inventing shapes, per the spec's example-sourcing decision.

## Stage 2: WebSocket Contract and Error Table

**4. WebSocket section** - Document the socket URL and connect params, both topic patterns with their join-authorization rules, the inbound `new_message` event with its reply and error shapes, and the five outbound events, each with a concrete payload example transcribed from the channel tests.

**5. Error-code table** - Add the single table mapping every emitted `errors.code` to its HTTP status and meaning, drawn from both source tables plus the channel reply reasons, so a client can branch exhaustively.

## Stage 3: README Narrative and Verification

**6. README design-decisions and reflection sections** - Add a "Design decisions" section justifying JWT over cookies, Argon2id over bcrypt, REST plus Channels, the single conversations table, keyset over offset pagination, and unidirectional contacts; and a "What I would do differently with more time" section. Leave the existing run/seed/env/error-format content unchanged.

**7. Coverage verification** - Verify the finished documentation against the spec's checks: route coverage via the router, error-code completeness against the source tables, channel topic and event coverage against the channel modules, and example fidelity against the asserting tests. Confirm a reviewer following only the README can reach a running, populated, loggable-in application.
