# Implementation Plan: Group Management

**Prerequisites:**
- F04 complete: the `conversations` and `conversation_participants` tables in full — including the `name`, `creator_id`, `joined_at` and `left_at` columns groups are the first to write — plus `Api.Conversations` with `get_conversation/2` and `participant?/2`, `ApiWeb.ConversationController`, `ApiWeb.ConversationJSON` and the conversations boundary already exported from the domain root
- F03 complete: the `contacts` table and `Api.Contacts.contact?/2`, the per-id predicate this feature complements with a set check
- F02 complete: the `users` table, the `:authenticated` router pipeline exposing `conn.assigns.current_user`, and `ApiWeb.UserJSON.data/1` as the shared user shape each member is rendered through
- F01 complete: the `Api.Schema` conventions, the JSON error envelope with its reason-keyed fallback table, and the `DataCase`/`ConnCase`/`Api.Factory` harness
- **No migration, no new dependency, no configuration value and no environment variable** — the data layer this feature needs already exists
- Scope is the whole feature: creation and member listing from Core Scope, plus adding members, removing members and leaving from the Full Scope additions
- Follow the existing conventions: moduledocs explain why a decision was made and never name feature IDs, and commits use Conventional Commits

---

### Stage 1: Domain Layer

**1. Contact Set Check** - Add the set counterpart to the existing per-id contact predicate in the contacts context: one query answering which of a list of ids are absent from the owner's list, returning the offenders' usernames so the caller can name every one of them in its error. Keep it behind the contacts boundary alongside the predicate it complements, and assume the ids arrive already cast.

**2. Group Changeset** - Add the group changeset to the conversation schema, casting and validating only the name against the length bounds the spec fixes, with the kind and the owner set on the struct when it is built so no request body can name another user as creator. Leave the private changeset and its pair-key constraint untouched.

**3. Group Creation** - Add the creation function to the conversations context, running the decision order from the spec — structural validation, the creator's own id, then the contact set — and inserting the conversation, the creator's membership row and one row per member inside a single transaction, so a rejected set or a failed insert leaves nothing behind. Return the group with its active members resolved.

**4. Group Read Branch** - Extend the existing conversation read with its group branch: load the active membership rows with their users, derive the member count from them, and keep the outsider's answer indistinguishable from an absent conversation, including for a member who has left.

**5. Membership Changes** - Add the three membership functions. Adding and removing share the authorization order the spec fixes — existence before permission, so an outsider learns nothing and only an active member reaches the creator check. Adding validates the set the same way creation does, refuses a caller already seated, and reactivates a previously departed row rather than inserting a second one. Removing marks the target's row departed and refuses the creator's own id. Leaving marks the caller's own row departed after confirming another active member remains, and never rewrites the recorded owner.

**6. Group Factory** - Add the group factory to the shared factory module, seating the creator as an active member so a bare insert produces a readable group and a named owner is a one-line override.

### Stage 2: Web Layer

**7. Error Table Extension** - Register the five new domain reasons in the fallback controller's reason table with the statuses and default messages from the spec. The three at the validation status carry no field map, since none of them is a field failure. The contact rejection reuses the code the private-conversation feature registered, overriding only its detail through the clause that already exists for that.

**8. Group Renderer** - Add the group branch to the conversation view, carrying the name, the owner id, the active member count and the member list rendered through the shared user renderer in a stable order, alongside the caller's own read marker. Leave the private branch unchanged.

**9. Group Endpoints and Routes** - Add the four actions to the existing conversation controller, validating the submitted member set with a schemaless changeset before any domain call — the same shape the contact controller uses for an add — and rendering the created group at the creation status and the updated group at the success status for all three mutations. Register the four routes inside the router's existing authenticated scope, declaring the static leave segment before the parameterised removal one so a leave is never matched as a removal.

### Stage 3: Test Suite

**10. Contact Set Check Tests** - Extend the contacts suite with the set check: every id valid, several offenders named at once rather than only the first, an unknown user treated as a non-contact, scoping to the owner, and the empty input.

**11. Context Test Suite** - Extend the conversations suite with the group functions: the decision orders, transactionality, deduplication and the size cap, the read branch and its indistinguishable outsider answer, reactivation of a departed member on a re-add, the all-or-nothing behaviour of adding, the creator's own removal and leave guards, and the frozen membership a departed owner leaves behind.

**12. Endpoint Test Suite** - Add the group endpoint suite covering all four endpoints end to end against the real authenticated pipeline, one test per acceptance criterion, including the outsider receiving the absent answer rather than the permission one, the leave route winning the match over the removal route, name immutability across a mutation, and authentication on every route.

**13. Cross-Feature Test** - Cover the integration criterion in the endpoint suite: add contacts through the contacts endpoint, create a group from the returned user ids, then repeat the creation with one of them plus a stranger and assert the whole request fails naming only the stranger, with no group persisted.

### Stage 4: Quality Gate

**14. Quality Gate Verification** - Run the full precommit chain and resolve every warning, formatting difference, Credo finding and coverage shortfall until it passes. Confirm the boundary compiler still accepts the conversations context reaching into the contacts context for the new set check, and that no migration was added.
