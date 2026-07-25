export interface ChatMessage {
  id?: string
  side: 'in' | 'out'
  text: string
  time: string
  author?: string
  clientRef?: string
}

export interface ChatConversation {
  id: string
  type: 'private' | 'group'
  initials: string
  name: string
  subtitle: string
  preview: string
  time: string
  messages: ChatMessage[]
}
