defmodule Api.Seeds.Dataset do
  @moduledoc """
  The demo content as data, not as code.

  Seven users, the mesh flag, and six conversations — four private and two
  groups — each carrying its ordered transcript and how many trailing messages
  start unread for the primary account. Nothing here executes: it is a map, so
  every count an acceptance criterion asserts can be read off it, and the
  interpreter over it is the only thing that touches a database.

  A message is `{sender_username, body, {days_ago, minutes_back}}`. The time is
  an offset backwards from a single anchor taken once at run time, never a
  wall-clock value, so no seeded message can be dated in the future at any hour
  and "today, yesterday and the previous week" is true whenever the script runs.
  Within a conversation the offsets strictly increase in real time — each entry
  resolves later than the one before it — which the interpreter and the dataset
  tests both rely on.

  The contact mesh is not listed: every ordered pair of distinct users is a
  contact, derived from `:users`, so any seeded account can open a conversation
  with any other on first login.
  """

  @password "senha123"
  @primary "demo"

  @users [
    %{username: "demo", name: "Usuário Demo"},
    %{username: "anabeatriz", name: "Ana Beatriz"},
    %{username: "carlosedu", name: "Carlos Eduardo"},
    %{username: "joaopedro", name: "João Pedro"},
    %{username: "leticiam", name: "Letícia Moraes"},
    %{username: "marianas", name: "Mariana Silva"},
    %{username: "rafaelalves", name: "Rafael Alves"}
  ]

  @ana_beatriz %{
    kind: :private,
    with: "anabeatriz",
    unread: 0,
    messages: [
      {"anabeatriz", "Oi! Tudo bem? Queria alinhar o cronograma do projeto com você", {8, 600}},
      {"demo", "Oi Ana! Tudo ótimo. Podemos sim, me manda os detalhes", {8, 585}},
      {"anabeatriz", "Perfeito, vou preparar um resumo e te envio ainda hoje", {8, 570}},
      {"demo", "Recebi o resumo, ficou muito claro. Obrigado!", {7, 620}},
      {"anabeatriz", "Que bom! Fico à disposição para ajustar o que precisar", {7, 600}},
      {"demo", "Vou revisar com o time e te dou um retorno", {7, 540}},
      {"anabeatriz", "Bom dia! Conseguiu revisar a proposta?", {1, 700}},
      {"demo", "Bom dia! Vi sim, ficou ótima", {1, 685}},
      {"anabeatriz", "Fico feliz que gostou 😊", {1, 670}},
      {"demo", "Vamos fechar os próximos passos amanhã?", {1, 300}},
      {"anabeatriz", "Claro! Que horas fica bom pra você?", {0, 240}},
      {"demo", "Depois do almoço, umas 14h", {0, 180}},
      {"anabeatriz", "Fechado, te mando o link da call", {0, 120}},
      {"demo", "Perfeito, até lá!", {0, 90}}
    ]
  }

  @carlos_eduardo %{
    kind: :private,
    with: "carlosedu",
    unread: 2,
    messages: [
      {"carlosedu", "E aí, viu o resultado dos testes?", {1, 800}},
      {"demo", "Vi! Passou tudo, só faltou o de integração", {1, 785}},
      {"carlosedu", "Verdade, vou rodar de novo aqui", {1, 770}},
      {"demo", "Beleza, me avisa quando terminar", {1, 500}},
      {"carlosedu", "Rodou! Tá tudo verde agora", {1, 300}},
      {"demo", "Show, pode subir então", {1, 280}},
      {"carlosedu", "Subi a versão nova pra staging", {0, 400}},
      {"demo", "Ótimo, vou validar aqui", {0, 380}},
      {"carlosedu", "Achei um bug pequeno no login, já corrigi", {0, 200}},
      {"carlosedu", "Pode revisar quando puder?", {0, 150}}
    ]
  }

  @mariana_silva %{
    kind: :private,
    with: "marianas",
    unread: 0,
    messages: [
      {"marianas", "Oi! Vamos marcar aquele café?", {1, 600}},
      {"demo", "Vamos sim! Quinta te serve?", {1, 585}},
      {"marianas", "Quinta é perfeito 😄", {1, 570}},
      {"demo", "Combinado então", {1, 200}},
      {"marianas", "Ah, muda pra sexta? Surgiu uma reunião", {0, 300}},
      {"demo", "Sem problema, sexta então", {0, 280}},
      {"marianas", "Valeu! Te espero às 15h", {0, 120}},
      {"demo", "Até lá!", {0, 100}}
    ]
  }

  @joao_pedro %{
    kind: :private,
    with: "joaopedro",
    unread: 0,
    messages: [
      {"joaopedro", "Fala! Fechou o orçamento do trimestre?", {8, 700}},
      {"demo", "Fechei ontem, dentro do previsto", {8, 680}},
      {"joaopedro", "Maravilha, parabéns!", {8, 500}},
      {"demo", "Obrigado! Trabalho em equipe", {8, 480}},
      {"joaopedro", "Precisa de ajuda com o relatório?", {7, 900}},
      {"demo", "Se puder revisar a parte financeira, ajuda muito", {7, 880}},
      {"joaopedro", "Pode deixar, reviso hoje à tarde", {7, 600}},
      {"demo", "Valeu, João!", {7, 300}}
    ]
  }

  @time_de_produto %{
    kind: :group,
    name: "Time de Produto",
    creator: "demo",
    members: ["demo", "rafaelalves", "anabeatriz", "carlosedu", "leticiam"],
    unread: 3,
    messages: [
      {"rafaelalves", "Pessoal, subi a build de staging", {7, 800}},
      {"anabeatriz", "Vou testar o fluxo de cadastro", {7, 780}},
      {"demo", "Ótimo, obrigado pessoal", {7, 600}},
      {"carlosedu", "Achei um problema no cronograma da sprint", {7, 400}},
      {"leticiam", "Atualizei o board com as tarefas novas", {1, 900}},
      {"rafaelalves", "Valeu Letícia!", {1, 880}},
      {"demo", "Bom trabalho time 👏", {1, 700}},
      {"anabeatriz", "Amanhã tem review, não esqueçam", {1, 500}},
      {"carlosedu", "Anotado", {1, 480}},
      {"demo", "Bom dia! Alguém pode revisar meu PR?", {0, 400}},
      {"rafaelalves", "Eu reviso", {0, 360}},
      {"leticiam", "Subi os novos protótipos no Figma", {0, 200}},
      {"carlosedu", "Ficaram ótimos!", {0, 160}},
      {"rafaelalves", "Concordo, mandaram bem", {0, 132}}
    ]
  }

  @familia %{
    kind: :group,
    name: "Família",
    creator: "demo",
    members: ["demo", "marianas", "joaopedro", "leticiam"],
    unread: 0,
    messages: [
      {"marianas", "Bom dia família! Como estão?", {1, 720}},
      {"demo", "Tudo bem por aqui 😄", {1, 700}},
      {"joaopedro", "Tudo ótimo!", {1, 680}},
      {"leticiam", "Saudades de vocês ❤️", {1, 660}},
      {"marianas", "Vamos marcar o almoço de domingo?", {1, 400}},
      {"demo", "Bora! Na casa da vó?", {1, 380}},
      {"joaopedro", "Perfeito, levo a sobremesa", {1, 200}},
      {"leticiam", "Combinado! Até domingo", {1, 180}}
    ]
  }

  @conversations [
    @ana_beatriz,
    @carlos_eduardo,
    @mariana_silva,
    @joao_pedro,
    @time_de_produto,
    @familia
  ]

  @dataset %{
    password: @password,
    primary: @primary,
    users: @users,
    conversations: @conversations
  }

  @doc """
  The whole dataset as a map: `:password`, `:primary`, `:users` and
  `:conversations`. Pure data — no database access, no context aliased.
  """
  def all, do: @dataset
end
