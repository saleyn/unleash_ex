defmodule Unleash.ClientTest do
  use ExUnit.Case

  import Mox

  alias Unleash.Client
  alias Unleash.Config

  setup :set_mox_from_context

  setup do
    http_client = Application.get_env(:unleas, :http_client)

    Application.put_env(:unleash, :http_client, SimpleHttpMock)

    on_exit(fn ->
      Application.put_env(:unleash, :http_client, http_client)
    end)

    :ok
  end

  describe "features/1" do
    test "publishes start event" do
      SimpleHttpMock
      |> expect(:get, fn _url, _headers ->
        {:ok,
         %SimpleHttp.Response{
           body: ~S({"version": "2", "features":[]}),
           headers: [{"etag", "x"}],
           status: 200
         }}
      end)
      |> expect(:status_code!, fn _ -> 200 end)
      |> expect(:response_body!, fn _ -> ~S({"version": "2", "features":[]}) end)
      |> expect(:response_headers!, fn _ -> [{"etag", "x"}] end)

      attach_telemetry_event([:unleash, :client, :fetch_features, :start])

      assert {:ok, %{etag: "x", features: %Unleash.Features{}}} = Client.features()
      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}
      assert metadata[:etag] == nil
      assert metadata[:url] =~ "client/features"
      assert metadata[:appname] == Config.appname()
      assert metadata[:instance_id] == Config.instance_id()

      assert is_number(measurements[:system_time])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop event" do
      SimpleHttpMock
      |> expect(:get, fn _url, _headers ->
        {:ok,
         %SimpleHttp.Response{
           body: ~S({"version": "1", "features":[]}),
           headers: [{"etag", "x"}],
           status: 200
         }}
      end)
      |> expect(:status_code!, fn _ -> 200 end)
      |> expect(:response_body!, fn _ -> ~S({"version": "2", "features":[]}) end)
      |> expect(:response_headers!, fn _ -> [{"etag", "x"}] end)

      attach_telemetry_event([:unleash, :client, :fetch_features, :stop])

      assert {:ok, %{etag: "x", features: %Unleash.Features{}}} = Client.features()

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:etag] == "x"
      assert metadata[:url] =~ "client/features"
      assert metadata[:http_response_status] == 200

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop event with an error" do
      SimpleHttpMock
      |> expect(:get, fn _url, _headers ->
        {:error, %SimpleHttp.Response{}}
      end)
      |> expect(:status_code!, fn _ -> 404 end)
      |> expect(:response_body!, fn _ -> ~S({"version": "2", "features":[]}) end)
      |> expect(:response_headers!, fn _ -> [{"etag", "x"}] end)

      attach_telemetry_event([:unleash, :client, :fetch_features, :stop])
      assert {:error, "{\"version\": \"2\", \"features\":[]}"} = Client.features()
      assert_received {:telemetry_metadata, metadata}
    end

    test "publishes exception event" do
      SimpleHttpMock
      |> expect(:get, fn _url, _headers ->
        raise "Unexpected error"
      end)

      attach_telemetry_event([:unleash, :client, :fetch_features, :exception])

      assert_raise RuntimeError, fn -> Client.features() end

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

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
      SimpleHttpMock
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %SimpleHttp.Response{status: 200}}
      end)
      |> expect(:status_code!, fn _ -> 200 end)
      |> expect(:status_code!, fn _ -> 200 end)
      |> expect(:response_body!, fn _ -> ~S({"version": "2", "features":[]}) end)
      |> expect(:response_headers!, fn _ -> [{"etag", "x"}] end)

      attach_telemetry_event([:unleash, :client, :register, :start])

      assert {:ok, %{"features" => [], "version" => "2"}} = Client.register_client()

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:url] =~ "client/register"
      assert metadata[:sdk_version] =~ "unleash_ex:"
      assert is_list(metadata[:strategies])
      assert metadata[:interval] == 600_000

      assert is_number(measurements[:system_time])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop event with measurements" do
      SimpleHttpMock
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %SimpleHttp.Response{status: 200}}
      end)
      |> expect(:status_code!, fn _ -> 200 end)
      |> expect(:status_code!, fn _ -> 200 end)
      |> expect(:response_body!, fn _ -> ~S({"version": "2", "features":[]}) end)

      attach_telemetry_event([:unleash, :client, :register, :stop])

      assert {:ok, %{"features" => [], "version" => "2"}} = Client.register_client()

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:url] =~ "client/register"
      assert metadata[:http_response_status] == 200

      assert metadata[:sdk_version] =~ "unleash_ex:"
      assert is_list(metadata[:strategies])
      assert metadata[:interval] == 600_000

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop with an error event" do
      SimpleHttpMock
      |> expect(:post, fn _url, _body, _headers ->
        {:error, %SimpleHttp.Response{status: 503}}
      end)
      |> expect(:status_code!, fn _ -> 503 end)
      |> expect(:status_code!, fn _ -> 503 end)
      |> expect(:response_body!, fn _ -> ~S() end)

      attach_telemetry_event([:unleash, :client, :register, :stop])

      assert {:error, ""} = Client.register_client()

      assert_received {:telemetry_metadata, metadata}
      assert 503 = metadata[:http_response_status]
    end

    test "publishes exception event with measurements" do
      SimpleHttpMock
      |> expect(:post, fn _url, _body, _headers ->
        raise "Unexpected error"
      end)

      attach_telemetry_event([:unleash, :client, :register, :exception])

      assert_raise RuntimeError, fn -> Client.register_client() end

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:url] =~ "client/register"

      assert metadata[:sdk_version] =~ "unleash_ex:"
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
      SimpleHttpMock
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %SimpleHttp.Response{status: 200}}
      end)
      |> expect(:status_code!, fn _ -> 200 end)

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

      assert {:ok, %SimpleHttp.Response{}} = Client.metrics(payload)

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:url] =~ "client/metrics"
      assert metadata[:metrics_payload] == payload

      assert is_number(measurements[:system_time])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop event with measurements" do
      SimpleHttpMock
      |> expect(:post, fn _url, _body, _headers ->
        {:ok, %SimpleHttp.Response{status: 200}}
      end)
      |> expect(:status_code!, fn _ -> 200 end)

      attach_telemetry_event([:unleash, :client, :push_metrics, :stop])

      assert {:ok, %SimpleHttp.Response{}} = Client.metrics(%{})

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:url] =~ "client/metrics"
      assert metadata[:http_response_status] == 200

      assert is_number(measurements[:duration])
      assert is_number(measurements[:monotonic_time])
    end

    test "publishes stop with an error event" do
      SimpleHttpMock
      |> expect(:post, fn _url, _body, _headers ->
        {:error, %SimpleHttp.Response{status: 503}}
      end)
      |> expect(:status_code!, fn _ -> 503 end)

      attach_telemetry_event([:unleash, :client, :push_metrics, :stop])

      assert {:error, %SimpleHttp.Response{status: 503}} = Client.metrics(%{})

      assert_received {:telemetry_metadata, metadata}
      assert metadata[:http_response_status] == 503
    end

    test "publishes exception event with measurements" do
      SimpleHttpMock
      |> expect(:post, fn _url, _body, _headers ->
        raise "Unexpected error"
      end)

      attach_telemetry_event([:unleash, :client, :push_metrics, :exception])

      assert_raise RuntimeError, fn -> Client.metrics(%{}) end

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

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
