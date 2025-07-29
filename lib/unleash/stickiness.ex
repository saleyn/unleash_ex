defmodule Unleash.Stickiness do
  def get_seed(sticky_field, ctx)
      when sticky_field == "default"
      when sticky_field == "" do
    stickiness_value_(ctx)
  end

  def get_seed(sticky_field, ctx) do
    sticky_context_field = sticky_context_field(sticky_field)

    case Map.get(ctx, sticky_context_field, "") do
      "" ->
        stickiness_value_(ctx)

      value ->
        value
    end
  end

  def sticky_context_field(sticky_field) do
    :unleash
    |> Application.get_env(:sticky_fields, %{})
    |> Map.get(sticky_field, sticky_field)
  end

  defp stickiness_value_(%{user_id: user_id}) when user_id != "" do
    user_id
  end

  defp stickiness_value_(%{session_id: session_id}) when session_id != "" do
    session_id
  end

  defp stickiness_value_(%{remote_address: remote_address}) when remote_address != "" do
    remote_address
  end

  defp stickiness_value_(_ctx), do: random()

  defp random,
    do: Integer.to_string(round(:rand.uniform() * 100) + 1)
end
