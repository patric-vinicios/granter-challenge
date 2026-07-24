import { getApiBaseUrl } from '@/shared/config/apiConfig'

import { ApiError, decodeApiError, invalidResponseError, networkError } from './errors'

interface HttpRequestOptions<T> {
  method?: 'GET' | 'POST' | 'DELETE' | 'PATCH'
  body?: unknown
  token?: string
  signal?: AbortSignal
  decode: (payload: unknown) => T
}

let terminalAuthFailureHandler: (() => void) | null = null

export function setTerminalAuthFailureHandler(handler: (() => void) | null): void {
  terminalAuthFailureHandler = handler
}

export async function requestJson<T>(
  path: string,
  { method = 'GET', body, token, signal, decode }: HttpRequestOptions<T>,
): Promise<T> {
  let response: Response

  try {
    response = await fetch(`${getApiBaseUrl()}${path}`, {
      method,
      signal,
      headers: buildHeaders(body, token),
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch (error) {
    if (isAbortError(error)) {
      throw error
    }

    throw networkError()
  }

  const payload = await readJson(response)

  if (!response.ok) {
    const apiError = decodeApiError(payload)
    if (token && response.status === 401 && (apiError?.code === 'token_expired' || apiError?.code === 'unauthenticated')) {
      terminalAuthFailureHandler?.()
    }

    throw new ApiError(
      apiError ?? { code: 'invalid_response', detail: 'A resposta de erro do servidor e invalida.' },
      response.status,
    )
  }

  try {
    return decode(payload)
  } catch {
    throw invalidResponseError()
  }
}

function buildHeaders(body: unknown, token: string | undefined): HeadersInit {
  const headers: Record<string, string> = {
    Accept: 'application/json',
  }

  if (body !== undefined) {
    headers['Content-Type'] = 'application/json'
  }

  if (token) {
    headers.Authorization = `Bearer ${token}`
  }

  return headers
}

async function readJson(response: Response): Promise<unknown> {
  if (response.status === 204) {
    return null
  }

  try {
    return await response.json()
  } catch {
    return null
  }
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError'
}
