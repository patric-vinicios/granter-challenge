# Implementation Plan: Demo Seed Data

**Prerequisites:**
- F06 complete: `Api.Messages.create_message/3`, the single write path this feature backdates demo messages through, and the history endpoint the cross-feature test reads them back from
- F05 complete: `Api.Conversations.create_group/3` with its contact and size checks, and the `conversation_participants` rows the unread pass writes `last_read_at` onto
- F04 complete: `Api.Conversations.create_private_conversation/2` and the shared conversation tables
- F03 complete: `Api.Contacts.add_contact/2` and `contact?/2`, so the mesh is seeded through the same validation a real add passes
- F02 complete: `Api.Accounts.register_user/1` and `get_user_by_username/1`, the create-and-lookup pair the user step and the idempotency guard use
- F01 complete: the `Api.Schema` conventions, the `Api` boundary the new context is exported from, and the `DataCase`/`ConnCase`/`Api.Factory` harness
- **No migration, no new dependency, no environment variable. One new configuration key (`:api, :env`), one new context (`Api.Seeds`) and one data module (`Api.Seeds.Dataset`). `mix ecto.setup` and `docker-compose.dev.yml` already run the seed script, so neither changes**
- Scope is the whole feature: the PRD declares no Core/Full split for it
- Follow the existing conventions: moduledocs explain why a decision was made and never name feature IDs, reviewer-facing output is verbatim, and commits use Conventional Commits

---

### Stage 1: Configuration

**1. Environment Fact** - Add the application environment key to the base config so the production refusal is decided on a value that exists inside a release rather than on `Mix.env()`. Place it with the other `:api` application settings, sourced from the compile-time environment.

### Stage 2: Demo Content

**2. Dataset Module** - Add the dataset module as pure data: the shared password, the primary account, the seven users, and the six conversations each carrying its kind, participants, ordered transcript and declared unread depth. It accesses no database and aliases no context, so it can be tested and read on its own. Encode message timestamps as backward offsets from run time, not wall-clock times, and include the searchable term the later features rely on.

### Stage 3: Seed Interpreter

**3. Seeds Context** - Add the seeds context as its own boundary, declaring the four write contexts plus accounts as dependencies, and register it in the domain root's export list. Give it `run/0` delegating to `run/1` so the dataset is an injectable argument, which is what makes the rollback contract testable.

**4. Guards** - Implement the two guards that run before any transaction, in the fixed order the spec sets: refuse when the environment is production, printing a refusal and issuing no query; then return the skip result when the primary account already exists, printing the verbatim skip line. The production check runs first so the refusal is unconditional.

**5. Seeding Transaction** - Implement the single transaction that walks the dataset in dependency order — users looked up before insert then created through the accounts context, the full contact mesh, the private conversations, the groups, and every message through the message write path with its backdated timestamp on the struct. On any failed write, print the record label and its changeset errors and roll the whole transaction back so no partial dataset survives.

**6. Unread Pass** - After the messages land, write `last_read_at` on the participant rows through a direct update over the exported participant schema, so exactly the two declared conversations start unread for the primary account and every other participant starts read. Derive each read timestamp from the surrounding message times rather than a fixed value, so the resulting count is exactly the declared number.

**7. Failure Rescue and Summary** - Wrap the run so a missing table or an unreachable database is rescued and re-raised as an instruction to migrate, rather than surfacing a raw driver error. On success, print the summary line naming the counts written and return them so a caller can assert on them.

### Stage 4: Wiring

**8. Seed Script and Credentials** - Reduce the seed script to a single invocation of the new context, replacing the generator comment block, with a short comment pointing at the module that owns the content. Add the "Seeded accounts" section to the README listing the seven usernames, their display names and the shared password, and noting that the script is idempotent and refuses to run in production.

### Stage 5: Test Suite

**9. Dataset Tests** - Cover the dataset on its own with no database: the user and conversation counts the criteria fix, strictly increasing offsets within every conversation, no offset resolving into the future, every body within the length bounds, every sender a member of its conversation, the today/yesterday/last-week spread, the unread declarations naming only other senders' messages, and each group's creator being one of its members.

**10. Seed Behaviour Tests** - Add the seed suite: the full run and its counts, every user authenticating with the documented password, the complete contact mesh, the backdated spread, the exactly-two unread outcome for the primary account with everyone else read, idempotency returning the skip result, reuse of a pre-existing seeded username, every persisted body satisfying the runtime validations, the production refusal creating no record, the transaction rolling back fully on a bad record through an unboxed run, and the missing-schema instruction.

**11. Cross-Feature Tests** - Add the integration suite exercising the four PRD criteria that name this feature through the real endpoints: seeded users logging in and calling the current-user endpoint, seeded contact lists returned by the contacts endpoint, seeded groups returned by the group detail endpoint with the right creator and members, and seeded messages returned by the history endpoint in chronological order with their backdated timestamps and a working second page.

### Stage 6: Quality Gate

**12. Quality Gate Verification** - Run the full precommit chain and resolve every warning, formatting difference, Credo finding and coverage shortfall until it passes. Confirm the boundary compiler accepts the new context's declared dependencies and its registration in the domain root, then run the seed against a real development database twice to confirm a populated first run and a clean skip on the second.
