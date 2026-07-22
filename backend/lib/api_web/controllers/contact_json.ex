defmodule ApiWeb.ContactJSON do
  @moduledoc """
  The contact shape: a row id and the user it lists.

  The contacted user is embedded through `ApiWeb.UserJSON.data/1` rather than
  flattened, so the client reuses one type across contacts, message senders and
  group members, and a field later added to the user object reaches this
  endpoint without a change here.

  Note that `id` is the *contact row's* id — the value a delete addresses — and
  `user.id` is the contacted user's, which is what later features take as a
  conversation target or a group member.
  """

  alias Api.Contacts.Contact
  alias ApiWeb.UserJSON

  def show(%{contact: contact}), do: %{contact: data(contact)}

  def index(%{contacts: contacts}), do: %{contacts: Enum.map(contacts, &data/1)}

  def data(%Contact{} = contact) do
    %{
      id: contact.id,
      user: UserJSON.data(contact.user)
    }
  end
end
