if Code.ensure_loaded?(Plug) do
  defmodule Unleash.Plug do
    @moduledoc """
    An extra fancy `Plug` and utility functions to help when developing `Plug`
    or `Phoenix`-based applications. It automatically puts together a
    `t:Unleash.context/0` under the `Plug.Conn`'s `Plug.assigns/0`.

    To use, call `plug Unleash.Plug` in your plug pipeline. It depends on the
    session, and requires being after `:fetch_session` to work. It accepts the
    following options:

    * `:user_id`: The key under which the user's ID is found in the session.
    * `:session_id`: The key under wwhich the session ID is found in the
      session.

    After which, `enabled?/3` is usable.

    If you are _also_ using `PhoenixGon` in your application, you can call
    `put_feature/3` to put a specific feature flag into the gon object for
    using on the client side.

    """

    import Plug.Conn
    @behaviour Plug

    @default_opts [
      user_id: :user_id,
      session_id: :session_id
    ]

    @doc false
    def init(opts) when is_list(opts), do: Keyword.merge(@default_opts, opts)

    def init(_), do: @default_opts

    @doc false
    def call(conn, opts) do
      context = construct_context(conn, opts)
      assign(conn, :unleash_context, context)
    end

    @doc """
    Given a `t:Plug.Conn/0`, a feature, and (optionally) a boolean, return
    whether or not a feature is enabled. This requires this plug to be a part
    of the plug pipeline, as it will construct an `t:Unleash.context()/0` out
    of the session.

    ## Examples

        iex> Unleash.Plug.enabled?(conn, :test)
        false

        iex> Unleash.Plug.enabled?(conn, :test, true)
        true
    """
    @spec enabled?(Plug.Conn.t(), String.t() | atom(), boolean()) :: boolean()
    def enabled?(%Plug.Conn{assigns: assigns}, feature, default \\ false) do
      context = Map.get(assigns, :unleash_context, %{})
      Unleash.enabled?(feature, context, default)
    end

    if Code.ensure_loaded?(PhoenixGon) do
      alias PhoenixGon.Controller

      @doc """
      If you are using `PhoenixGon`, you can call this to put a feature in the
      gon object to be used on the client side. It will be available under
      `window.Gon.getAssets('features')`. It listens to the options that
      are configured by `PhoenixGon.Pipeline`.

      ## Examples

          iex> Unleash.Plug.put_feature(conn, :test)
          %Plug.Conn{}

          iex> Unleash.Plug.enabled?(conn, :test, true)
          %Plug.Conn{}
      """
      @spec put_feature(Plug.Conn.t(), String.t() | atom(), boolean()) :: Plug.Conn.t()
      def put_feature(conn, feature, default \\ false) do
        conn
        |> Controller.get_gon(:features)
        |> case do
          features when is_map(features) ->
            Controller.update_gon(
              conn,
              :features,
              Map.put(features, feature, enabled?(conn, feature, default))
            )

          _ ->
            Controller.put_gon(
              conn,
              :features,
              Map.new([{feature, enabled?(conn, feature, default)}])
            )
        end
      end
    end

    defp construct_context(conn, opts) do
      opts
      |> Enum.map(fn {k, v} ->
        {k, get_session(conn, v)}
      end)
      |> Enum.concat(remote_address: to_string(:inet.ntoa(conn.remote_ip)))
      |> Enum.into(%{})
    end
  end
end
