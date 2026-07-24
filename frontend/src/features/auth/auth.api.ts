import { requestJson } from '@/shared/api/httpClient'

import {
  type AuthSession,
  type AuthUser,
  decodeAuthSession,
  decodeCurrentUser,
  type LoginRequest,
  type RegisterRequest,
} from './auth.contracts'

export function login(request: LoginRequest, signal?: AbortSignal): Promise<AuthSession> {
  return requestJson('/auth/login', {
    method: 'POST',
    body: request,
    signal,
    decode: decodeAuthSession,
  })
}

export function register(request: RegisterRequest, signal?: AbortSignal): Promise<AuthSession> {
  return requestJson('/auth/register', {
    method: 'POST',
    body: request,
    signal,
    decode: decodeAuthSession,
  })
}

export function getCurrentUser(token: string, signal?: AbortSignal): Promise<AuthUser> {
  return requestJson('/auth/me', {
    token,
    signal,
    decode: decodeCurrentUser,
  })
}

export function logout(token: string, signal?: AbortSignal): Promise<void> {
  return requestJson('/auth/session', {
    method: 'DELETE',
    token,
    signal,
    decode: () => undefined,
  })
}
