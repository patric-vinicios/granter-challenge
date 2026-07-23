# Implementation Plan: Conversation Inbox and Unread Tracking

**Prerequisites:**
- F06 complete: the `messages` table and its `(conversation_id, inserted_at DESC, id DESC)` index — the last-message and unread laterals read it at its leading edge, and `MessageJSON.data/1` is the neighbouring shape the entry's `last_message` mirrors
- F05 complete: groups on the shared conversation tables and the membership lifecycle that writes `left_at` and rewrites `joined_at` on re-add — the two columns the unread window and the ordering depend on
- F04 complete: the `conversations` and `conversation_participants` tables, `Api.Conversations` with `participant?/2` and `read_access/2` already exported, and `ConversationJSON` with its `show/1` and `data/2` clauses
- F02 complete: the `users` table, the `:authenticated` pipeline exposing `conn.assigns.current_user`, and `ApiWeb.UserJSON.data/1` as the shared user shape the counterpart is rendered through
- F01 complete: the `Api.Schema` conventions, the JSON error envelope with its reason-keyed fallback table, and the `DataCase`/`ConnCase`/`Api.Factory` harness
- **One migration, generated with `mix ecto.gen.migration add_conversation_participants_user_index`. No new table, no new dependency, no configuration value and no environment variable**
- Scope is Core plus Full: the aggregated list, the unread counts and the mark-as-read endpoint
- Follow the existing conventions: moduledocs explain why a decision was made and never name feature IDs, and commits use Conventional Commits

---

### Stage 1: Data Layer

**1. Driving-Scan Index** - Generate the migration adding the partial index on the participant's user column, restricted to active rows. This is what turns "every conversation of this caller" from a sequential scan of the whole participant table into a lookup, and the partial predicate keeps departed rows out of the structure the inbox is read through.

### Stage 2: Domain Layer

**2. Preview Rule** - Add the preview module beside the conversation and participant schemas, holding the single truncation function: collapse whitespace runs, return short bodies verbatim, and otherwise cut at the last word boundary within the limit — falling back to a hard cut for an oversized single word — before appending the ellipsis. Keep it unexported from the boundary, the way the cursor codec is to the messages boundary.

**3. Aggregate Query** - Add the list function to the conversations context: the driving scan over the caller's active participant rows, the four lateral sub-plans the spec fixes — last message, capped unread count, private counterpart, active member count — the two-tier ordering, and the response cap. Reach the messages table as a bare source with explicit type annotations rather than through its schema, so the boundary graph stays acyclic, and assemble each row into the summary map with the preview truncated and the unread count capped and flagged.

**4. Read Marker** - Add the mark-as-read function to the same context: cast the id, resolve access through the existing read gate, map a departed member's bound to the participant-specific refusal, and write the marker as a maximum of its current value and the server's time so two devices marking at once cannot move it backwards. Return the new marker.

### Stage 3: Web Layer

**5. Error Table Extension** - Register the not-a-participant reason in the fallback controller's table with the forbidden status and the message the spec fixes, alongside the codes the earlier features declared there.

**6. Inbox Renderer** - Extend the conversation view with the list wrapper, the single-entry renderer embedding the counterpart through the shared user renderer and nesting the last message or null, and the marker-response renderer. Leave the existing detail-shape clauses untouched, since the inbox entry and the conversation detail answer different questions.

**7. Endpoints and Routes** - Add the list and mark-as-read actions to the conversation controller, both reading the caller from the connection and delegating every failure to the existing fallback, and register the two routes inside the router's authenticated scope so neither collides with the existing conversation routes.

### Stage 4: Test Suite

**8. Query-Count Helper** - Add the helper to the data case that attaches a telemetry handler to the repo's query event for the duration of a function and returns the number of queries it issued, detaching afterward. This is what the bounded-query criterion is asserted with, at both the context and the endpoint level.

**9. Preview Tests** - Cover the truncation rule on its own: a short body and a body at exactly the limit returned verbatim, a cut at a word boundary, the hard cut for a single oversized word, whitespace collapse, the stripped trailing space before the ellipsis, and character-rather-than-byte counting for multi-byte bodies.

**10. Context Test Suite** - Extend the conversations suite with the list and marker paths: both conversation types in one response, the title and counterpart-or-member-count resolution, the full ordering including the message-less tier and its tie-break, the newest-message preview and its id tie-break, every branch of the unread window — own messages excluded, the null-marker case, the group membership bound, the re-add restart — the cap and overflow at their exact boundaries, the left-conversation omission, the 200-entry cap, and the single-query assertion taken at two conversation counts. Cover the marker write for an active member, its idempotence and monotonicity, and its three refusals.

**11. Endpoint Test Suite** - Add the inbox endpoint suite in a file of its own, exercising both routes end to end against the real authenticated pipeline, one test per acceptance criterion: the full entry shape, the ordering, the truncated preview that differs from the history body, the badge cleared by a mark, the idempotent mark, the departed group omitted, every error status, the empty array for a fresh user, and authentication on both routes. Include the query-count assertion through the full pipeline.

**12. Cross-Feature Tests** - Cover the three integration criteria in the endpoint suite: a private conversation opened through the earlier feature's endpoint appearing with the counterpart as its title, a group appearing with its name and active member count and disappearing once the caller leaves through the membership endpoint, and the last persisted message being the previewed one and carrying its conversation to the top of the ordering.

### Stage 5: Quality Gate

**13. Quality Gate Verification** - Run the full precommit chain and resolve every warning, formatting difference, Credo finding and coverage shortfall until it passes. Confirm the boundary compiler still accepts the conversations context with its dependency list unchanged, and verify against a populated account that the aggregate plans as one statement driven by the new partial index with each lateral bounded, rather than as a scan whose cost grows with total message history.
