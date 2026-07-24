# Implementation Plan: Message and Conversation Search

**Prerequisites:**
- Message persistence and history and the conversation inbox are implemented (the `messages` table, the `Messages` and `Conversations` contexts, the read-access predicate, the message JSON object, and the inbox summary entry all exist).
- PostgreSQL 16 with the `unaccent` extension already enabled by the base extensions migration.
- Existing test harness (`ConnCase`, `DataCase`, `Api.Factory`) and `mix precommit` gate.

## Stage 1: Search Index Foundation

**1. Search index migration** — Generate a migration (`mix ecto.gen.migration`) that establishes a diacritic-insensitive Portuguese text-search configuration, adds a database-generated full-text vector column to the messages table derived from the message body, and creates a GIN index over it. Write it as `up`/`down` so the configuration is reversible on a clean database. See the spec's Data Model section for the exact statements.

## Stage 2: In-Conversation Message Search

**2. Match-offset module** — Add a small pure module beside the messages boundary that, given a message body and a search term, returns the character spans of the matched term(s) for client-side highlighting, matching accent- and case-insensitively. Reference the spec's Decisions and Assumptions for the normalization and offset semantics.

**3. Message search in the context** — Add a search function to the messages context that gates the caller through the existing conversation read-access predicate, runs the index-backed full-text query bounded to a departed member's read window, orders matches by recency, caps the result set while reporting whether more exist, assigns each hit a position, and attaches its match offsets. See the spec's Component Overview and Data Model for the query shape.

**4. Search endpoint and route** — Add the search action to the message controller, validating the query term's length before any domain call, and register its route. Delegate all error translation to the existing fallback controller. See the spec's API Contracts for the parameter rules and error mapping.

**5. Search result rendering** — Add a render clause to the message JSON view that reuses the canonical message object and augments each hit with its position and match offsets, alongside the total-match count and truncation flag. See the spec's API Contracts for the response shape.

## Stage 3: Conversation List Filtering

**6. Title filter in the inbox query** — Extend the conversation-listing function to accept an optional query term and, when present, narrow the results to conversations whose display title matches accent- and case-insensitively, without changing the returned entry shape. See the spec's Data Model for the filter expression.

**7. Filtered list endpoint** — Have the conversation index action read the optional query parameter and forward it to the listing function, leaving the response identical to the unfiltered list. See the spec's API Contracts.
