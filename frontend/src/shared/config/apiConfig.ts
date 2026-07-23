const DEFAULT_API_URL = 'http://localhost:4000/api'
const DEFAULT_SOCKET_URL = 'ws://localhost:4000/socket'

export function getApiBaseUrl(): string {
  return (import.meta.env.VITE_API_URL || DEFAULT_API_URL).replace(/\/+$/, '')
}

export function getSocketUrl(): string {
  return (import.meta.env.VITE_SOCKET_URL || DEFAULT_SOCKET_URL).replace(/\/+$/, '')
}
