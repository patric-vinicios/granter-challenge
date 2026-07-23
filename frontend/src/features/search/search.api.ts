import { requestJson } from '@/shared/api/httpClient'

import { decodeConversationSearchResult, type ConversationSearchResult } from './search.contracts'

export function searchConversationMessages(
  conversationId: string,
  query: string,
  token: string,
  signal?: AbortSignal,
): Promise<ConversationSearchResult> {
  const params = new URLSearchParams({ q: query })

  return requestJson(
    '/conversations/' + encodeURIComponent(conversationId) + '/messages/search?' + params.toString(),
    {
      method: 'GET',
      token,
      signal,
      decode: decodeConversationSearchResult,
    },
  )
}
