defmodule UnleashTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  import Mox

  describe "features/0" do
    @tag :capture_log
    test "should warn if unexpected status code returned" do
      MojitoMock
      |> stub(:post, fn _, _, _ -> {:ok, %Mojito.Response{}} end)
      |> expect(:get, fn _url, _headers ->
        {:ok, %Mojito.Response{status_code: 502}}
      end)

      Application.put_env(:unleash, Unleash, http_client: MojitoMock)

      assert capture_log(fn ->
               Unleash.Client.features()
             end) =~ ~r/Unexpected response.+Using cached features/
    end
  end

  describe "enabled?/2" do
    setup :start_repo

    @tag capture_log: true
    test "should send an empty context" do
      Application.put_env(:unleash, Unleash, [])
      refute Unleash.enabled?(:test1, true)
    end

    test "should emit evaluation series on stop when applicable" do
      Application.put_env(:unleash, Unleash, [])

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
      Application.put_env(:unleash, Unleash, [])

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

    @tag capture_log: true
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
      Application.put_env(:unleash, Unleash, disable_client: true)

      on_exit(fn ->
        Application.put_env(:unleash, Unleash, disable_client: false)
      end)

      :ok
    end

    @tag capture_log: true
    test "should return the default if the client is disabled" do
      assert true == Unleash.enabled?(:test, %{}, true)
      assert false == Unleash.enabled?(:test, %{}, false)
    end

    test "should log if the client is disabled" do
      assert capture_log(fn ->
               Unleash.enabled?(:test1)
             end) =~ "Client is disabled, it will only return default:"
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
      Application.put_env(:unleash, Unleash, disable_client: true)

      on_exit(fn ->
        Application.put_env(:unleash, Unleash, disable_client: false)
      end)

      :ok
    end

    @tag capture_log: true
    test "should return the default if the client is disabled" do
      assert true == Unleash.get_variant(:variant, %{}, true)
      assert false == Unleash.get_variant(:variant, %{}, false)
    end

    test "should log if the client is disabled" do
      assert capture_log(fn ->
               Unleash.get_variant(:variant)
             end) =~ "Client is disabled, it will only return the fallback:"
    end
  end

  describe "start/1" do
    test "it should listen to configuration when starting the supervisor tree" do
      Unleash.ClientMock
      |> expect(:register_client, fn -> %Mojito.Response{} end)
      |> stub(:features, fn _ -> %Mojito.Response{} end)
      |> stub(:metrics, fn _ -> %Mojito.Response{} end)

      Application.put_env(:unleash, Unleash, client: Unleash.ClientMock)
      {:ok, pid} = Unleash.start(:normal, [])

      children = Supervisor.which_children(pid)

      assert Enum.any?(children, &Kernel.match?({Unleash.Repo, _, _, _}, &1))
      assert Enum.any?(children, &Kernel.match?({Unleash.Metrics, _, _, _}, &1))
    end

    test "it shouldn't start the metrics server if disabled" do
      Unleash.ClientMock
      |> expect(:register_client, fn -> %Mojito.Response{} end)
      |> stub(:features, fn _ -> %Mojito.Response{} end)

      Application.put_env(:unleash, Unleash, disable_metrics: true, client: Unleash.ClientMock)
      {:ok, pid} = Unleash.start(:normal, [])

      children = Supervisor.which_children(pid)

      assert Enum.any?(children, &Kernel.match?({Unleash.Repo, _, _, _}, &1))
      refute Enum.any?(children, &Kernel.match?({Unleash.Metrics, _, _, _}, &1))
    end

    test "it shouldn't start anything if the client is disabled" do
      Application.put_env(:unleash, Unleash, disable_client: true, client: Unleash.ClientMock)
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
