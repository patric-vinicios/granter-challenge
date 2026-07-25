defmodule ApiWeb.Contacts.ContactJSON do
  @moduledoc """
  The contact shape: a row id and the user it lists.

  The contacted user is embedded through `ApiWeb.Accounts.UserJSON.data/1` rather than
  flattened, so the client reuses one type across contacts, message senders and
  group members, and a field later added to the user object reaches this
  endpoint without a change here.

  Note that `id` is the *contact row's* id — the value a delete addresses — and
  `user.id` is the contacted user's, which is what later features take as a
  conversation target or a group member.
  """

  alias Api.Contacts.Contact
  alias ApiWeb.Accounts.UserJSON

  @doc "Renders one contact under a `:contact` key, for the create response."
  @spec show(%{contact: Contact.t()}) :: map()
  def show(%{contact: contact}), do: %{contact: data(contact)}

  @doc """
  One page of the list: the entries, the cursor that opens the next page and
  whether there is one. Shaped exactly as the conversation inbox's page is, so a
  client pages both lists with one piece of code.
  """
  @spec index(%{
          contacts: [Contact.t()],
          next_cursor: String.t() | nil,
          has_more: boolean()
        }) :: map()
  def index(%{contacts: contacts, next_cursor: next_cursor, has_more: has_more}) do
    %{
      contacts: Enum.map(contacts, &data/1),
      next_cursor: next_cursor,
      has_more: has_more
    }
  end

  @doc "The contact object: the row `id` and the embedded contacted `user`."
  @spec data(Contact.t()) :: map()
  def data(%Contact{} = contact) do
    %{
      id: contact.id,
      user: UserJSON.data(contact.user)
    }
  end
end
