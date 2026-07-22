defmodule Api.Providers.Hash.Behaviour do
  @callback verify_password(String.t(), String.t()) :: boolean()
  @callback hash_password(String.t()) :: String.t()
end
