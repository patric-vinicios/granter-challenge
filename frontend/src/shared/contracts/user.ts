import type { ChatUser } from '@/types/user'

import {
  requireOptionalBoolean,
  requireOptionalNullableString,
  requireNullableString,
  requireRecord,
  requireString,
} from './decoders'

interface DecodeChatUserOptions {
  requireLastSeenAt?: boolean
}

export function decodeChatUser(
  payload: unknown,
  options: DecodeChatUserOptions = {},
): ChatUser {
  const data = requireRecord(payload)

  return {
    id: requireString(data.id),
    username: requireString(data.username),
    name: requireString(data.name),
    lastSeenAt: options.requireLastSeenAt
      ? requireNullableString(data.last_seen_at)
      : requireOptionalNullableString(data.last_seen_at),
    online: requireOptionalBoolean(data.online),
  }
}
