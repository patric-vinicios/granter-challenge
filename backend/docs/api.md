# Granter Chat — API Reference

Complete contract for the backend: every REST endpoint, the full WebSocket
contract, and every error code the API emits. It documents the system as built;
payload shapes are taken from the response view modules and the passing test
suite, so a client developer can integrate without reading Elixir.

## Table of contents

- [Conventions](#conventions)
  - [Base URL](#base-url)
  - [Authentication](#authentication)
  - [Error envelope](#error-envelope)
  - [Common objects](#common-objects)
- [REST endpoints](#rest-endpoints)
  - [Health](#health)
    - [`GET /api/health`](#get-apihealth)
  - [Authentication](#authentication-endpoints)
    - [`POST /api/auth/register`](#post-apiauthregister)
    - [`POST /api/auth/login`](#post-apiauthlogin)
    - [`GET /api/auth/me`](#get-apiauthme)
    - [`DELETE /api/auth/session`](#delete-apiauthsession)
  - [Contacts](#contacts)
    - [`POST /api/contacts`](#post-apicontacts)
    - [`GET /api/contacts`](#get-apicontacts)
    - [`DELETE /api/contacts/:id`](#delete-apicontactsid)
  - [Conversations](#conversations)
    - [`GET /api/conversations`](#get-apiconversations)
    - [`POST /api/conversations/private`](#post-apiconversationsprivate)
    - [`POST /api/conversations/groups`](#post-apiconversationsgroups)
    - [`GET /api/conversations/:id`](#get-apiconversationsid)
    - [`POST /api/conversations/:id/read`](#post-apiconversationsidread)
    - [`POST /api/conversations/:id/members`](#post-apiconversationsidmembers)
    - [`DELETE /api/conversations/:id/members/me`](#delete-apiconversationsidmembersme)
    - [`DELETE /api/conversations/:id/members/:user_id`](#delete-apiconversationsidmembersuser_id)
  - [Messages](#messages)
    - [`GET /api/conversations/:id/messages`](#get-apiconversationsidmessages)
    - [`GET /api/conversations/:id/messages/search`](#get-apiconversationsidmessagessearch)
- [WebSocket contract](#websocket-contract)
- [Error codes](#error-codes)

---

## Conventions

### Base URL

All routes are served under `http://localhost:4000` in local development. Every
path below is prefixed with `/api`.

### Authentication

Endpoints marked **Auth: Bearer** require an `Authorization` header carrying the
JWT issued by `POST /api/auth/register` or `POST /api/auth/login`:

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

The token is an HS256 JWT whose `sub` claim is the user id and whose `exp` is 7
days after issue. The **same token** authenticates the WebSocket connection (see
[WebSocket contract](#websocket-contract)). A missing or malformed header yields
`401 unauthenticated`; an expired token yields `401 token_expired`.

### Error envelope

Every non-2xx response, from any endpoint, has the same shape. Clients branch on
`errors.code` and may display `errors.detail` verbatim. `fields` is present only
on `422` validation failures, one list of messages per rejected field.

```json
{
  "errors": {
    "code": "validation_error",
    "detail": "The request could not be processed",
    "fields": {
      "username": ["has already been taken"]
    }
  }
}
```

The full set of `code` values is listed under [Error codes](#error-codes).

### Common objects

**User** — the one user shape reused across registration, contacts, message
senders and group members. `last_seen_at` is `null` until presence tracking
writes it.

```json
{
  "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
  "username": "anabeatriz",
  "name": "Ana Beatriz",
  "last_seen_at": "2026-07-23T14:02:11.482301Z"
}
```

**Message** — the one message shape, reused by history, search, and the
`message:new` WebSocket broadcast. `body` is returned verbatim; escaping is the
client's responsibility.

```json
{
  "id": "c1d2e3f4-5061-7283-94a5-b6c7d8e9f0a1",
  "conversation_id": "7f8e9d0c-1b2a-3948-5766-8594a3b2c1d0",
  "body": "Bom dia, tudo certo com o cronograma?",
  "inserted_at": "2026-07-23T13:59:02.104553Z",
  "sender": {
    "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
    "username": "anabeatriz",
    "name": "Ana Beatriz",
    "last_seen_at": "2026-07-23T14:02:11.482301Z"
  }
}
```

All timestamps are absolute ISO 8601 UTC with microsecond precision. All public
identifiers are UUID v4; sequential integers are never exposed.

---

## REST endpoints

### Health

#### `GET /api/health`

Liveness and database-connectivity probe. **Auth:** none.

**Success — `200 OK`**

```json
{ "status": "ok", "database": "up" }
```

**Error — `503 Service Unavailable`** (`database_unavailable`), when the Repo
cannot execute `SELECT 1`. The body carries both the probe fields and the
standard envelope:

```json
{
  "status": "error",
  "database": "down",
  "errors": {
    "code": "database_unavailable",
    "detail": "Database connection is not available"
  }
}
```

---

### Authentication endpoints

#### `POST /api/auth/register`

Create an account and receive a bearer token in the same response. **Auth:** none.

**Request body**

```json
{
  "username": "anabeatriz",
  "name": "Ana Beatriz",
  "password": "senha123"
}
```

`username`: 3–20 chars, lowercase letters, digits and underscore only; a leading
`@` is stripped before validation; case-insensitive and immutable after
registration. `name`: 2–60 chars. `password`: 8–72 chars, hashed with Argon2id,
never returned.

**Success — `201 Created`**

```json
{
  "user": {
    "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
    "username": "anabeatriz",
    "name": "Ana Beatriz",
    "last_seen_at": null
  },
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_at": "2026-07-30T14:00:00.000000Z"
}
```

**Error — `422 Unprocessable Entity`** (`validation_error`), e.g. a taken
username:

```json
{
  "errors": {
    "code": "validation_error",
    "detail": "The request could not be processed",
    "fields": { "username": ["has already been taken"] }
  }
}
```

---

#### `POST /api/auth/login`

Exchange credentials for a bearer token. **Auth:** none.

**Request body**

```json
{ "username": "anabeatriz", "password": "senha123" }
```

**Success — `200 OK`** — same shape as register (`user`, `token`, `expires_at`).

**Error — `401 Unauthorized`** (`invalid_credentials`) — identical body for an
unknown username and a wrong password, so response time and shape never reveal
whether an account exists:

```json
{
  "errors": {
    "code": "invalid_credentials",
    "detail": "Invalid username or password"
  }
}
```

**Error — `429 Too Many Requests`** (`rate_limited`) — after 10 failed attempts
from one IP or 5 for one username within 60 seconds; carries a `Retry-After`
header (seconds). Successful logins are never throttled.

---

#### `GET /api/auth/me`

Return the authenticated user. **Auth:** Bearer.

**Success — `200 OK`**

```json
{
  "user": {
    "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
    "username": "anabeatriz",
    "name": "Ana Beatriz",
    "last_seen_at": "2026-07-23T14:02:11.482301Z"
  }
}
```

**Error — `401 Unauthorized`** (`unauthenticated`) when the header is missing or
malformed:

```json
{
  "errors": {
    "code": "unauthenticated",
    "detail": "Missing or invalid authentication token"
  }
}
```

---

#### `DELETE /api/auth/session`

Log out, revoking the presented token until it would have expired. **Auth:** Bearer.

**Success — `204 No Content`** — no body. The same token is afterwards rejected
with `401` (`unauthenticated`) on every HTTP request and on a socket connect.

**Error — `401 Unauthorized`** (`unauthenticated`) when no valid token is sent.

---

### Contacts

#### `POST /api/contacts`

Add a user to the caller's contact list, resolved by `@username`. **Auth:** Bearer.

**Request body** — a leading `@` is accepted and stripped:

```json
{ "username": "carlosedu" }
```

**Success — `201 Created`** — `id` is the contact row id (the value a delete
addresses); `user.id` is the contacted user:

```json
{
  "contact": {
    "id": "d4e5f6a7-8b90-1c2d-3e4f-506172839405",
    "user": {
      "id": "1a2b3c4d-5e6f-7081-92a3-b4c5d6e7f809",
      "username": "carlosedu",
      "name": "Carlos Eduardo",
      "last_seen_at": null
    }
  }
}
```

**Errors**

- `404 Not Found` (`user_not_found`) — no such `@username`.
- `409 Conflict` (`contact_already_exists`) — already in the list; no second row created.
- `422 Unprocessable Entity` (`self_contact`) — adding oneself.
- `422 Unprocessable Entity` (`contact_limit_reached`) — the 500-contact cap is reached.

```json
{
  "errors": {
    "code": "user_not_found",
    "detail": "No user with that @username exists in the system"
  }
}
```

---

#### `GET /api/contacts`

List the caller's contacts, sorted by display name ascending (case- and
accent-insensitive). **Auth:** Bearer. Maximum 500 entries.

**Query parameters**

- `q` *(optional)* — filter by the contact's display name or `@username`, case-
  and accent-insensitive. Matching runs in the database against the same trigram
  indexes the conversation search uses, so a client never has to hold the whole
  list to filter it, and a person found here is never missed in the inbox
  search. A blank term is no filter at all.
- `limit` *(optional)* — page size, `1`–`200`, default `200`. A non-numeric or
  out-of-range value is `422 validation_error` under `fields.limit`.
- `cursor` *(optional)* — the `next_cursor` of a previous response. Opaque;
  build it only from a value the API returned. A malformed value, or one minted
  for a different list, is `400 invalid_cursor`.

Paging is shaped exactly as [`GET /api/conversations`](#get-apiconversations) is,
so one client implementation drives both. `next_cursor` is `null` exactly when
`has_more` is `false`. The cursor is a keyset over the full ordering — folded
display name, then user id — so contacts sharing a display name, or differing
only by accent or case, are never skipped at a page boundary.

**Success — `200 OK`**

```json
{
  "contacts": [
    {
      "id": "d4e5f6a7-8b90-1c2d-3e4f-506172839405",
      "user": {
        "id": "1a2b3c4d-5e6f-7081-92a3-b4c5d6e7f809",
        "username": "carlosedu",
        "name": "Carlos Eduardo",
        "last_seen_at": null
      }
    }
  ],
  "next_cursor": null,
  "has_more": false
}
```

**Error — `401 Unauthorized`** (`unauthenticated`) without a valid token.
**Error — `422 Unprocessable Entity`** (`validation_error`) for a `limit`
outside `1`–`200`.
**Error — `400 Bad Request`** (`invalid_cursor`) for a malformed `cursor`.

---

#### `DELETE /api/contacts/:id`

Remove a contact by its contact-row id. Existing conversations and messages with
that user are left intact. **Auth:** Bearer.

**Success — `204 No Content`** (empty body).

**Error — `404 Not Found`** (`not_found`) — unknown id, or a contact belonging
to another user (ownership is never disclosed as a 403):

```json
{
  "errors": {
    "code": "not_found",
    "detail": "The requested resource was not found"
  }
}
```

---

### Conversations

#### `GET /api/conversations`

The inbox: every conversation the caller actively participates in, with a
last-message preview and unread count, in one request. **Auth:** Bearer.

**Query parameters**

- `q` *(optional)* — filter by display title (counterpart display name or
  `@username` for private, group name for groups), case- and accent-insensitive,
  minimum 1 character. Matching runs in the database against trigram indexes, so
  the filter applies to the whole inbox and not only to the page that would have
  been returned. Returns the same entry shape as the unfiltered list. A group is
  matched by its own name only, never by a member's.
- `limit` *(optional)* — page size, `1`–`200`, default `200`. A non-numeric or
  out-of-range value is `422 validation_error` under `fields.limit`.
- `cursor` *(optional)* — the `next_cursor` of a previous response. Opaque;
  build it only from a value the API returned. A malformed value is
  `400 invalid_cursor` rather than a silent first page.

Ordered by last-message timestamp descending; conversations with no messages
sort after those that do, by their own creation time. `unread_count` is capped
at 99 with `unread_overflow: true` past that. For a private conversation
`counterpart` is set and `member_count` is `null`; for a group the reverse.

`next_cursor` is `null` exactly when `has_more` is `false`, so paging stops on
either. The cursor is a keyset over the full ordering, so conversations sharing
a last-message timestamp are never skipped at a page boundary.

**Success — `200 OK`**

```json
{
  "conversations": [
    {
      "id": "7f8e9d0c-1b2a-3948-5766-8594a3b2c1d0",
      "type": "private",
      "title": "Ana Beatriz",
      "counterpart": {
        "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
        "username": "anabeatriz",
        "name": "Ana Beatriz",
        "last_seen_at": "2026-07-23T14:02:11.482301Z"
      },
      "member_count": null,
      "last_message": {
        "id": "c1d2e3f4-5061-7283-94a5-b6c7d8e9f0a1",
        "body": "Bom dia, tudo certo com o cronograma?",
        "sender_id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
        "inserted_at": "2026-07-23T13:59:02.104553Z"
      },
      "unread_count": 2,
      "unread_overflow": false,
      "last_read_at": "2026-07-23T12:00:00.000000Z"
    },
    {
      "id": "3c2b1a09-8f7e-6d5c-4b3a-291807f6e5d4",
      "type": "group",
      "title": "Time de Produto",
      "counterpart": null,
      "member_count": 5,
      "last_message": null,
      "unread_count": 0,
      "unread_overflow": false,
      "last_read_at": null
    }
  ],
  "next_cursor": "MjAyNi0wNy0yM1QxMzo1OTowMi4xMDQ1NTNafDIwMjYtMDctMjBUMDk6MTQ6MDBafDdmOGU5ZDBjLTFiMmEtMzk0OC01NzY2LTg1OTRhM2IyYzFkMA",
  "has_more": true
}
```

**Error — `401 Unauthorized`** (`unauthenticated`) without a valid token.
**Error — `422 Unprocessable Entity`** (`validation_error`) for a `limit`
outside `1`–`200`.
**Error — `400 Bad Request`** (`invalid_cursor`) for a malformed `cursor`.

---

#### `POST /api/conversations/private`

Open (or retrieve) a private conversation with a contact. Idempotent: the same
pair always resolves to the same conversation. **Auth:** Bearer.

**Request body**

```json
{ "user_id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8" }
```

**Success**

- `201 Created` — first creation.
- `200 OK` — the pair already had a conversation; the identical id is returned.

```json
{
  "conversation": {
    "id": "7f8e9d0c-1b2a-3948-5766-8594a3b2c1d0",
    "type": "private",
    "last_read_at": null,
    "counterpart": {
      "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
      "username": "anabeatriz",
      "name": "Ana Beatriz",
      "last_seen_at": "2026-07-23T14:02:11.482301Z",
      "online": true
    }
  }
}
```

**Errors**

- `403 Forbidden` (`not_a_contact`) — the target is not in the caller's contacts.
- `404 Not Found` (`user_not_found`) — the target user id does not exist.
- `422 Unprocessable Entity` (`self_conversation`) — opening one with oneself.

```json
{
  "errors": {
    "code": "not_a_contact",
    "detail": "You can only start conversations with your contacts"
  }
}
```

---

#### `POST /api/conversations/groups`

Create a group. The creator is added automatically and must not appear in
`member_ids`; every id in `member_ids` must be a contact of the creator,
validated as a set before any insert. **Auth:** Bearer.

**Request body** — `name` 1–60 chars; 1–255 member ids (2–256 total members):

```json
{
  "name": "Time de Produto",
  "member_ids": [
    "1a2b3c4d-5e6f-7081-92a3-b4c5d6e7f809",
    "2b3c4d5e-6f70-8192-a3b4-c5d6e7f8091a"
  ]
}
```

**Success — `201 Created`**

```json
{
  "conversation": {
    "id": "3c2b1a09-8f7e-6d5c-4b3a-291807f6e5d4",
    "type": "group",
    "name": "Time de Produto",
    "creator_id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
    "member_count": 3,
    "members": [
      {
        "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
        "username": "anabeatriz",
        "name": "Ana Beatriz",
        "last_seen_at": "2026-07-23T14:02:11.482301Z",
        "online": true
      },
      {
        "id": "1a2b3c4d-5e6f-7081-92a3-b4c5d6e7f809",
        "username": "carlosedu",
        "name": "Carlos Eduardo",
        "last_seen_at": null,
        "online": false
      }
    ]
  }
}
```

**Errors**

- `403 Forbidden` (`not_a_contact`) — one or more `member_ids` are not contacts;
  the offending usernames are named in `detail` and no group is created.
- `422 Unprocessable Entity` (`validation_error`) — empty `member_ids` or a name
  outside 1–60 chars, with the offending field in `fields`.

```json
{
  "errors": {
    "code": "not_a_contact",
    "detail": "These users are not in your contacts: @carlosedu, @joaopedro"
  }
}
```

---

#### `GET /api/conversations/:id`

Conversation detail. For a private conversation the counterpart is returned with
live `online` status; for a group, the ordered member list with per-member
`online`. Restricted to participants (active members for a group). **Auth:** Bearer.

**Success — `200 OK` (private)**

```json
{
  "conversation": {
    "id": "7f8e9d0c-1b2a-3948-5766-8594a3b2c1d0",
    "type": "private",
    "last_read_at": "2026-07-23T12:00:00.000000Z",
    "counterpart": {
      "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
      "username": "anabeatriz",
      "name": "Ana Beatriz",
      "last_seen_at": "2026-07-23T14:02:11.482301Z",
      "online": false
    }
  }
}
```

**Success — `200 OK` (group)** — same shape as the group-creation response
(`id`, `type`, `name`, `creator_id`, `member_count`, `members`).

**Error — `404 Not Found`** (`not_found`) — a non-participant, or a non-member of
a group; conversation existence is never disclosed to outsiders.

---

#### `POST /api/conversations/:id/read`

Mark the conversation read for the caller, setting `last_read_at` to the server's
current time. Idempotent; `last_read_at` never moves backwards. Restricted to
participants. **Auth:** Bearer. No request body.

**Success — `200 OK`**

```json
{
  "conversation_id": "7f8e9d0c-1b2a-3948-5766-8594a3b2c1d0",
  "last_read_at": "2026-07-23T14:05:33.912004Z",
  "unread_count": 0
}
```

**Errors**

- `404 Not Found` (`not_found`) — caller does not participate.
- `403 Forbidden` (`not_a_participant`) — caller has left the conversation.
- `400 Bad Request` (`invalid_id`) — the id is not a valid UUID.

```json
{
  "errors": {
    "code": "invalid_id",
    "detail": "The provided id is not a valid identifier"
  }
}
```

---

#### `POST /api/conversations/:id/members`

Add members to a group. Creator only; each id must be a contact of the creator
and not already an active member. Re-adding a user who previously left clears
their `left_at` and sets a new `joined_at`. **Auth:** Bearer.

**Request body**

```json
{ "member_ids": ["3c4d5e6f-7081-92a3-b4c5-d6e7f8091a2b"] }
```

**Success — `200 OK`** — the updated group detail (same shape as `GET
/api/conversations/:id` for a group). Each newly seated member is also pushed a
[`conversation:added`](#conversationadded--on-userid) event on their personal
topic so their session can add the group to the inbox without a reload.

**Errors**

- `403 Forbidden` (`not_group_creator`) — the caller is not the creator.
- `403 Forbidden` (`not_a_contact`) — a listed user is not a contact of the creator.
- `409 Conflict` (`already_member`) — a listed user is already active.

```json
{
  "errors": {
    "code": "not_group_creator",
    "detail": "Only the group creator can manage members"
  }
}
```

---

#### `DELETE /api/conversations/:id/members/me`

Leave a group. Any member may leave; the creator may leave only if at least one
other active member remains (the group keeps its original `creator_id`). **Auth:**
Bearer.

**Success — `204 No Content`** (empty body).

**Error — `422 Unprocessable Entity`** (`last_member`) — the last active member
attempting to leave:

```json
{
  "errors": {
    "code": "last_member",
    "detail": "A group must keep at least one member"
  }
}
```

---

#### `DELETE /api/conversations/:id/members/:user_id`

Remove a member from a group. Creator only; the creator cannot remove
themselves this way (they must leave instead). Sets the member's `left_at`.
**Auth:** Bearer.

**Success — `204 No Content`** (empty body).

**Errors**

- `403 Forbidden` (`not_group_creator`) — the caller is not the creator.
- `422 Unprocessable Entity` (`cannot_remove_self`) — the creator targeting their
  own id.

```json
{
  "errors": {
    "code": "cannot_remove_self",
    "detail": "The creator cannot remove themselves; leave the group instead"
  }
}
```

---

### Messages

#### `GET /api/conversations/:id/messages`

Keyset-paginated history, always returned ascending by `(inserted_at, id)`.
Restricted to participants. **Auth:** Bearer.

**Query parameters**

- `limit` *(optional)* — page size, default 30, maximum 100.
- `before` *(optional)* — an opaque base64 cursor from a previous response's
  `next_cursor`; fetches the page immediately older than it.

`next_cursor` is `null` exactly on the page containing the oldest message; drive
"load more" off `has_more`.

**Success — `200 OK`**

```json
{
  "messages": [
    {
      "id": "c1d2e3f4-5061-7283-94a5-b6c7d8e9f0a1",
      "conversation_id": "7f8e9d0c-1b2a-3948-5766-8594a3b2c1d0",
      "body": "Bom dia, tudo certo com o cronograma?",
      "inserted_at": "2026-07-23T13:59:02.104553Z",
      "sender": {
        "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
        "username": "anabeatriz",
        "name": "Ana Beatriz",
        "last_seen_at": "2026-07-23T14:02:11.482301Z"
      }
    }
  ],
  "next_cursor": "ZzoyMDI2LTA3LTIzVDEzOjU5OjAyLjEwNDU1M1p8YzFkMmUzZjQ=",
  "has_more": true
}
```

**Errors**

- `400 Bad Request` (`invalid_cursor`) — a tampered or non-decodable `before`;
  the endpoint never silently falls back to the first page.
- `422 Unprocessable Entity` (`validation_error`) — `limit` above 100 or
  non-numeric.
- `404 Not Found` (`not_found`) — requested by a non-participant; no message
  content is returned.

```json
{
  "errors": {
    "code": "invalid_cursor",
    "detail": "The pagination cursor is invalid"
  }
}
```

---

#### `GET /api/conversations/:id/messages/search`

Full-text search within one conversation. Restricted to participants. **Auth:**
Bearer.

**Query parameters**

- `q` *(required)* — the search term, 2–100 chars after trimming; accent- and
  case-insensitive (`websearch_to_tsquery` over a Portuguese `tsvector`).

Results are newest-first, capped at 100. Each hit is the canonical message object
augmented with `position` (1-based) and `match_offsets` (a list of
`{ "start", "length" }` grapheme spans of the matched term in `body`, `start`
0-based). `total_matches` is exact at or below 100, otherwise reported as 100 with
`truncated: true`.

**Success — `200 OK`**

```json
{
  "messages": [
    {
      "id": "c1d2e3f4-5061-7283-94a5-b6c7d8e9f0a1",
      "conversation_id": "7f8e9d0c-1b2a-3948-5766-8594a3b2c1d0",
      "body": "Bom dia, tudo certo com o cronograma?",
      "inserted_at": "2026-07-23T13:59:02.104553Z",
      "sender": {
        "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
        "username": "anabeatriz",
        "name": "Ana Beatriz",
        "last_seen_at": "2026-07-23T14:02:11.482301Z"
      },
      "position": 1,
      "match_offsets": [{ "start": 26, "length": 10 }]
    }
  ],
  "total_matches": 1,
  "truncated": false
}
```

A search with no matches returns `200` with an empty `messages` array and
`total_matches: 0` — never `404`.

**Errors**

- `422 Unprocessable Entity` (`validation_error`) — `q` shorter than 2 or longer
  than 100 characters; no database scan is executed.
- `404 Not Found` (`not_found`) — requested by a non-participant.

```json
{
  "errors": {
    "code": "validation_error",
    "detail": "The request could not be processed",
    "fields": { "q": ["should be at least 2 character(s)"] }
  }
}
```

---

## WebSocket contract

Real-time delivery runs over Phoenix Channels. Channel topics and events are not
discoverable from the router; this section is their contract.

### Socket

- **URL:** `ws://localhost:4000/socket/websocket`
- **Connect param:** `token` — the **same JWT** used for HTTP requests, passed as
  a URL/connect parameter (a browser `WebSocket` cannot set an `Authorization`
  header).
- **Handshake:** a missing, malformed, expired or revoked token fails the
  handshake (the socket returns `:error`, surfaced to the client as a `403`); no
  channel can be joined.
- **Socket id:** `user_socket:<user_id>`, so all of a user's sockets can be
  disconnected together (used by presence and membership revocation).

Example (Phoenix JS client):

```js
import { Socket } from "phoenix"

const socket = new Socket("/socket", { params: { token: jwt } })
socket.connect()
```

### Topics and join rules

| Topic | Purpose | Join rule |
|-------|---------|-----------|
| `conversation:<conversation_id>` | Message traffic and presence for one conversation | Join calls the same participant predicate as REST. A non-participant, a departed group member, an unknown id and a malformed id all receive the identical `{ "reason": "unauthorized" }` — the socket is never an oracle for ids REST refuses to confirm. |
| `user:<user_id>` | The caller's personal notification topic | The topic id must equal the authenticated user's own id. Joining any other `user:` id (well-formed or not) is rejected with `{ "reason": "unauthorized" }`. |

A rejected join is delivered as the channel `join` error reply:

```json
{ "reason": "unauthorized" }
```

### Inbound events

Sent by the client with `channel.push(event, payload)`.

#### `new_message` — on `conversation:<id>`

Persist a message and broadcast it to the conversation. Persist-then-broadcast:
the insert commits before anything is broadcast, so no client ever sees a message
a history read cannot return.

**Payload**

```json
{ "body": "Bom dia, tudo certo com o cronograma?", "client_ref": "c-42" }
```

`client_ref` is optional and client-generated; it is echoed back on every reply
(success and error) so the client can reconcile the right optimistic bubble.

**Success reply** — `{:ok, ...}`. The sender receives the persisted record here,
exactly once; it is excluded from the `message:new` broadcast for the sending
channel process.

```json
{
  "message": {
    "id": "c1d2e3f4-5061-7283-94a5-b6c7d8e9f0a1",
    "conversation_id": "7f8e9d0c-1b2a-3948-5766-8594a3b2c1d0",
    "body": "Bom dia, tudo certo com o cronograma?",
    "inserted_at": "2026-07-23T13:59:02.104553Z",
    "sender": {
      "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
      "username": "anabeatriz",
      "name": "Ana Beatriz",
      "last_seen_at": "2026-07-23T14:02:11.482301Z"
    }
  },
  "client_ref": "c-42"
}
```

**Error replies** — `{:error, ...}`, no broadcast emitted:

```json
{ "reason": "validation_error", "fields": { "body": ["can't be blank"] }, "client_ref": "c-42" }
```

```json
{ "reason": "rate_limited", "retry_after_ms": 4200, "client_ref": "c-42" }
```

```json
{ "reason": "unauthorized", "client_ref": "c-42" }
```

The send rate limit is 20 messages per 10 seconds per user across all
conversations; `unauthorized` here covers a conversation that vanished under the
sender. Any event name other than `new_message` replies
`{ "reason": "unknown_event", "client_ref": ... }`. The `user:<id>` topic accepts
no inbound events and answers any push with `{ "reason": "unknown_event" }`.

### Outbound events

Pushed by the server; the client handles them with `channel.on(event, cb)`.

#### `message:new` — on `conversation:<id>`

The persisted message record (the [Message](#common-objects) object), delivered
to every participant with the topic joined **except** the sender.

```json
{
  "id": "c1d2e3f4-5061-7283-94a5-b6c7d8e9f0a1",
  "conversation_id": "7f8e9d0c-1b2a-3948-5766-8594a3b2c1d0",
  "body": "Bom dia, tudo certo com o cronograma?",
  "inserted_at": "2026-07-23T13:59:02.104553Z",
  "sender": {
    "id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
    "username": "anabeatriz",
    "name": "Ana Beatriz",
    "last_seen_at": "2026-07-23T14:02:11.482301Z"
  }
}
```

#### `conversation:updated` — on `user:<id>`

Pushed to **each** participant's personal topic on every new message, so the
conversation list reorders and badges without joining every conversation topic.
`unread` is simply "someone other than you sent it".

```json
{
  "conversation_id": "7f8e9d0c-1b2a-3948-5766-8594a3b2c1d0",
  "last_message": {
    "preview": "Bom dia, tudo certo com o cronograma?",
    "sender_id": "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
    "inserted_at": "2026-07-23T13:59:02.104553Z"
  },
  "unread": true
}
```

The `preview` is a leading slice of up to 120 characters.

#### `conversation:added` — on `user:<id>`

Pushed to a user the moment the group creator adds them (`POST
/api/conversations/:id/members`), on their personal topic — the one place their
session listens before they are a participant. It carries only the conversation
id; the client fetches `GET /api/conversations/:id` to populate the new inbox
entry. A re-added member who previously left is notified the same way.

```json
{ "conversation_id": "3c2b1a09-8f7e-6d5c-4b3a-291807f6e5d4" }
```

#### `presence:state` — on `conversation:<id>`

Pushed once on join: the current presence snapshot of exactly this
conversation's participants, keyed by user id. Presence is never exposed for
users the caller shares no conversation with.

```json
{
  "9a1f2b3c-4d5e-6f70-8192-a3b4c5d6e7f8": {
    "metas": [{ "phx_ref": "F9x1...", "online_at": "2026-07-23T14:02:11.482301Z" }]
  }
}
```

#### `presence:diff` — on `conversation:<id>`

Pushed when a participant of this conversation connects or disconnects. Standard
`Phoenix.Presence` diff of joins and leaves.

```json
{
  "joins": {
    "1a2b3c4d-5e6f-7081-92a3-b4c5d6e7f809": {
      "metas": [{ "phx_ref": "G2a4...", "online_at": "2026-07-23T14:06:00.000000Z" }]
    }
  },
  "leaves": {}
}
```

#### `conversation:membership_revoked` — on `conversation:<id>`

Pushed to a member the moment they are removed from a group, immediately before
their channel process is stopped; a subsequent rejoin is rejected.

```json
{ "conversation_id": "3c2b1a09-8f7e-6d5c-4b3a-291807f6e5d4" }
```

---

## Error codes

Every `errors.code` the API emits, with its HTTP status and meaning. Endpoint-
level codes are owned by `ApiWeb.ErrorJSON`; domain codes by
`ApiWeb.FallbackController`. A client can branch exhaustively on this table.

| Code | Status | Meaning |
|------|--------|---------|
| `malformed_request` | 400 | Request body is not valid JSON. |
| `invalid_id` | 400 | A path segment is not a valid UUID. |
| `invalid_cursor` | 400 | The pagination `before` cursor is tampered or non-decodable. |
| `unauthenticated` | 401 | Missing or malformed `Authorization` header. |
| `invalid_credentials` | 401 | Login username/password did not match (identical for unknown user and wrong password). |
| `token_expired` | 401 | The bearer token is past its `exp`; prompt for re-login. |
| `forbidden` | 403 | Authenticated but not permitted to perform this action. |
| `not_a_contact` | 403 | The target user (or a listed group member) is not in the caller's contacts. |
| `not_group_creator` | 403 | Only the group creator can manage members. |
| `not_a_participant` | 403 | The caller has left this conversation. |
| `not_found` | 404 | Resource absent or not visible to the caller. |
| `user_not_found` | 404 | No user with the given `@username` or id exists. |
| `method_not_allowed` | 405 | HTTP method not supported for this path. |
| `conflict` | 409 | The request conflicts with the current state. |
| `contact_already_exists` | 409 | The user is already in the caller's contacts. |
| `already_member` | 409 | The user is already an active member of the group. |
| `unsupported_media_type` | 415 | The request content-type must be `application/json`. |
| `validation_error` | 422 | A changeset validation failed; `fields` carries per-field messages. |
| `self_contact` | 422 | A user cannot add themselves as a contact. |
| `contact_limit_reached` | 422 | The 500-contact limit has been reached. |
| `self_conversation` | 422 | A user cannot start a private conversation with themselves. |
| `last_member` | 422 | A group must keep at least one member. |
| `cannot_remove_self` | 422 | The creator cannot remove themselves; they must leave instead. |
| `rate_limited` | 429 | Too many requests; retry later (a `Retry-After` header may accompany it). |
| `internal_error` | 500 | An unexpected server error; the stacktrace is logged, never returned. |
| `database_unavailable` | 503 | The database connection is not available (health probe). |

### Channel reply reasons

The WebSocket surface uses a parallel set of `reason` values in its error
replies (not HTTP statuses):

| Reason | Meaning |
|--------|---------|
| `unauthorized` | Join rejected, or a `new_message` targeting a conversation the sender may no longer post to. |
| `rate_limited` | Send rate limit exceeded; the reply carries `retry_after_ms`. |
| `validation_error` | The message changeset failed; the reply carries `fields`. |
| `unknown_event` | An inbound event the channel does not handle. |
