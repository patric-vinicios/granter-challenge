export interface SearchMatchOffset {
  start: number
  length: number
}

export type ConversationSearchStatus = 'idle' | 'loading' | 'validation' | 'success' | 'error'
