import { isApiError } from '@/shared/api/errors'

export function conversationErrorMessage(error: unknown): string {
  if (isApiError(error)) {
    return error.message
  }

  return error instanceof Error ? error.message : 'Não foi possível atualizar a conversa.'
}
