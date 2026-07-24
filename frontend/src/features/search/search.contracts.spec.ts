import { describe, expect, it } from 'vitest'

import { decodeConversationSearchResult } from './search.contracts'

describe('search contracts', () => {
  it('decodes search metadata, messages and match offsets', () => {
    expect(
      decodeConversationSearchResult({
        messages: [searchHit()],
        total_matches: 3,
        has_more: true,
      }),
    ).toMatchObject({
      matches: [
        {
          message: { id: 'message-1', body: 'Cronograma aprovado' },
          position: 2,
          matchOffsets: [{ start: 0, length: 10 }],
        },
      ],
      totalMatches: 3,
      truncated: true,
    })
  })

  it.each([
    null,
    {},
    { messages: {}, total_matches: 0, has_more: false },
    { messages: [{ ...searchHit(), match_offsets: {} }], total_matches: 1, has_more: false },
    { messages: [{ ...searchHit(), position: Number.NaN }], total_matches: 1, has_more: false },
    {
      messages: [{ ...searchHit(), match_offsets: [{ start: '0', length: 10 }] }],
      total_matches: 1,
      has_more: false,
    },
    { messages: [], total_matches: '0', has_more: false },
    { messages: [], total_matches: 0, has_more: 'false' },
  ])('rejects malformed search results %#', (payload) => {
    expect(() => decodeConversationSearchResult(payload)).toThrow()
  })
})

function searchHit() {
  return {
    id: 'message-1',
    conversation_id: 'conversation-1',
    body: 'Cronograma aprovado',
    inserted_at: '2026-07-24T10:00:00Z',
    sender: {
      id: 'user-1',
      username: 'ana',
      name: 'Ana',
      last_seen_at: null,
    },
    position: 2,
    match_offsets: [{ start: 0, length: 10 }],
  }
}
