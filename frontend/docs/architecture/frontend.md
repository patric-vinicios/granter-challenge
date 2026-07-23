# Arquitetura do frontend

## Objetivo

Organizar o frontend como uma aplicação Vue 3 modular, orientada a features e implementada em
vertical slices. Cada entrega deve atravessar contrato, estado, interação e testes sem espalhar a
mesma feature por diretórios técnicos sem um proprietário claro.

A arquitetura deve suportar:

- autenticação compartilhada entre HTTP e WebSocket;
- contatos, conversas privadas e grupos;
- histórico com paginação por cursor;
- mensagens em tempo real com reconciliação otimista;
- inbox ordenada, unread, busca e presença;
- implementação incremental seguindo as dependências do PRD;
- testes rápidos sem rede ou backend reais.

Esta não é uma arquitetura de camadas cerimoniais. Interfaces, stores, composables e componentes
só devem existir quando houver comportamento real que justifique sua criação.

## Fontes de verdade

Use esta precedência ao implementar uma feature:

1. O PRD e a especificação da feature definem intenção e critérios de aceite.
2. Router, controllers, renderizadores JSON, channels e testes do backend definem o contrato
   disponível para integração.
3. O comportamento frontend existente define compatibilidade que deve ser preservada.
4. Este documento define a organização e a direção das dependências no frontend.

Nunca invente endpoint, campo, código de erro, tópico ou evento para resolver uma divergência. Se o
contrato documentado não estiver implementado, separe o trabalho que continua verdadeiro e registre
explicitamente o que permanece sem integração.

## Estilo arquitetural

Adote uma arquitetura modular por feature, com vertical slices e infraestrutura compartilhada nas
fronteiras de entrada e saída.

```text
src/
├── app/                    # bootstrap e composição global
├── domain/                 # tipos puros compartilhados entre features
├── shared/
│   ├── api/                # cliente HTTP e normalização de erros
│   ├── realtime/           # Phoenix Socket e lifecycle da conexão
│   ├── config/             # leitura centralizada de configuração
│   ├── storage/            # persistência da sessão
│   ├── ui/                 # elementos compartilhados com contrato real
│   └── utils/              # funções puras reutilizadas
├── features/
│   ├── auth/
│   ├── contacts/
│   ├── conversations/
│   ├── messaging/
│   ├── search/
│   └── presence/
├── views/                  # composição das rotas
└── router/                 # rotas e guards
```

Essa estrutura é um destino incremental. Não mova o protótipo inteiro antes de implementar a
primeira feature. Crie um módulo quando a vertical slice correspondente começar e migre somente o
código necessário para ela.

## Direção das dependências

```text
main e router
      ↓
    views
      ↓
   features
    ↙     ↘
 domain   shared
```

Regras obrigatórias:

- `app`, router e views podem compor features.
- Features podem depender de `domain` e `shared`.
- `domain` contém apenas tipos e funções puras; não importa Vue, Pinia ou transporte.
- `shared` não importa features, views ou stores de domínio.
- Views não chamam `fetch`, não criam socket e não interpretam payload externo.
- Módulos de API não importam componentes, router ou stores.
- Stores não acessam DOM e não executam navegação.
- Uma feature não importa arquivos internos de outra feature. Compartilhe tipos puros pelo domínio
  ou componha as duas features na view.
- Dependência circular é falha arquitetural, não motivo para criar um singleton global.

## Anatomia de uma feature

Uma feature começa pequena e cresce sob demanda:

```text
features/auth/
├── auth.api.ts             # operações HTTP da feature
├── auth.contracts.ts       # schemas, decoders e tipos de transporte
├── auth.store.ts           # apenas se o estado for compartilhado
├── auth.spec.ts
├── components/             # UI exclusiva da feature
└── views/                  # opcional quando a rota pertence à feature
```

Não crie todos esses arquivos por padrão:

- estado usado por um único componente permanece local;
- uma chamada simples pode ficar em um único módulo da feature;
- crie composable quando existir lifecycle, efeito reutilizável ou coordenação entre fontes;
- crie store quando o estado atravessar componentes, rotas ou eventos em tempo real;
- extraia componente quando ele possuir responsabilidade e contrato próprios;
- tipos usados apenas por uma feature permanecem na feature;
- mova um tipo para `domain` somente quando duas ou mais features o consumirem.

## Mapeamento das features

| Módulo | Responsabilidade | PRD |
| --- | --- | --- |
| `auth` | sessão, identidade, bootstrap e guards | F02 |
| `contacts` | lista, inclusão, remoção e seleção de contatos | F03 |
| `conversations` | conversa privada, grupos, detalhes e inbox | F04, F05, F08 |
| `messaging` | histórico, cursor, envio e eventos de mensagem | F06, F07 |
| `search` | filtro da inbox e busca dentro da conversa | F09 |
| `presence` | estado online e último acesso | F10 |
| `shared` | HTTP, socket, configuração, erros e sessão persistida | F01 |

F11 fornece dados demonstrativos consumidos pelos módulos existentes e não exige uma feature
frontend própria. F12 documenta os contratos utilizados pelo frontend.

Implemente na ordem das dependências do produto:

```text
shared → auth → contacts → conversations → messaging
                                  ↘          ↙
                                    search
auth + messaging → presence
```

## Estado e ownership

O backend é a fonte de verdade dos dados persistidos. Pinia mantém sessão, cache e coordenação do
cliente; não replica regras de autorização pertencentes ao servidor.

| Estado | Proprietário recomendado | Motivo |
| --- | --- | --- |
| usuário, token e bootstrap | `authStore` | usado por rotas, HTTP e socket |
| contatos | `contactsStore` | reutilizado em contatos, conversa privada e grupos |
| resumos, ordem e unread | `inboxStore` | atualizado por REST e tópico pessoal |
| histórico por conversa | `messagesStore` | cursor, deduplicação e reconciliação |
| presença da conversa aberta | composable da feature | lifecycle ligado à rota atual |
| formulário, modal e draft | componente ou composable local | não precisa ser global |
| resultados de busca | composable local | pertence à interação aberta |

Diretrizes de estado:

- normalize coleções com `byId` e listas de ids quando houver atualização incremental;
- derive ordenação, agrupamento e rótulos com `computed`;
- não copie dados derivados para outro `ref`;
- não use `watch` para manter duas cópias sincronizadas;
- mutations compartilhadas passam por actions;
- use `storeToRefs` ao desestruturar estado ou getters;
- mantenha navegação em views ou guards, fora das stores.

## Fronteira HTTP

`src/shared/api/` deve fornecer somente capacidades comuns:

- resolução de `VITE_API_URL`;
- serialização e leitura de JSON;
- headers comuns;
- suporte a `AbortSignal`;
- normalização do envelope `{ errors: { code, detail, fields? } }`;
- erro distinto para falha de rede, resposta inválida e erro da API.

Cada feature declara seus endpoints e contratos no próprio módulo. Funções autenticadas recebem o
token explicitamente; o cliente compartilhado não importa a `authStore`.

Payload externo entra como `unknown`. Valide os campos usados para estado ou controle de fluxo antes
de transformá-lo em um tipo confiável. Tipos TypeScript não substituem validação runtime.

Não duplique mensagens do servidor dentro de componentes. A camada de apresentação recebe erros já
normalizados e decide apenas como exibi-los.

## Fronteira WebSocket

`src/shared/realtime/` possui a criação e a conexão do Phoenix Socket. Ele recebe o token no momento
da conexão e não conhece stores ou componentes.

Composables das features controlam tópicos e eventos:

- a sessão autenticada abre uma conexão;
- a inbox entra em `user:<user_id>`;
- a conversa aberta entra em `conversation:<conversation_id>`;
- desmontagem ou troca de rota encerra o channel anterior e remove handlers;
- logout encerra todos os channels e a conexão;
- reconnect dispara recuperação por REST porque o channel não faz replay.

Stores recebem dados já decodificados por callbacks ou actions. O módulo de socket nunca altera
estado de UI diretamente.

## REST e tempo real

REST e WebSocket têm papéis diferentes:

```text
REST
├── bootstrap da sessão
├── lista inicial da inbox
├── detalhes e histórico
├── paginação por cursor
└── recuperação depois de reconnect

WebSocket
├── mensagens novas
├── acknowledgements de envio
├── atualizações incrementais da inbox
├── revogação de membership
└── presença
```

Regras de reconciliação:

- histórico REST chega em ordem cronológica e é armazenado sem reordenar pelo cliente;
- páginas antigas são inseridas antes das mensagens existentes;
- mensagens em tempo real são deduplicadas pelo id do servidor;
- envio otimista usa `client_ref` e um estado transitório;
- o acknowledgement substitui a mensagem transitória pelo registro persistido;
- o remetente não adiciona novamente o mesmo registro pelo broadcast;
- falha de envio remove ou marca a mensagem transitória e preserva o texto para nova tentativa;
- após reconnect, refaça histórico e inbox para preencher eventos perdidos;
- o tópico pessoal atualiza resumo, unread e posição da conversa sem entrar em todos os tópicos.

## Rotas e composição

Views são composition roots de UI:

- leem parâmetros da rota;
- iniciam stores e composables necessários;
- coordenam navegação após resultados de negócio;
- compõem estados de carregamento, vazio, sucesso e falha;
- passam dados e callbacks tipados para componentes.

Guards dependem apenas do estado público da sessão. Preserve um destino de retorno seguro ao mandar
um usuário não autenticado para login. Nunca confie em uma URL externa como destino de navegação.

## Segurança no cliente

- Não renderize conteúdo de mensagem com `v-html`.
- Não grave token, senha ou payload sensível em logs e fixtures.
- Centralize a persistência da sessão em `shared/storage`.
- Limpe sessão, socket e caches autenticados no logout ou token expirado.
- Trate 401 por código: `token_expired` e `unauthenticated` encerram a sessão; credenciais inválidas
  pertencem ao formulário de login.
- Não replique autorização de contatos ou membership como garantia do cliente. A UI pode ocultar uma
  ação, mas o servidor continua responsável por autorizá-la.
- Escape é o comportamento padrão do template Vue; não contorne essa proteção para mensagens.

## Estratégia de testes

Coloque testes próximos do comportamento que protegem:

- contratos da feature: método, caminho, headers, corpo, resposta e erro normalizado;
- store/composable: transições de estado, deduplicação, paginação e cleanup;
- componente: interação acessível e estados percebidos pelo usuário;
- router: guards e parâmetros com `createMemoryHistory`;
- socket: entrada, saída, acknowledgement e reconnect com transporte falso.

Regras:

- cada teste cria Pinia e router próprios;
- rede e WebSocket reais permanecem bloqueados;
- não selecione classes Tailwind;
- não use snapshots extensos;
- restaure timers e mocks;
- não use espera arbitrária para sincronizar testes;
- fake de transporte prova integração do cliente, não disponibilidade real do backend.

Cada vertical slice deve mapear critérios de aceite para testes ou para uma verificação manual
explícita. Antes de concluir, execute teste direcionado, testes relacionados e `npm run verify`.

## Evolução incremental do protótipo

Evite uma migração estrutural isolada. Para cada feature:

1. leia PRD, pasta da feature e contrato executável;
2. escreva o feature brief;
3. crie a pasta da feature e somente a infraestrutura consumida por ela;
4. mova da view apenas o estado e o comportamento pertencentes à feature;
5. preserve markup e aparência que não fazem parte da mudança;
6. substitua mocks apenas quando a vertical slice estiver testada;
7. execute o harness e confira o diff por mudanças não relacionadas.

O `InboxView.vue` atual pode ser decomposto enquanto F03-F09 forem implementadas. Não o divida em
componentes vazios ou wrappers apenas para reduzir o tamanho do arquivo.

## Anti-padrões

Não introduza:

- uma store global única para toda a aplicação;
- chamadas HTTP ou socket dentro de templates e componentes de apresentação;
- um diretório genérico de serviços sem ownership por feature;
- DTOs duplicados em várias camadas;
- eventos globais sem contrato e cleanup;
- watchers usados como mecanismo principal de derivação;
- abstrações de repository ou use case para chamadas triviais sem segundo consumidor;
- refatoração de estrutura antes da primeira vertical slice;
- comportamento otimista sem reconciliação por `client_ref` e id persistido;
- confiança em testes com fakes como prova de integração real.

## Checklist de decisão

Antes de criar um arquivo, responda:

1. Qual feature é proprietária deste comportamento?
2. Existe consumidor real agora?
3. O estado precisa atravessar componente ou rota?
4. O efeito possui lifecycle ou cleanup?
5. O tipo é compartilhado por mais de uma feature?
6. O dado veio de uma fronteira externa e foi validado?
7. A dependência respeita a direção definida neste documento?
8. O comportamento possui teste observável?

Se as respostas não justificarem uma nova camada, mantenha a solução no menor escopo possível.
