import { afterEach, describe, expect, it, vi } from 'vitest'

import { getApiBaseUrl, getSocketUrl } from './apiConfig'

describe('api config', () => {
  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it('uses local endpoints by default outside production', () => {
    vi.stubEnv('PROD', false)

    expect(getApiBaseUrl()).toBe('http://localhost:4000/api')
    expect(getSocketUrl()).toBe('ws://localhost:4000/socket')
  })

  it('normalizes configured endpoints', () => {
    vi.stubEnv('PROD', true)
    vi.stubEnv('VITE_API_URL', 'https://api.granter.test/api///')
    vi.stubEnv('VITE_SOCKET_URL', 'wss://api.granter.test/socket///')

    expect(getApiBaseUrl()).toBe('https://api.granter.test/api')
    expect(getSocketUrl()).toBe('wss://api.granter.test/socket')
  })

  it('allows same-origin production endpoints', () => {
    vi.stubEnv('PROD', true)
    vi.stubEnv('VITE_API_URL', '/api/')
    vi.stubEnv('VITE_SOCKET_URL', '/socket/')

    expect(getApiBaseUrl()).toBe('/api')
    expect(getSocketUrl()).toBe('/socket')
  })

  it('requires explicit production endpoints', () => {
    vi.stubEnv('PROD', true)

    expect(() => getApiBaseUrl()).toThrow('VITE_API_URL must be configured for production builds.')
    expect(() => getSocketUrl()).toThrow('VITE_SOCKET_URL must be configured for production builds.')
  })

  it('rejects localhost endpoints in production', () => {
    vi.stubEnv('PROD', true)
    vi.stubEnv('VITE_API_URL', 'http://localhost:4000/api')
    vi.stubEnv('VITE_SOCKET_URL', 'ws://127.0.0.1:4000/socket')

    expect(() => getApiBaseUrl()).toThrow('VITE_API_URL must not point to localhost in production.')
    expect(() => getSocketUrl()).toThrow('VITE_SOCKET_URL must not point to localhost in production.')
  })

  it('rejects endpoints with the wrong protocol', () => {
    vi.stubEnv('PROD', true)
    vi.stubEnv('VITE_API_URL', 'wss://api.granter.test/api')
    vi.stubEnv('VITE_SOCKET_URL', 'https://api.granter.test/socket')

    expect(() => getApiBaseUrl()).toThrow('VITE_API_URL must use one of these protocols: http:, https:')
    expect(() => getSocketUrl()).toThrow('VITE_SOCKET_URL must use one of these protocols: ws:, wss:')
  })
})
