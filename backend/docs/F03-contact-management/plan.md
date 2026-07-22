# Implementation Plan: Contact Management

**Prerequisites:**
- F02 complete: the `users` table, `Api.Accounts.get_user_by_username/1` as the single username resolver, the `:authenticated` router pipeline exposing `conn.assigns.current_user`, and `ApiWeb.UserJSON.data/1` as the shared user shape
- F01 complete: the `Api.Schema` conventions, the JSON error envelope with its reason-keyed fallback table, and the `DataCase`/`ConnCase`/`Api.Factory` harness
- The `unaccent` extension, already enabled by F01's base migration — no privileged DDL is needed by this feature
- No new dependency, configuration value or environment variable
- The whole feature is in scope: the PRD defines no Core/Full split for it
- Follow the existing conventions: moduledocs explain why a decision was made and never name feature IDs, and commits use Conventional Commits

---

### Stage 1: Data Layer and Domain Context

**1. Contacts Migration** - Generate the migration creating the contacts table as a pair of user references with a creation timestamp and no update timestamp. Add the uniqueness, cascade and self-pair guarantees the spec specifies, along with the two supporting indexes.

**2. Contact Schema** - Add the contact schema on the shared schema conventions, with both associations to the user record and a changeset that applies the database guarantees as changeset errors rather than raised exceptions. Both identifiers are set when the struct is built and must never be castable from a request body.

**3. Contacts Context** - Add the context with the four functions the spec describes: adding a contact by username, listing an owner's contacts, deleting one, and the membership predicate the conversation and group features will consume. Adding must run the guards in the order the spec's decision diagram fixes, and every function must be scoped to a single owner. Declare the context's architectural sub-boundary and export it from the domain root.

**4. Contact Factory** - Add the contact factory to the shared factory module so a test can build a valid, non-self pair with either side overridden inline.

### Stage 2: Web Layer

**5. Error Table Extension** - Register the five new domain reasons in the fallback controller's reason table with the statuses and default messages from the spec. Two of them answer at the same status as a validation failure but must remain distinguishable from one, so they carry a code of their own and no field map. One is the API-wide answer to a malformed path identifier, established here because this is the first feature with an id in a path and reused unchanged by later features.

**6. Contact Renderer** - Add the view producing the contact shape, embedding the contacted user through the shared user renderer rather than restating its fields, plus the wrappers for the single-contact and list responses.

**7. Contact Controller and Routes** - Add the controller with the create, list and delete actions, validating the request body the same way the auth controller validates a login, delegating every failure to the fallback controller, and taking the list owner exclusively from the authenticated connection. Register the three routes inside the router's existing authenticated scope.

### Stage 3: Test Suite and Quality Gate

**8. Context Test Suite** - Cover the resolution, guard ordering, uniqueness, unidirectionality, cascade behaviour, ordering guarantee and owner scoping described in the spec's testing strategy, including the paths that reach the database constraints rather than the context guards.

**9. Endpoint Test Suite** - Cover the three endpoints end to end against the real authenticated pipeline, one test per acceptance criterion, plus the cross-feature case that registers a user through the auth endpoint and then adds them by the username that registration returned. Extend the existing fallback controller test with the new reasons.

**10. Quality Gate Verification** - Run the full precommit chain and resolve every warning, formatting difference, Credo finding and coverage shortfall until it passes. Confirm the boundary compiler accepts the new context's declaration, its dependency on the accounts context and its export from the domain root.
