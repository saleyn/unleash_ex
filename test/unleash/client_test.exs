defmodule Unleash.ClientTest do
  use ExUnit.Case

  import Mox

  alias Unleash.Client

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

      test_pid = self()

      event = [:unleash, :client, :fetch_features, :start]

      :telemetry.attach(
        make_ref(),
        event,
        fn
          ^event, _measurements, metadata, _config ->
            send(test_pid, {:telemetry_metadata, metadata})
        end,
        []
      )

      assert {"x", %Unleash.Features{}} = Client.features()

      assert_received {:telemetry_metadata, metadata}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"
      assert metadata[:etag] == nil
    end

    test "publishes stop event with measurements" do
      MojitoMock
      |> expect(:get, fn _url, _headers ->
        {:ok,
         %Mojito.Response{
           body: ~S({"version": "1", "features":[]}),
           headers: [{"etag", "x"}],
           status_code: 200
         }}
      end)

      test_pid = self()

      event = [:unleash, :client, :fetch_features, :stop]

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

      assert {"x", %Unleash.Features{}} = Client.features()

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"
      assert metadata[:etag] == "x"

      assert is_number(measurements[:duration])
    end

    test "publishes stop with an error event" do
      MojitoMock
      |> expect(:get, fn _url, _headers ->
        {:error, %Mojito.Error{message: "Network unavailable"}}
      end)

      test_pid = self()

      event = [:unleash, :client, :fetch_features, :stop]

      :telemetry.attach(
        make_ref(),
        event,
        fn
          ^event, _measurements, metadata, _config ->
            send(test_pid, {:telemetry_metadata, metadata})
        end,
        []
      )

      assert {nil, %Mojito.Error{}} = Client.features()

      assert_received {:telemetry_metadata, metadata}

      assert %Mojito.Error{} = metadata[:error]
    end

    test "publishes exception event with measurements" do
      MojitoMock
      |> expect(:get, fn _url, _headers ->
        raise "Unexpected error"
      end)

      test_pid = self()

      event = [:unleash, :client, :fetch_features, :exception]

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

      assert_raise RuntimeError, fn -> Client.features() end

      assert_received {:telemetry_metadata, metadata}
      assert_received {:telemetry_measurements, measurements}

      assert metadata[:appname] == "myapp"
      assert metadata[:instance_id] == "node@a"
      assert metadata[:etag] == nil

      assert metadata[:kind] == :error
      assert is_list(metadata[:stacktrace])
      assert %RuntimeError{} = metadata[:reason]

      assert is_number(measurements[:duration])
    end
  end
end
