export type GroupContact = {
  initials: string
  name: string
  shortName: string
  username: string
  selected: boolean
}

export type Contact = {
  initials: string
  name: string
  username: string
}

export type ContactGroup = {
  initial: string
  contacts: Contact[]
}

export const groupContacts: GroupContact[] = [
  { initials: 'AB', name: 'Ana Beatriz', shortName: 'Ana', username: 'anabeatriz', selected: true },
  { initials: 'CE', name: 'Carlos Eduardo', shortName: 'Carlos', username: 'carloseduardo', selected: true },
  { initials: 'MS', name: 'Mariana Silva', shortName: 'Mariana', username: 'marianasilva', selected: true },
  { initials: 'JP', name: 'Joao Pedro', shortName: 'Joao', username: 'joaopedro', selected: false },
  { initials: 'LM', name: 'Leticia Moraes', shortName: 'Leticia', username: 'leticiamoraes', selected: false },
]

export const contactGroups: ContactGroup[] = [
  {
    initial: 'A',
    contacts: [{ initials: 'AB', name: 'Ana Beatriz', username: 'anabeatriz' }],
  },
  {
    initial: 'C',
    contacts: [{ initials: 'CE', name: 'Carlos Eduardo', username: 'carlosedu' }],
  },
  {
    initial: 'J',
    contacts: [{ initials: 'JP', name: 'Joao Pedro', username: 'joaopedro' }],
  },
  {
    initial: 'L',
    contacts: [{ initials: 'LM', name: 'Leticia Moraes', username: 'leticiam' }],
  },
  {
    initial: 'M',
    contacts: [
      { initials: 'MS', name: 'Mariana Silva', username: 'marianas' },
      { initials: 'RA', name: 'Rafael Alves', username: 'rafaelalves' },
    ],
  },
]
