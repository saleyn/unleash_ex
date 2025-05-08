defmodule UnleashTest do
  use ExUnit.Case
  import Mox

  describe "enabled?/2" do
    setup :start_repo

    test "should send an empty context" do
      Application.delete_env(:unleash, :disable_client)
      refute Unleash.enabled?(:test1, true)
    end

    test "should emit evaluation series on stop when applicable" do
      Application.delete_env(:unleash, :disable_client)

      attach_telemetry_event([:unleash, :feature, :enabled?, :stop])

      refute Unleash.enabled?(:test1, true)

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata.feature === :test1
      assert metadata.result === false
      assert metadata.reason === :strategy_evaluations
      assert metadata.feature_enabled
      assert [{"userWithId", false}] = metadata.strategy_evaluations

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])
    end

    test "should emit reason for non existent feature" do
      Application.delete_env(:unleash, :disable_client)

      attach_telemetry_event([:unleash, :feature, :enabled?, :stop])

      refute Unleash.enabled?(:test_none_of_this, false)

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata.feature === :test_none_of_this
      assert metadata.result === false
      assert metadata.reason === :feature_not_found

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])
    end
  end

  describe "is_enabled?" do
    setup :start_repo

    test "should call enabled" do
      assert Unleash.is_enabled?(:test1, true) == Unleash.enabled?(:test1, true)

      assert Unleash.is_enabled?(:test1, %{user_id: 1}, true) ==
               Unleash.enabled?(:test1, %{user_id: 1}, true)

      assert Unleash.is_enabled?(:test1) ==
               Unleash.enabled?(:test1)
    end
  end

  describe "enabled?/3" do
    setup do
      stop_supervised(Unleash.Repo)
      saved = Application.get_env(:unleash, :disable_client)
      Application.put_env(:unleash, :disable_client, true)

      on_exit(fn ->
        Application.put_env(:unleash, :disable_client, saved)
      end)

      :ok
    end

    test "should return the default if the client is disabled" do
      assert true == Unleash.enabled?(:test, %{}, true)
      assert false == Unleash.enabled?(:test, %{}, false)
    end

    test "should emit telemetry on start" do
      attach_telemetry_event([:unleash, :feature, :enabled?, :start])

      Unleash.enabled?(:test1)

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata.feature === :test1

      assert is_number(measurements[:system_time])
      assert is_number(measurements[:monotonic_time])
    end

    test "should emit telemetry with result on stop" do
      attach_telemetry_event([:unleash, :feature, :enabled?, :stop])

      Unleash.enabled?(:test1)

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata.feature === :test1
      assert metadata.result === false
      assert metadata.reason === :disabled_client

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])
    end
  end

  describe "get_variant/3" do
    setup do
      stop_supervised(Unleash.Repo)
      saved = Application.get_env(:unleash, :disable_client)
      Application.put_env(:unleash, :disable_client, true)

      on_exit(fn ->
        Application.put_env(:unleash, :disable_client, saved)
      end)

      :ok
    end

    test "should return the default if the client is disabled" do
      assert true == Unleash.get_variant(:variant, %{}, true)
      assert false == Unleash.get_variant(:variant, %{}, false)
    end
  end

  describe "start/1" do
    test "it should listen to configuration when starting the supervisor tree" do
      Unleash.ClientMock
      |> expect(:register_client, fn -> {:ok, %{}} end)
      |> stub(:features, fn _ -> {:ok, %{etag: "test_etag", features: %Unleash.Features{}}} end)
      |> stub(:metrics, fn _ -> {:ok, %SimpleHttp.Response{}} end)

      Application.put_env(:unleash, :client, Unleash.ClientMock)
      Application.put_env(:unleash, :disable_metrics, false)
      Application.put_env(:unleash, :disable_client, false)
      {:ok, pid} = Unleash.start(:normal, [])
      children = Supervisor.which_children(pid)

      assert Enum.any?(children, &Kernel.match?({Unleash.Repo, _, _, _}, &1))
      assert Enum.any?(children, &Kernel.match?({Unleash.Metrics, _, _, _}, &1))
    end

    test "it shouldn't start the metrics server if disabled" do
      Unleash.ClientMock
      |> expect(:register_client, fn -> {:ok, %{}} end)
      |> stub(:features, fn _ -> {:ok, %{etag: "test_etag", features: %Unleash.Features{}}} end)

      Application.put_env(:unleash, :client, Unleash.ClientMock)
      Application.put_env(:unleash, :disable_metrics, true)
      {:ok, pid} = Unleash.start(:normal, [])

      children = Supervisor.which_children(pid)

      assert Enum.any?(children, &Kernel.match?({Unleash.Repo, _, _, _}, &1))
      refute Enum.any?(children, &Kernel.match?({Unleash.Metrics, _, _, _}, &1))
    end

    test "it shouldn't start anything if the client is disabled" do
      Application.put_env(:unleash, :client, Unleash.ClientMock)
      Application.put_env(:unleash, :disable_client, true)
      {:ok, pid} = Unleash.start(:normal, [])

      children = Supervisor.which_children(pid)

      refute Enum.any?(children, &Kernel.match?({Unleash.Repo, _, _, _}, &1))
      refute Enum.any?(children, &Kernel.match?({Unleash.Metrics, _, _, _}, &1))
    end
  end

  defp start_repo(_) do
    stop_supervised(Unleash.Repo)

    state = Unleash.Features.from_map!(state())

    {:ok, _pid} = start_supervised({Unleash.Repo, state})
    :ok
  end

  defp attach_telemetry_event(event) do
    test_pid = self()

    :telemetry.attach(
      make_ref(),
      event,
      fn
        ^event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_measurements, measurements})
          send(test_pid, {:telemetry_metadata, metadata})
      end,
      []
    )
  end

  defp state,
    do: %{
      "version" => 2,
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
        },
        %{
          "name" => "variant",
          "description" => "variant",
          "enabled" => true,
          "strategies" => [
            %{
              "name" => "default",
              "parameters" => %{}
            }
          ],
          "variants" => [
            %{
              "name" => "variant1",
              "weight" => 100,
              "payload" => %{"type" => "string", "value" => "val1"}
            }
          ]
        }
      ]
    }
end
