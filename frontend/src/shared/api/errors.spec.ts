import { describe, expect, it } from 'vitest'

import {
  ApiError,
  decodeApiError,
  invalidResponseError,
  isApiError,
  networkError,
} from './errors'

describe('API errors', () => {
  it('decodes valid error envelopes and rejects malformed fields', () => {
    expect(
      decodeApiError({
        errors: {
          code: 'validation_error',
          detail: 'Invalid',
          fields: { username: ["can't be blank"] },
        },
      }),
    ).toEqual({
      code: 'validation_error',
      detail: 'Invalid',
      fields: { username: ["can't be blank"] },
    })

    expect(decodeApiError(null)).toBeNull()
    expect(decodeApiError({ errors: [] })).toBeNull()
    expect(decodeApiError({ errors: { code: 1, detail: 'Invalid' } })).toBeNull()
    expect(
      decodeApiError({
        errors: { code: 'validation_error', detail: 'Invalid', fields: { username: [1] } },
      }),
    ).toBeNull()
  })

  it('localizes known backend details and preserves unknown details', () => {
    expect(
      new ApiError(
        { code: 'invalid_credentials', detail: 'Invalid username or password' },
        401,
      ).message,
    ).toBe('Usuário ou senha inválidos.')
    expect(new ApiError({ code: 'custom', detail: 'Custom detail' }, 422).message).toBe(
      'Custom detail',
    )
  })

  it('localizes rate limits by code so dynamic details remain safe', () => {
    expect(
      new ApiError({ code: 'rate_limited', detail: 'Retry after 27 seconds' }, 429).message,
    ).toBe('Muitas tentativas. Aguarde um momento e tente novamente.')
  })

  it('localizes field messages including dynamic length constraints', () => {
    const error = new ApiError(
      {
        code: 'validation_error',
        detail: 'Invalid',
        fields: {
          username: ["can't be blank", 'has already been taken'],
          password: [
            'should be at least 8 character(s)',
            'should be at most 72 character(s)',
            'custom rule',
          ],
        },
      },
      422,
    )

    expect(error.fields).toEqual({
      username: ['não pode ficar em branco', 'já está em uso'],
      password: [
        'deve ter pelo menos 8 caracteres',
        'deve ter no máximo 72 caracteres',
        'custom rule',
      ],
    })
  })

  it('builds typed network and invalid-response failures', () => {
    const network = networkError()
    const invalid = invalidResponseError()

    expect(isApiError(network)).toBe(true)
    expect(network).toMatchObject({ code: 'network_error', status: null })
    expect(invalid).toMatchObject({ code: 'invalid_response', status: null })
    expect(isApiError(new Error('plain'))).toBe(false)
  })
})
