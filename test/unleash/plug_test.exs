defmodule Unleash.PlugTest do
  use ExUnit.Case
  use Plug.Test
  use ExUnitProperties

  alias PhoenixGon.Controller
  alias PhoenixGon.Pipeline
  alias Unleash.Plug

  @opts Plug.init([])
  @gon_opts Pipeline.init([])

  setup do
    stop_supervised(Unleash.Repo)

    state =
      Unleash.Features.from_map!(%{
        "version" => 1,
        "features" => [
          %{
            "name" => "test1",
            "description" => "Enabled toggle",
            "enabled" => true,
            "strategies" => [
              %{
                "name" => "userWithId",
                "parameters" => %{
                  "userIds" => "1"
                }
              }
            ]
          },
          %{
            "name" => "test2",
            "description" => "Enabled toggle",
            "enabled" => true,
            "strategies" => [
              %{
                "name" => "gradualRolloutSessionId",
                "parameters" => %{
                  "percentage" => "50",
                  "groupId" => "AB12A"
                }
              }
            ]
          },
          %{
            "name" => "test3",
            "description" => "Enabled toggle",
            "enabled" => true,
            "strategies" => [
              %{
                "name" => "remoteAddress",
                "parameters" => %{
                  "IPs" => "127.0.0.1"
                }
              }
            ]
          }
        ]
      })

    {:ok, _pid} = start_supervised({Unleash.Repo, state})

    Application.put_env(:unleash, Unleash, disable_client: false)
    :ok
  end

  describe "call/2" do
    property "puts an unleash context in assigns" do
      check all session_id <- binary(min_length: 1),
                user_id <- binary(min_length: 1) do
        conn = conn(:get, "/")

        conn =
          conn
          |> init_test_session(%{user_id: user_id, session_id: session_id})
          |> Plug.call(@opts)

        assert %{
                 user_id: user_id,
                 session_id: session_id,
                 remote_address: "127.0.0.1"
               } == conn.assigns[:unleash_context]
      end
    end

    property "follows options passed into the plug" do
      check all session <- atom(:alphanumeric),
                user <- atom(:alphanumeric),
                opts = Plug.init(user_id: user, session_id: session),
                session_id <- binary(min_length: 1),
                user_id <- binary(min_length: 1) do
        conn = conn(:get, "/")

        conn =
          conn
          |> init_test_session(%{user => user_id, session => session_id})
          |> Plug.call(opts)

        assert %{
                 user_id: user_id,
                 session_id: session_id,
                 remote_address: "127.0.0.1"
               } == conn.assigns[:unleash_context]
      end
    end
  end

  describe "enabled?/3" do
    test "it should pass a constructed context through to `Unleash.enabled?/3`" do
      conn = conn(:get, "/")

      conn =
        conn
        |> init_test_session(%{user_id: 1, session_id: 122})
        |> Plug.call(@opts)

      assert Plug.enabled?(conn, :test1, false)
      assert Plug.enabled?(conn, :test2, false)
      assert Plug.enabled?(conn, :test3, false)
    end
  end

  describe "put_feature/3" do
    test "it should put a feature in the Gon object" do
      conn = conn(:get, "/")

      conn =
        conn
        |> init_test_session(%{user_id: 1, session_id: 122})
        |> Pipeline.call(@gon_opts)
        |> Plug.call(@opts)
        |> Plug.put_feature(:test1, false)

      assert %{test1: true} = Controller.get_gon(conn, :features)
    end

    test "it should append a feature in the Gon object" do
      conn = conn(:get, "/")

      conn =
        conn
        |> init_test_session(%{user_id: 1, session_id: 122})
        |> Pipeline.call(@gon_opts)
        |> Plug.call(@opts)
        |> Plug.put_feature(:test1, false)
        |> Plug.put_feature(:test2, false)

      assert %{test1: true, test2: true} = Controller.get_gon(conn, :features)
    end
  end
end
