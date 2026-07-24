export type ApiErrorCode =
  | 'invalid_credentials'
  | 'token_expired'
  | 'unauthenticated'
  | 'validation_error'
  | 'network_error'
  | 'invalid_response'
  | string

export interface ApiErrorBody {
  code: ApiErrorCode
  detail: string
  fields?: Record<string, string[]>
}

export class ApiError extends Error {
  readonly code: ApiErrorCode
  readonly status: number | null
  readonly fields: Record<string, string[]> | undefined

  constructor(error: ApiErrorBody, status: number | null) {
    super(localizeErrorDetail(error))
    this.name = 'ApiError'
    this.code = error.code
    this.status = status
    this.fields = localizeFields(error.fields)
  }
}

export function isApiError(error: unknown): error is ApiError {
  return error instanceof ApiError
}

export function invalidResponseError(): ApiError {
  return new ApiError(
    {
      code: 'invalid_response',
      detail: 'A resposta do servidor não pôde ser lida.',
    },
    null,
  )
}

export function networkError(): ApiError {
  return new ApiError(
    {
      code: 'network_error',
      detail: 'Não foi possível conectar ao servidor.',
    },
    null,
  )
}

export function decodeApiError(payload: unknown): ApiErrorBody | null {
  if (!isRecord(payload) || !isRecord(payload.errors)) {
    return null
  }

  const { code, detail, fields } = payload.errors

  if (typeof code !== 'string' || typeof detail !== 'string') {
    return null
  }

  if (fields !== undefined && !isStringArrayRecord(fields)) {
    return null
  }

  return {
    code,
    detail,
    fields,
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function isStringArrayRecord(value: unknown): value is Record<string, string[]> {
  if (!isRecord(value)) {
    return false
  }

  return Object.values(value).every(
    (entry) => Array.isArray(entry) && entry.every((item) => typeof item === 'string'),
  )
}

function localizeErrorDetail(error: ApiErrorBody): string {
  const translatedDetail = localizeBackendDetail(error.detail)

  if (translatedDetail) {
    return translatedDetail
  }

  switch (error.code) {
    case 'network_error':
      return 'Não foi possível conectar ao servidor.'
    case 'invalid_response':
      return 'Não foi possível ler a resposta do servidor.'
    case 'rate_limited':
      // The backend detail carries a dynamic retry window, so map by code.
      return 'Muitas tentativas. Aguarde um momento e tente novamente.'
    default:
      return error.detail
  }
}

function localizeBackendDetail(detail: string): string | null {
  return backendDetailsPtBr[detail] ?? null
}

function localizeFields(fields: Record<string, string[]> | undefined): Record<string, string[]> | undefined {
  if (!fields) {
    return undefined
  }

  return Object.fromEntries(
    Object.entries(fields).map(([field, messages]) => [
      field,
      messages.map((message) => localizeFieldMessage(message)),
    ]),
  )
}

function localizeFieldMessage(message: string): string {
  const translated = backendFieldMessagesPtBr[message]
  if (translated) {
    return translated
  }

  const atLeastMatch = message.match(/^should be at least (\d+) character\(s\)$/)
  if (atLeastMatch) {
    return `deve ter pelo menos ${atLeastMatch[1]} caracteres`
  }

  const atMostMatch = message.match(/^should be at most (\d+) character\(s\)$/)
  if (atMostMatch) {
    return `deve ter no máximo ${atMostMatch[1]} caracteres`
  }

  return message
}

const backendDetailsPtBr: Record<string, string> = {
  'The request body is not valid JSON': 'O corpo da requisição não é um JSON válido.',
  'Authentication is required': 'Autenticação obrigatória.',
  'You are not allowed to perform this action': 'Você não tem permissão para executar esta ação.',
  'The requested resource was not found': 'O recurso solicitado não foi encontrado.',
  'This method is not supported for this path': 'Este método não é suportado para este caminho.',
  'The request conflicts with the current state': 'A requisição conflita com o estado atual.',
  'The request content-type must be application/json':
    'O tipo de conteúdo da requisição deve ser application/json.',
  'The request could not be processed': 'A solicitação não pôde ser processada.',
  'Too many requests, please retry later': 'Muitas requisições. Tente novamente mais tarde.',
  'Something went wrong': 'Algo deu errado.',
  'Database connection is not available': 'A conexão com o banco de dados não está disponível.',
  'Invalid username or password': 'Usuário ou senha inválidos.',
  'Missing or invalid authentication token': 'Token de autenticação ausente ou inválido.',
  'Your session has expired, please log in again': 'Sua sessão expirou. Entre novamente.',
  'The provided id is not a valid identifier': 'O id informado não é um identificador válido.',
  'The pagination cursor is invalid': 'O cursor de paginação é inválido.',
  'No user with that @username exists in the system': 'Nenhum usuário com esse @username existe no sistema.',
  'This user is already in your contacts': 'Este usuário já está nos seus contatos.',
  'You cannot add yourself as a contact': 'Você não pode adicionar a si mesmo como contato.',
  'You have reached the maximum of 500 contacts': 'Você atingiu o máximo de 500 contatos.',
  'You can only start conversations with your contacts':
    'Você só pode iniciar conversas com seus contatos.',
  'You cannot start a conversation with yourself': 'Você não pode iniciar uma conversa consigo mesmo.',
  'Only the group creator can manage members': 'Apenas o criador do grupo pode gerenciar membros.',
  'This user is already a member of the group': 'Este usuário já é membro do grupo.',
  'A group must keep at least one member': 'Um grupo deve manter pelo menos um membro.',
  'The group creator can only leave after every other member has left':
    'O criador só pode sair depois que os outros membros saírem.',
  'The creator cannot remove themselves; leave the group instead':
    'O criador não pode remover a si mesmo; saia do grupo.',
  'You have left this conversation': 'Você saiu desta conversa.',
  'A resposta do servidor não pôde ser lida.': 'A resposta do servidor não pôde ser lida.',
  'Não foi possível conectar ao servidor.': 'Não foi possível conectar ao servidor.',
  'Não foi possível ler a resposta do servidor.': 'Não foi possível ler a resposta do servidor.',
}

const backendFieldMessagesPtBr: Record<string, string> = {
  "can't be blank": 'não pode ficar em branco',
  'has already been taken': 'já está em uso',
  'must contain only lowercase letters, digits and underscores':
    'use apenas letras minúsculas, números e sublinhado',
}
