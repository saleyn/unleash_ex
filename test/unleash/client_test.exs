defmodule Unleash.ClientTest do
  use ExUnit.Case

  import Mox

  alias Unleash.Client

  @moduletag capture_log: true

  setup :set_mox_from_context

  setup do
    default_config = Application.get_env(:unleash, Unleash, [])

    test_config =
      Keyword.merge(default_config,
        http_client: MojitoMock,
        appname: "myapp",
        instance_id: "node@a"
      )

    Application.put_env(:unleash, Unleash, test_config)

    on_exit(fn -> Application.put_env(:unleash, Unleash, default_config) end)

    :ok
  end

  describe "features/1" do
    test "publishes start event" do
      MojitoMock
      |> expect(:get, fn _url, _headers ->
        {:ok,
         %Mojito.Response{
           body: ~S({"version": "1", "features":[]}),
           headers: [{"etag", "x"}],
           status_code: 200
         }}
      end)

      attach_telemetry_event([:unleash, :client, :fetch_features, :start])

      assert {"x", %Unleash.Features{}} = Client.features()

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"
      assert metadata[:etag] == nil
      assert metadata[:url] =~ "client/features"

      assert is_number(measurements[:system_time])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop event" do
      MojitoMock
      |> expect(:get, fn _url, _headers ->
        {:ok,
         %Mojito.Response{
           body: ~S({"version": "1", "features":[]}),
           headers: [{"etag", "x"}],
           status_code: 200
         }}
      end)

      attach_telemetry_event([:unleash, :client, :fetch_features, :stop])

      assert {"x", %Unleash.Features{}} = Client.features()

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"
      assert metadata[:etag] == "x"
      assert metadata[:url] =~ "client/features"
      assert metadata[:http_response_status] == 200

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop event with an error" do
      MojitoMock
      |> expect(:get, fn _url, _headers ->
        {:error, %Mojito.Error{message: "Network unavailable"}}
      end)

      attach_telemetry_event([:unleash, :client, :fetch_features, :stop])

      assert {nil, %Mojito.Error{}} = Client.features()

      assert_received {:telemetry_metadata, metadata}

      assert %Mojito.Error{} = metadata[:error]
    end

    test "publishes exception event" do
      MojitoMock
      |> expect(:get, fn _url, _headers ->
        raise "Unexpected error"
      end)

      attach_telemetry_event([:unleash, :client, :fetch_features, :exception])

      assert_raise RuntimeError, fn -> Client.features() end

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"
      assert metadata[:etag] == nil
      assert metadata[:url] =~ "client/features"

      assert metadata[:kind] == :error
      assert is_list(metadata[:stacktrace])
      assert %RuntimeError{} = metadata[:reason]

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])
    end
  end

  describe "register_client/0" do
    test "publishes start event" do
      MojitoMock
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %Mojito.Response{status_code: 200}}
      end)

      attach_telemetry_event([:unleash, :client, :register, :start])

      assert {:ok, %Mojito.Response{}} = Client.register_client()

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"

      assert metadata[:url] =~ "client/register"

      assert metadata[:sdk_version] == "unleash_ex:1.8.3"
      assert is_list(metadata[:strategies])
      assert metadata[:interval] == 600_000

      assert is_number(measurements[:system_time])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop event with measurements" do
      MojitoMock
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %Mojito.Response{status_code: 200}}
      end)

      attach_telemetry_event([:unleash, :client, :register, :stop])

      assert {:ok, %Mojito.Response{}} = Client.register_client()

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"

      assert metadata[:url] =~ "client/register"
      assert metadata[:http_response_status] == 200

      assert metadata[:sdk_version] == "unleash_ex:1.8.3"
      assert is_list(metadata[:strategies])
      assert metadata[:interval] == 600_000

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop with an error event" do
      MojitoMock
      |> expect(:post, fn _url, _body, _headers ->
        {:error, %Mojito.Error{message: "Network unavailable"}}
      end)

      attach_telemetry_event([:unleash, :client, :register, :stop])

      assert {:error, %Mojito.Error{}} = Client.register_client()

      assert_received {:telemetry_metadata, metadata}

      assert %Mojito.Error{} = metadata[:error]
    end

    test "publishes exception event with measurements" do
      MojitoMock
      |> expect(:post, fn _url, _body, _headers ->
        raise "Unexpected error"
      end)

      attach_telemetry_event([:unleash, :client, :register, :exception])

      assert_raise RuntimeError, fn -> Client.register_client() end

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"

      assert metadata[:url] =~ "client/register"

      assert metadata[:sdk_version] == "unleash_ex:1.8.3"
      assert is_list(metadata[:strategies])
      assert metadata[:interval] == 600_000

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])

      assert metadata[:kind] == :error
      assert is_list(metadata[:stacktrace])
      assert %RuntimeError{} = metadata[:reason]
    end
  end

  describe "metrics/1" do
    test "publishes start event" do
      MojitoMock
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %Mojito.Response{status_code: 200}}
      end)

      attach_telemetry_event([:unleash, :client, :push_metrics, :start])

      payload = %{
        bucket: %{
          start: "2023-01-19T15:00:15.269493Z",
          stop: "2023-01-19T15:00:25.270545Z",
          toggles: %{
            "example_toggle" => %{yes: 5, no: 0},
            "example_toggle_2" => %{yes: 55, no: 4}
          }
        }
      }

      assert {:ok, %Mojito.Response{}} = Client.metrics(payload)

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"

      assert metadata[:url] =~ "client/metrics"
      assert metadata[:metrics_payload] == payload

      assert is_number(measurements[:system_time])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop event with measurements" do
      MojitoMock
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %Mojito.Response{status_code: 200}}
      end)

      attach_telemetry_event([:unleash, :client, :push_metrics, :stop])

      assert {:ok, %Mojito.Response{}} = Client.metrics(%{})

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"

      assert metadata[:url] =~ "client/metrics"
      assert metadata[:http_response_status] == 200

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop with an error event" do
      MojitoMock
      |> expect(:post, fn _url, _body, _headers ->
        {:error, %Mojito.Error{message: "Network unavailable"}}
      end)

      attach_telemetry_event([:unleash, :client, :push_metrics, :stop])

      assert {:error, %Mojito.Error{}} = Client.metrics(%{})

      assert_received {:telemetry_metadata, metadata}

      assert %Mojito.Error{} = metadata[:error]
    end

    test "publishes exception event with measurements" do
      MojitoMock
      |> expect(:post, fn _url, _body, _headers ->
        raise "Unexpected error"
      end)

      attach_telemetry_event([:unleash, :client, :push_metrics, :exception])

      assert_raise RuntimeError, fn -> Client.metrics(%{}) end

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"

      assert metadata[:url] =~ "client/metrics"

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])

      assert metadata[:kind] == :error
      assert is_list(metadata[:stacktrace])
      assert %RuntimeError{} = metadata[:reason]
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
end
