export interface UserIdentity {
  id: string
  username: string
  name: string
  lastSeenAt: string | null
}

export interface ChatUser extends UserIdentity {
  online: boolean
}
