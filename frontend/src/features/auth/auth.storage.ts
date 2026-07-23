import { readJsonValue, writeJsonValue, clearStorageKey } from '@/shared/storage/jsonStorage'

import { type AuthSession, decodeStoredSession } from './auth.contracts'

const SESSION_KEY = 'granter.session'

export function readSession(): AuthSession | null {
  return decodeStoredSession(readJsonValue(SESSION_KEY))
}

export function writeSession(session: AuthSession): void {
  writeJsonValue(SESSION_KEY, session)
}

export function clearSession(): void {
  clearStorageKey(SESSION_KEY)
}
