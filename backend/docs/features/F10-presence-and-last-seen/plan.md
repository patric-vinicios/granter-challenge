# Implementation Plan: Presence and Last Seen

**Prerequisites:**
- F07 complete: the socket transport, the token-authenticated handshake, the personal-topic channel with its "own id only" join rule and the conversation channel with its participation-gated join rule — all consumed here unchanged, and the surfaces this feature tracks and relays over
- F02 complete: the user record and its `last_seen_at` column, deliberately kept out of every changeset cast, which this feature is the single writer of
- F04 and F05 complete: the conversation detail read and its counterpart/member preload, whose rendered output this feature enriches with an online flag
- F01 complete: the endpoint, the PubSub server already supervised, the boundary declarations that keep the web layer one-way, and the channel case template
- **No migration, no new dependency, no new REST route, no environment variable.** One supervision-tree entry, one new web module, and one boundary export
- Scope is the whole feature: the PRD declares no Core/Full split for it
- Tests accompany each stage per the spec's Testing Strategy; follow the existing conventions — moduledocs explain why a decision was made and never name feature IDs, and commits use Conventional Commits

---

### Stage 1: Presence Foundation and Last-Seen Persistence

**1. Last-Seen Write Path** - Add the single domain function that stamps a user's last-seen timestamp, writing exactly that one column for one user without going through a changeset and without disturbing the profile-updated marker, and treating an unknown or unusable identifier as a harmless no-op so a write for a since-deleted account never fails.

**2. Presence Tracker** - Add the presence module over the existing publish-subscribe server, tracking each user under their own key on their personal topic. Implement its change callback so that a user's final disconnect — the moment no tracked connection for them remains — stamps their last-seen timestamp through the write path above, while a disconnect that leaves another connection open writes nothing. Expose an online lookup that answers whether a user currently holds any tracked connection.

**3. Supervision and Boundary** - Register the tracker in the supervision tree after the publish-subscribe server and ahead of the endpoint, so it exists before the first connection can be made, and export it from the web boundary so the application supervisor may name it while the domain still cannot reach it.

### Stage 2: Socket Tracking Lifecycle

**4. Track on Personal-Topic Join** - Extend the personal-topic channel so that joining it tracks the connection in presence with its connect time, reusing the channel's existing proof that the connection belongs to the user it names, so no presence entry can be forged for anyone else.

**5. Periodic Last-Seen Refresh** - Give each personal-topic connection a recurring refresh that re-stamps the user's last-seen timestamp while they remain connected, bounding how stale the stored value can become if a node dies without ever running the disconnect callback.

### Stage 3: Conversation-Scoped Presence Relay

**6. Presence State on Join** - Extend the conversation channel so that, once joined, it resolves the conversation's active participants and pushes the current presence of exactly those participants to the joining client, giving a freshly opened thread its counterpart's status without waiting for a change.

**7. Presence Diff Relay** - Have the conversation channel subscribe to each participant's presence topic and forward every subsequent connect and disconnect to the client as a scoped difference. Because it subscribes only to this conversation's participants, a change for an unrelated user has no path to the client, making the no-leak guarantee structural rather than a filter.

### Stage 4: Conversation Detail Enrichment and Quality Gate

**8. Online in the Conversation Detail** - Enrich the conversation detail rendering so each counterpart and each member carries an online flag beside the last-seen timestamp the user object already exposes, giving the header its correct first-paint state before any live difference arrives. Keep the flag confined to the conversation view rather than the shared user shape, since a message sender or contact entry has no online status to answer, and update the one existing exact-match assertion that this contract change touches.

**9. Quality Gate Verification** - Run the full precommit chain and resolve every warning, formatting difference, static-analysis finding and coverage shortfall until it passes. Confirm the boundary compiler accepts the new export and that no domain module reaches into the tracker, and verify against a live socket that connecting marks a user online, that a final disconnect writes the last-seen value within the accuracy the spec fixes, and that a second connection keeps them online until it too closes.
