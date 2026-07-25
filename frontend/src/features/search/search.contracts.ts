import {
  requireBoolean,
  requireNumber,
  requireRecord,
} from '@/shared/contracts/decoders'
import { decodePersistedMessage } from '@/shared/contracts/message'
import type { PersistedMessage } from '@/types/message'
import type { SearchMatchOffset } from '@/types/search'

export type { SearchMatchOffset } from '@/types/search'

export interface ConversationSearchHit {
  message: PersistedMessage
  position: number
  matchOffsets: SearchMatchOffset[]
}

export interface ConversationSearchResult {
  matches: ConversationSearchHit[]
  totalMatches: number
  truncated: boolean
}

export function decodeConversationSearchResult(payload: unknown): ConversationSearchResult {
  const data = requireRecord(payload)
  const messages = data.messages

  if (!Array.isArray(messages)) {
    throw new Error('Expected messages array')
  }

  return {
    matches: messages.map(decodeConversationSearchHit),
    totalMatches: requireNumber(data.total_matches),
    // The backend paginates search; requesting the max page (100), `has_more`
    // means more matches exist than are shown — the truncated indicator.
    truncated: requireBoolean(data.has_more),
  }
}

function decodeConversationSearchHit(payload: unknown): ConversationSearchHit {
  const data = requireRecord(payload)
  const offsets = data.match_offsets

  if (!Array.isArray(offsets)) {
    throw new Error('Expected match offsets array')
  }

  return {
    message: decodePersistedMessage(data),
    position: requireNumber(data.position),
    matchOffsets: offsets.map(decodeSearchMatchOffset),
  }
}

function decodeSearchMatchOffset(payload: unknown): SearchMatchOffset {
  const data = requireRecord(payload)

  return {
    start: requireNumber(data.start),
    length: requireNumber(data.length),
  }
}
