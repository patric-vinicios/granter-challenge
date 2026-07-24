import type { UserIdentity } from '@/types/user'

export type AuthUser = UserIdentity

export interface AuthSession {
  user: AuthUser
  token: string
  expiresAt: string
}

export interface LoginRequest {
  username: string
  password: string
}

export interface RegisterRequest {
  username: string
  name: string
  password: string
}

export function decodeAuthSession(payload: unknown): AuthSession {
  const data = requireRecord(payload)
  const token = requireString(data.token)
  const expiresAt = requireString(data.expires_at)

  return {
    user: decodeUser(data.user),
    token,
    expiresAt,
  }
}

export function decodeCurrentUser(payload: unknown): AuthUser {
  const data = requireRecord(payload)

  return decodeUser(data.user)
}

export function decodeStoredSession(payload: unknown): AuthSession | null {
  try {
    return decodeStoredSessionValue(payload)
  } catch {
    return null
  }
}

function decodeStoredSessionValue(payload: unknown): AuthSession {
  const data = requireRecord(payload)

  return {
    user: decodeStoredUser(data.user),
    token: requireString(data.token),
    expiresAt: requireString(data.expiresAt),
  }
}

function decodeUser(payload: unknown): AuthUser {
  const data = requireRecord(payload)

  return {
    id: requireString(data.id),
    username: requireString(data.username),
    name: requireString(data.name),
    lastSeenAt: requireNullableString(data.last_seen_at),
  }
}

function decodeStoredUser(payload: unknown): AuthUser {
  const data = requireRecord(payload)

  return {
    id: requireString(data.id),
    username: requireString(data.username),
    name: requireString(data.name),
    lastSeenAt: requireNullableString(data.lastSeenAt),
  }
}

function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('Expected object')
  }

  return value as Record<string, unknown>
}

function requireString(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('Expected string')
  }

  return value
}

function requireNullableString(value: unknown): string | null {
  if (value === null) {
    return null
  }

  return requireString(value)
}
