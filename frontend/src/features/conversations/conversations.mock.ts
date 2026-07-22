export type Message = {
  side: 'in' | 'out'
  text: string
  time: string
  wide?: boolean
  author?: string
}

export type Conversation = {
  id: string
  type: 'private' | 'group'
  initials: string
  name: string
  subtitle: string
  preview: string
  time: string
  messages: Message[]
}

export const conversations: Conversation[] = [
  {
    id: 'ana',
    type: 'private',
    initials: 'AB',
    name: 'Ana Beatriz',
    subtitle: 'visto por ultimo ha 5 min',
    preview: 'Voce: Perfeito, fico no aguardo entao',
    time: '14:33',
    messages: [
      { side: 'in', text: 'Oi! Conseguiu ver a proposta que te enviei?', time: '14:20' },
      { side: 'out', text: 'Vi sim, ficou otima', time: '14:24' },
      {
        side: 'out',
        text: 'So queria ajustar a parte de cronograma antes de fechar',
        time: '14:24',
        wide: true,
      },
      {
        side: 'in',
        text: 'Boa, faz sentido. Consigo mexer nisso hoje a tarde',
        time: '14:29',
        wide: true,
      },
      { side: 'in', text: 'Te mando a versao revisada ainda hoje', time: '14:32' },
      { side: 'out', text: 'Perfeito, fico no aguardo entao', time: '14:33' },
    ],
  },
  {
    id: 'produto',
    type: 'group',
    initials: 'TP',
    name: 'Time de Produto',
    subtitle: '5 membros · Voce, Rafael, Ana, +2',
    preview: 'Voce: Combinado, obrigado pessoal',
    time: '10:03',
    messages: [
      {
        side: 'in',
        author: 'Rafael Alves',
        text: 'Bom dia pessoal! Subi a build de staging pra validacao',
        time: '09:12',
        wide: true,
      },
      { side: 'in', author: 'Ana Beatriz', text: 'Testando agora, ja te falo', time: '09:20' },
      {
        side: 'out',
        text: 'Aqui rodou tudo certo, so o login que ta lento',
        time: '09:34',
        wide: true,
      },
      { side: 'in', author: 'Leticia Moraes', text: 'E o cache, ja to resolvendo', time: '09:41' },
      {
        side: 'in',
        author: 'Rafael Alves',
        text: 'Show. Assim que subir o fix eu aviso aqui',
        time: '09:57',
        wide: true,
      },
      { side: 'out', text: 'Combinado, obrigado pessoal', time: '10:03' },
    ],
  },
  {
    id: 'carlos',
    type: 'private',
    initials: 'CE',
    name: 'Carlos Eduardo',
    subtitle: 'visto por ultimo ha 18 min',
    preview: 'Bora marcar aquele cafe',
    time: '12:10',
    messages: [{ side: 'in', text: 'Bora marcar aquele cafe', time: '12:10' }],
  },
  {
    id: 'familia',
    type: 'group',
    initials: 'FM',
    name: 'Familia',
    subtitle: '4 membros · Voce, Mae, Joao, +1',
    preview: 'Mae: nao esquecam do almoco',
    time: 'Ontem',
    messages: [{ side: 'in', author: 'Mae', text: 'Nao esquecam do almoco', time: 'Ontem' }],
  },
  {
    id: 'mariana',
    type: 'private',
    initials: 'MS',
    name: 'Mariana Silva',
    subtitle: 'offline',
    preview: 'valeu pela ajuda de ontem',
    time: 'Ontem',
    messages: [{ side: 'in', text: 'valeu pela ajuda de ontem', time: 'Ontem' }],
  },
  {
    id: 'joao',
    type: 'private',
    initials: 'JP',
    name: 'Joao Pedro',
    subtitle: 'visto por ultimo ontem',
    preview: 'Combinado entao, te encontro amanha as...',
    time: 'Seg',
    messages: [{ side: 'in', text: 'Combinado entao, te encontro amanha as 9', time: 'Seg' }],
  },
]
