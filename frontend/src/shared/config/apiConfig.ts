const DEFAULT_API_URL = 'http://localhost:4000/api'
const DEFAULT_SOCKET_URL = 'ws://localhost:4000/socket'
const LOCAL_HOSTNAMES = new Set(['localhost', '127.0.0.1', '0.0.0.0', '[::1]'])

export function getApiBaseUrl(): string {
  return resolveEndpoint('VITE_API_URL', import.meta.env.VITE_API_URL, DEFAULT_API_URL, ['http:', 'https:'])
}

export function getSocketUrl(): string {
  return resolveEndpoint('VITE_SOCKET_URL', import.meta.env.VITE_SOCKET_URL, DEFAULT_SOCKET_URL, ['ws:', 'wss:'])
}

function resolveEndpoint(
  name: 'VITE_API_URL' | 'VITE_SOCKET_URL',
  configuredValue: string | undefined,
  localFallback: string,
  allowedProtocols: string[],
): string {
  const value = configuredValue?.trim()

  if (!value) {
    if (import.meta.env.PROD) {
      throw new Error(`${name} must be configured for production builds.`)
    }

    return localFallback
  }

  return normalizeEndpoint(name, value, allowedProtocols)
}

function normalizeEndpoint(
  name: 'VITE_API_URL' | 'VITE_SOCKET_URL',
  value: string,
  allowedProtocols: string[],
): string {
  const normalized = value.replace(/\/+$/, '')

  if (normalized.startsWith('/')) {
    return normalized || '/'
  }

  const url = new URL(normalized)

  if (!allowedProtocols.includes(url.protocol)) {
    throw new Error(`${name} must use one of these protocols: ${allowedProtocols.join(', ')}`)
  }

  if (import.meta.env.PROD && LOCAL_HOSTNAMES.has(url.hostname)) {
    throw new Error(`${name} must not point to localhost in production.`)
  }

  return normalized
}
