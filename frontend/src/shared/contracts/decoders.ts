export function requireRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('Expected object')
  }

  return value as Record<string, unknown>
}

export function requireString(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('Expected string')
  }

  return value
}

export function requireNullableString(value: unknown): string | null {
  if (value === null) {
    return null
  }

  return requireString(value)
}

export function requireOptionalNullableString(value: unknown): string | null {
  if (value === undefined) {
    return null
  }

  return requireNullableString(value)
}

export function requireNumber(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error('Expected number')
  }

  return value
}

export function requireNullableNumber(value: unknown): number | null {
  if (value === null) {
    return null
  }

  return requireNumber(value)
}

export function requireBoolean(value: unknown): boolean {
  if (typeof value !== 'boolean') {
    throw new Error('Expected boolean')
  }

  return value
}

export function requireOptionalBoolean(value: unknown): boolean {
  if (value === undefined) {
    return false
  }

  return requireBoolean(value)
}
