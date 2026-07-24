# Implementation Plan: Private Conversations

**Prerequisites:**
- F03 complete: the `contacts` table and `Api.Contacts.contact?/2`, the predicate this feature calls to enforce the contact rule on creation
- F02 complete: the `users` table, `Api.Accounts.get_user/1` as the id resolver, the `:authenticated` router pipeline exposing `conn.assigns.current_user`, and `ApiWeb.UserJSON.data/1` as the shared user shape
- F01 complete: the `Api.Schema` conventions, the JSON error envelope with its reason-keyed fallback table, and the `DataCase`/`ConnCase`/`Api.Factory` harness
- No new dependency, configuration value or environment variable
- The whole feature is in scope: the PRD defines no Core/Full split for it
- This feature creates the `conversations` and `conversation_participants` tables that F05 reuses; the schema is built in full here so wave 4 has one ordered base migration
- Follow the existing conventions: moduledocs explain why a decision was made and never name feature IDs, and commits use Conventional Commits

---

### Stage 1: Data Layer and Domain Context

**1. Conversations Migration** - Generate one migration creating both shared tables: the conversation table with its kind discriminator, the nullable name and creator columns that only groups use, and the derived pair key; and the participant table with its read marker and join/leave timestamps. Add the partial uniqueness that pins one private conversation per pair and the per-membership uniqueness, along with the cascade behaviours the spec fixes.

**2. Conversation and Participant Schemas** - Add both schemas on the shared schema conventions. The conversation schema carries a changeset that sets the kind and pair key programmatically and translates a pair-key collision into a changeset error rather than a raised exception. The participant schema applies the membership uniqueness and foreign keys, with both identifiers set when the struct is built and never castable from a request body.

**3. Conversations Context** - Add the context with the three functions the spec describes: opening a private conversation idempotently by running the decision order and creating-or-returning inside a single transaction, reading a conversation scoped to its participants, and the participation predicate the message and channel features will consume. Declare the context's architectural sub-boundary over the accounts and contacts contexts and export it from the domain root.

**4. Conversation Factories** - Add the conversation and participant factories to the shared factory module, plus a helper that inserts a live private pair in one call, so later suites build a conversation without restating its participant rows.

### Stage 2: Web Layer

**5. Error Table Extension** - Register the two new domain reasons in the fallback controller's reason table with the statuses and default messages from the spec. One of them answers at the forbidden status and is reused by the group feature with an overriding detail; the other answers at the validation status but carries no field map, since it is not a field failure.

**6. Conversation Renderer** - Add the view producing the private conversation shape, embedding the counterpart through the shared user renderer rather than restating its fields, and carrying the caller's own read marker.

**7. Conversation Controller and Routes** - Add the controller with the create and read actions, validating the request body the same way the contact controller validates an add, mapping a first creation and a repeat to their respective success statuses, delegating every failure to the fallback controller, and taking the caller exclusively from the authenticated connection. Register the two routes inside the router's existing authenticated scope.

### Stage 3: Test Suite and Quality Gate

**8. Context Test Suite** - Cover idempotency, symmetry across the pair, the decision order, transactionality, the participation predicate, asymmetric visibility and the contact-removal behaviour described in the spec's testing strategy, including the paths that reach the database constraints rather than the context guards.

**9. Endpoint Test Suite** - Cover both endpoints end to end against the real authenticated pipeline, one test per acceptance criterion, including the concurrent-create case and the cross-feature case that adds a contact through the contacts endpoint, opens the conversation, then removes the contact and asserts the next creation is refused while the existing conversation still reads. Extend the existing fallback controller test with the two new reasons.

**10. Quality Gate Verification** - Run the full precommit chain and resolve every warning, formatting difference, Credo finding and coverage shortfall until it passes. Confirm the boundary compiler accepts the new context's declaration, its dependencies on the accounts and contacts contexts, and its export from the domain root.
