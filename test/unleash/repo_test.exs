defmodule Unleash.RepoTest do
  use ExUnit.Case

  import Mox

  setup do
    default_config = Application.get_env(:unleash, Unleash, [])

    test_config =
      Keyword.merge(default_config,
        client: Unleash.ClientMock,
        appname: "myapp",
        instance_id: "node@a",
        retries: 3,
        features_period: 100
      )

    Application.put_env(:unleash, Unleash, test_config)

    stop_supervised(Unleash.Repo)

    state = get_initial_state()

    {:ok, pid} = start_supervised({Unleash.Repo, state})

    %{repo_pid: pid}
  end

  describe "handle_info/2" do
    test "executes telemetry when no retries remaining", %{repo_pid: repo_pid} do
      attach_telemetry_event([:unleash, :repo, :disable_polling])

      Process.send(repo_pid, {:initialize, nil, 0}, [])

      assert_receive {:telemetry_metadata, _metadata}, 100
    end

    test "executes telemetry when scheduling a features poll", %{repo_pid: repo_pid} do
      Unleash.ClientMock
      |> allow(self(), repo_pid)
      |> stub(:features, fn _ -> {"test_etag", get_initial_state()} end)

      attach_telemetry_event([:unleash, :repo, :schedule])

      Process.send(repo_pid, {:initialize, nil, 3}, [])

      assert_receive {:telemetry_metadata, metadata}, 100
      assert metadata.etag == "test_etag"
    end

    test "executes telemetry when reading features from remote", %{repo_pid: repo_pid} do
      Unleash.ClientMock
      |> allow(self(), repo_pid)
      |> stub(:features, fn _ -> {"test_etag", get_initial_state()} end)

      attach_telemetry_event([:unleash, :repo, :features_update])

      Process.send(repo_pid, {:initialize, nil, 3}, [])

      assert_receive {:telemetry_metadata, metadata}, 100
      assert metadata.source == :remote
    end

    test "executes telemetry when reading features from cache", %{repo_pid: repo_pid} do
      Unleash.ClientMock
      |> allow(self(), repo_pid)
      |> stub(:features, fn _ -> :cached end)

      attach_telemetry_event([:unleash, :repo, :features_update])

      Process.send(repo_pid, {:initialize, nil, 3}, [])

      assert_receive {:telemetry_metadata, metadata}, 100
      assert metadata.source == :cache
    end

    test "executes telemetry when reading features from file", %{repo_pid: repo_pid} do
      Unleash.ClientMock
      |> allow(self(), repo_pid)
      |> expect(:features, fn _ -> :cached end)
      |> expect(:features, fn _ ->
        {:error, "error"}
      end)

      attach_telemetry_event([:unleash, :repo, :features_update])

      Process.send(repo_pid, {:initialize, nil, 3}, [])

      assert_receive {:telemetry_metadata, _}, 100

      Process.send(repo_pid, {:initialize, nil, 3}, [])

      assert_receive {:telemetry_metadata, metadata}, 100

      assert metadata.source == :backup_file
    end

    test "executes telemetry when writing to the backup file", %{
      repo_pid: repo_pid
    } do
      Unleash.ClientMock
      |> allow(self(), repo_pid)
      |> stub(:features, fn _ ->
        {"test_etag", get_state_with_features()}
      end)

      attach_telemetry_event([:unleash, :repo, :backup_file_update])

      Process.send(repo_pid, {:initialize, nil, 3}, [])

      assert_receive {:telemetry_metadata, metadata}, 100
      assert IO.iodata_to_binary(metadata.content) =~ "test1"
    end
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

  defp get_initial_state do
    Unleash.Features.from_map!(%{
      "version" => 1,
      "features" => []
    })
  end

  defp get_state_with_features do
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
        }
      ]
    })
  end
end
