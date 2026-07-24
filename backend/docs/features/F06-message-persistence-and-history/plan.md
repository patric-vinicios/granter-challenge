# Implementation Plan: Message Persistence and History

**Prerequisites:**
- F05 complete: groups on the shared conversation tables, and the membership lifecycle that writes `left_at` — the column this feature reads to bound a departed member's history
- F04 complete: the `conversations` and `conversation_participants` tables, `Api.Conversations` with `participant?/2`, and the conversations boundary already exported from the domain root
- F02 complete: the `users` table, the `:authenticated` router pipeline exposing `conn.assigns.current_user`, and `ApiWeb.UserJSON.data/1` as the shared user shape the sender is rendered through
- F01 complete: the `Api.Schema` conventions the keyset order depends on, the JSON error envelope with its reason-keyed fallback table, and the `DataCase`/`ConnCase`/`Api.Factory` harness
- **One migration, generated with `mix ecto.gen.migration create_messages`. No new dependency, no configuration value and no environment variable**
- Scope is the whole feature: the PRD declares no Core/Full split for it
- Follow the existing conventions: moduledocs explain why a decision was made and never name feature IDs, and commits use Conventional Commits

---

### Stage 1: Data Layer

**1. Messages Migration** - Generate the migration creating the message table with its two foreign keys, its body column and the project's timestamp convention. Add the composite history index the spec fixes, the sender index that keeps foreign-key maintenance off a sequential scan, and the body-length check that backstops the changeset at the storage layer.

**2. Message Schema** - Add the message schema following the shared schema conventions, with associations to the conversation and the sender, and a changeset that casts the body and nothing else. Trim it, require it, bound it against the length the spec fixes, and attach the length check and both foreign-key constraints so every database guarantee surfaces as a changeset error rather than a raised exception.

### Stage 2: Domain Layer

**3. Read Access Gate** - Add the read counterpart to the existing participation predicate in the conversations context, resolving one participant row into the three answers the spec defines: active, bounded at the departure time, or absent. Leave the existing predicate and every one of its callers untouched, and keep the outsider's answer indistinguishable from an unknown conversation.

**4. Cursor Codec** - Add the cursor module encoding a message's two ordering columns into a URL-safe opaque string and decoding it back. Decoding is strict at every step and collapses every failure into the single error the spec names, so a malformed cursor can never be mistaken for an absent one.

**5. Messages Context** - Add the messages context as its own boundary, declaring the accounts and conversations contexts as dependencies and exporting only its schema, and register it in the domain root's export list. Give it the single write path, which gates on active participation and places the sender, the conversation and the insertion time on the struct rather than casting them.

**6. Keyset Read** - Add the history read to the context, resolving access first, then the cursor, then running the descending range query with the sender preloaded and one row beyond the requested limit. Apply the departed member's time bound inside the query rather than over the fetched page, and assemble the result into the ascending page, the next cursor and the more-available flag the spec specifies.

**7. Message Factory** - Add the message factory to the shared factory module, building a conversation and a sender by default so a bare insert is valid and either side takes an override.

### Stage 3: Web Layer

**8. Error Table Extension** - Register the invalid-cursor reason in the fallback controller's reason table with the status and default message the spec fixes, alongside the codes the earlier features declared there.

**9. Message Renderer** - Add the message view rendering one message with its sender embedded through the shared user renderer, and the page wrapper carrying the message list, the next cursor and the more-available flag. This is the shape the real-time broadcast and the search result will both reuse, so keep the single-message renderer public and independent of the page.

**10. History Endpoint and Route** - Add the message controller with its single read action, validating the pagination parameters with a schemaless changeset before any domain call — the same shape the conversation controller uses for its request bodies — and delegating every failure to the fallback controller. Register the route inside the router's existing authenticated scope.

### Stage 4: Test Suite

**11. Cursor Tests** - Cover the codec on its own: the round trip preserving microsecond precision, the URL-safe output, and each decode failure mode arriving at the same single error, including a well-formed value with a flipped character.

**12. Context Test Suite** - Add the messages suite covering the write path — the sender that cannot come from the attributes, the backdated timestamp that can, and every body rule at and beyond its bounds — and the read path, including the full walk of a long conversation proving no duplicate and no gap, stability across inserts landing between two pages, the exact point at which the more-available flag turns false, and the departed member's bound applying to the pages rather than to the visible slice of one.

**13. Read Access Tests** - Extend the conversations suite with the new read gate: the active member, the departed member's bound, the outsider and the unknown conversation sharing one answer, the malformed id, and reactivation after a re-add. Add the regression asserting the existing predicate still refuses a departed member.

**14. Endpoint Test Suite** - Add the endpoint suite exercising the route end to end against the real authenticated pipeline, one test per acceptance criterion: the default page and its ordering, both limit boundaries and both rejection shapes, the tampered cursor that must not fall back to the newest page, the outsider receiving the absent answer with no content, authentication, and the sender identity carried on every entry.

**15. Cross-Feature Tests** - Cover the two integration criteria in the endpoint suite: a private conversation from the earlier feature accepting messages from both participants while a third user's read is refused, and a group accepting messages from every active member, with a member removed through the group endpoint then refused on their next send and served only the history that predates their removal.

### Stage 5: Quality Gate

**16. Quality Gate Verification** - Run the full precommit chain and resolve every warning, formatting difference, Credo finding and coverage shortfall until it passes. Confirm the boundary compiler accepts the new context's declared dependencies and its registration in the domain root, and verify against a populated conversation that the history query plans as a range scan over the composite index rather than a sort.
