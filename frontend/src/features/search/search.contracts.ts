import { decodePersistedMessage, type PersistedMessage } from '@/features/messaging/messaging.contracts'

export interface SearchMatchOffset {
  start: number
  length: number
}

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
    truncated: requireBoolean(data.truncated),
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

function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('Expected object')
  }

  return value as Record<string, unknown>
}

function requireNumber(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error('Expected number')
  }

  return value
}

function requireBoolean(value: unknown): boolean {
  if (typeof value !== 'boolean') {
    throw new Error('Expected boolean')
  }

  return value
}
