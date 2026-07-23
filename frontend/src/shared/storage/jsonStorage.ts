export function readJsonValue(key: string): unknown | null {
  const raw = window.localStorage.getItem(key)

  if (!raw) {
    return null
  }

  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

export function writeJsonValue(key: string, value: unknown): void {
  window.localStorage.setItem(key, JSON.stringify(value))
}

export function clearStorageKey(key: string): void {
  window.localStorage.removeItem(key)
}
