import type { UserIdentity } from '@/types/user'

export function matchesUserQuery(
  user: Pick<UserIdentity, 'name' | 'username'>,
  rawQuery: string,
): boolean {
  const query = rawQuery.trim().toLocaleLowerCase()

  if (!query) {
    return true
  }

  return `${user.name} ${user.username}`.toLocaleLowerCase().includes(query)
}
