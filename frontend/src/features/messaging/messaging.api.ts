import { requestJson } from '@/shared/api/httpClient'

import { decodeMessageHistoryPage, type MessageHistoryPage } from './messaging.contracts'

export function listMessages(
  conversationId: string,
  token: string,
  options: { before?: string | null; limit?: number; signal?: AbortSignal } = {},
): Promise<MessageHistoryPage> {
  return requestJson('/conversations/' + encodeURIComponent(conversationId) + '/messages' + queryString(options), {
    method: 'GET',
    token,
    signal: options.signal,
    decode: decodeMessageHistoryPage,
  })
}

function queryString(options: { before?: string | null; limit?: number }): string {
  const params = new URLSearchParams()

  if (options.limit !== undefined) {
    params.set('limit', String(options.limit))
  }

  if (options.before) {
    params.set('before', options.before)
  }

  const serialized = params.toString()

  return serialized ? `?${serialized}` : ''
}
