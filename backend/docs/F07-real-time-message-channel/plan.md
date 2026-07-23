# Implementation Plan: Real-Time Message Channel

**Prerequisites:**
- F06 complete: the single message write path with its participation gate and body rules, the history read the client refetches after a reconnect, and the canonical message renderer this feature broadcasts unchanged
- F05 complete: the group membership lifecycle whose removal action triggers the revocation relay, and the departed-member state the join predicate already refuses
- F04 complete: the conversations context and its participation predicate, reused verbatim as the channel's only authorization rule
- F02 complete: the token issuance and verification entry point the socket authenticates with, and the user record it resolves
- F01 complete: the endpoint, the PubSub server already in the supervision tree, the boundary declarations that keep the web layer one-way, and the channel case template that has been scaffolded and unused until now
- **No migration, no new dependency, no environment variable. One supervision-tree entry and one socket declaration**
- Scope is the whole feature: the PRD declares no Core/Full split for it
- Follow the existing conventions: moduledocs explain why a decision was made and never name feature IDs, and commits use Conventional Commits

---

### Stage 1: Transport and Supporting Pieces

**1. Rate Limiter** - Add the per-user send limiter as a supervised process owning a public in-memory table, exposing a single function that records an attempt and answers either permission or the wait remaining. Register it in the supervision tree ahead of the endpoint and export it from the web boundary so the application supervisor may name it, and give it a periodic sweep that keeps the table proportional to active users rather than to registered ones.

**2. Fan-Out Recipients** - Add the function to the conversations context that resolves a conversation into the identities of its currently active members. It answers an empty list for a conversation that cannot be found or named, so a notification pass can never fail on a conversation that disappeared after a message was already committed.

**3. Socket Transport** - Add the socket module, resolving the connect credential through the existing token verification entry point and refusing the handshake on anything else, assigning the resolved account onto the connection, and deriving a per-account socket identity so every connection a person holds can be closed together. Declare it on the endpoint with the inbound frame ceiling and the origin allowlist the spec fixes, reusing the one the cross-origin configuration already reads.

### Stage 2: Channels

**4. Personal Topic Channel** - Add the channel for the per-account notification topic with its single rule: the topic must name the connected account and every other identifier is refused with the same answer. It accepts no inbound events and exists to receive the conversation notifications this feature emits and the presence traffic a later feature will add.

**5. Conversation Join** - Add the conversation channel with its join clause delegating to the existing participation predicate, so an outsider, a departed member, an unknown conversation and an unusable identifier all receive one indistinguishable refusal and the live surface can never disagree with the REST surface about who belongs.

**6. Send Handler** - Add the inbound send handler running the limiter before any database work, then the shared write path, and reply to the sender with the persisted record correlated by the reference the client supplied. Map each failure the write path can return onto its own reply shape, echo that reference on failures too, and answer an unrecognised event rather than letting the client wait on a reply that never comes.

**7. Message Broadcast** - Broadcast the persisted record to the conversation topic excluding only the sending connection, so the sender receives it exactly once through its reply while every other subscriber — including that person's own second device — receives it as an event. The payload is the canonical message shape unchanged, which is what makes a broadcast record and a history record the same object to a client.

**8. Conversation Notification** - After the broadcast, resolve the active members and push a conversation summary to each personal topic, carrying the conversation, the truncated preview, the sender and the timestamp, plus the indicator distinguishing the sender's own copy from everyone else's. Add the renderer for that payload alongside the existing conversation views rather than assembling it inside the channel.

### Stage 3: Membership Revocation

**9. Removal Relay** - Extend the member-removal action to announce the removal on the conversation topic once the context confirms it happened, keeping the domain free of any knowledge that channels exist and firing only on a removal that actually took effect.

**10. Revocation Handling** - Intercept that announcement in the conversation channel so each joined connection decides for itself: the one belonging to the removed member notifies its client and stops, and every other member's connection ignores it. A later join is already refused by the join rule, so nothing further is needed to keep them out.

### Stage 4: Test Suite

**11. Test Helper** - Extend the channel case template with a helper that produces an authenticated connection for an account, so no test in the suite restates the handshake.

**12. Limiter Tests** - Cover the limiter on its own, without a connection: the allowance exhausting exactly at its bound, the wait it reports, accounts counted independently, attribution that ignores which conversation an attempt came from, and the sweep clearing what has expired while leaving the current period intact.

**13. Socket Tests** - Cover the handshake: the credential that succeeds and the four that fail, the per-account socket identity, and the fact that a refused handshake leaves no connection through which any topic can be reached.

**14. Conversation Channel Tests** - Add the conversation suite covering every acceptance criterion: each join outcome sharing one refusal, the reply carrying the persisted record and its correlation reference, the sender receiving that record exactly once while a second device of the same person still receives the event, every body rule at and beyond its bounds producing an error and no delivery, the removal that takes effect mid-session, the allowance rejecting a send without persisting it, the notification reaching every member with the sender's copy distinguished, and concurrent senders producing exactly the expected number of stored messages and delivered events with none duplicated.

**15. Personal Channel Tests** - Cover the personal topic: joining one's own and being refused another's, an unusable identifier refused the same way, and a conversation notification arriving without the conversation topic ever being joined.

**16. Context and Cross-Feature Tests** - Extend the conversations suite with the recipient lookup, including its empty answers for an unknown and an unusable identifier. Then cover the two integration criteria: a delivered record matching field for field what the history endpoint returns for it, and a connection whose lifecycle and identity are the surface the presence feature will consume.

### Stage 5: Quality Gate

**17. Quality Gate Verification** - Run the full precommit chain and resolve every warning, formatting difference, static-analysis finding and coverage shortfall until it passes. Confirm the boundary compiler accepts the new export and that no channel reaches past the domain's declared contexts, and verify against a populated group that a single send performs the fixed number of database operations the spec states regardless of member count.
