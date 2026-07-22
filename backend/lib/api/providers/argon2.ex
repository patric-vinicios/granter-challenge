defmodule Api.Providers.Hash.Argon2 do
  @behaviour Api.Providers.Hash.Behaviour

  def hash_password(string), do: Argon2.hash_pwd_salt(string)

  def verify_password(plain_password, hashed_password), do:
    Argon2.verify_pass(plain_password, hashed_password)
end
