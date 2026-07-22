# Implementation Plan: User Account and JWT Authentication

**Prerequisites:**
- F01 complete: `Api.Schema` conventions, the JSON error envelope and fallback controller, the `citext` extension migration, and the `DataCase`/`ConnCase`/`Api.Factory` harness
- New dependencies: `guardian` (~> 2.3) for token issuance and the authenticated plug pipeline, `argon2_elixir` (~> 4.0) for password hashing
- `JWT_SECRET` is already read and guarded at boot by `config/runtime.exs`; this feature repoints it at the Guardian implementation module
- The test environment needs its own literal signing secret, since `config/runtime.exs` deliberately skips `:test`
- PostgreSQL 16 running via `docker-compose.dev.yml` (development) and `docker-compose.test.yml` (test)
- Scope is the PRD's Core Scope only: login rate limiting, logout and token revocation are deferred, and `ApiWeb.UserSocket` belongs to F07

---

### Stage 1: Data Layer and Domain Context

**1. Users Migration** - Generate the migration creating the users table with a case-insensitive unique username, a display name, a password hash column and the nullable last-seen timestamp reserved for presence. The spec gives the column types, index and rationale.

**2. User Schema and Changesets** - Add the user schema on the shared schema conventions, with the registration changeset that normalises the submitted username, enforces every field rule from the spec, hashes the password into its stored column and discards the plaintext. Ensure neither the hash nor the plaintext can be revealed by inspecting a struct.

**3. Accounts Context** - Add the accounts context exposing registration, credential authentication and the two lookup functions later features consume. Authentication must return the same failure regardless of whether the username exists, and must spend the same time on both paths. Declare the context's architectural sub-boundary and export it from the domain root.

**4. Token Module** - Add the Guardian implementation module that maps a user to a token subject and a verified token back to a user record, with the token lifetime the spec states. Wire its issuer and lifetime in the shared configuration and its signing secret through the existing environment variable in the runtime configuration.

**5. Test Configuration** - Give the test environment its own signing secret and reduce the password hashing cost parameters, so the suite is neither blocked on a missing secret nor dominated by deliberate hashing slowness.

### Stage 2: Authentication Layer

**6. Error Table Extension** - Extend the fallback controller with a reason-keyed table so a domain reason carries its own machine code at a status that already has a generic one, registering the three authentication codes from the spec. Preserve the existing behaviours: an explicit detail still overrides the default, and an unmapped reason still becomes a generic server error.

**7. Guardian Error Handler** - Add the handler that translates the token library's failure tuples into the domain reasons above and renders them through the fallback controller, so a rejection from the plug pipeline is indistinguishable in shape from a rejection raised inside a context.

**8. Authenticated Pipeline** - Assemble the plug pipeline that verifies the bearer header, requires an authenticated token, loads the corresponding user record, and finishes by exposing that record on the connection assign every later controller reads. Register it as a router pipeline alongside the existing public one.

### Stage 3: Endpoints and Rendering

**9. Shared User Renderer** - Add the single view responsible for the user shape returned anywhere in the API, along with the wrappers for this feature's authenticated and token-carrying responses. This renderer's field list is what keeps credential columns out of every payload from here on.

**10. Auth Controller and Routes** - Add the controller with the registration, login and current-user actions, delegating every failure to the fallback controller, and register the two public routes and the one authenticated route in the router. Registration and login both answer with the user record, a token and its expiry so no second round trip is needed.

### Stage 4: Test Suite and Quality Gate

**11. User Factory** - Add the user factory to the shared factory module, using a sequence for the unique username and a pre-computed hash so inserting test users stays cheap, while still letting login tests authenticate with a known plaintext.

**12. Domain and Web Test Suite** - Cover the changeset rules, the context's registration and authentication behaviour, token issuance and verification, the three endpoints end to end, and the plug pipeline's rejection paths, as detailed in the spec's testing strategy. Update the existing fallback controller test that asserted the old status-derived code for expired tokens.

**13. Quality Gate Verification** - Run the full precommit chain and resolve every warning, formatting difference, Credo finding and coverage shortfall until it passes. Confirm the boundary compiler accepts the new context's declaration and its export from the domain root.
