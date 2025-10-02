defmodule Unleash.SocketDebug do
  @moduledoc """
  Utilities for debugging HTTP connections and extracting socket information
  from httpc sessions to investigate hanging connections.
  """

  require Logger

  @doc """
  Extract all socket information from httpc sessions.
  Returns detailed information about active HTTP connections.
  """
  def debug_all_connections do
    :httpc.which_sessions()
    |> elem(0)
    |> Enum.with_index()
    |> Enum.map(fn {session, index} ->
      %{
        profile: :default,
        session_index: index,
        session_info: extract_session_info(session),
        socket_info: extract_socket_info(session),
        ssl_info: extract_ssl_info(session)
      }
    end)
  end

  @doc """
  Extract basic session information from httpc session tuple.
  """
  def extract_session_info(session) do
    case session do
      {:session, {{host, port}, pid}, _flag, protocol, _socket, _ssl_opts, _version, _keepalive,
       reused} ->
        %{
          host: host |> to_string(),
          port: port,
          pid: pid,
          protocol: protocol,
          process_alive: Process.alive?(pid),
          reused: reused
        }

      _ ->
        %{error: :unknown_session_format, raw: inspect(session)}
    end
  end

  @doc """
  Extract socket reference and network information from httpc session.
  """
  def extract_socket_info(session) do
    case extract_socket_reference(session) do
      {:ok, socket_ref} ->
        %{
          socket_ref: inspect(socket_ref),
          addresses: get_socket_addresses(socket_ref),
          socket_stats: get_socket_stats(socket_ref),
          socket_opts: get_socket_options(socket_ref),
          socket_health: check_socket_health(socket_ref)
        }

      {:error, reason} ->
        %{error: reason}
    end
  end

  @doc """
  Extract SSL/TLS connection information from httpc session.
  """
  def extract_ssl_info(session) do
    case extract_ssl_socket(session) do
      {:ok, ssl_socket} ->
        get_ssl_connection_info(ssl_socket)

      {:error, reason} ->
        %{error: reason}
    end
  end

  @doc """
  Extract socket reference from session tuple structure.
  """
  def extract_socket_reference(session) do
    case session do
      # SSL socket structure
      {:session, _host_info, _, _,
       {:sslsocket,
        {:gen_tcp, {:"$inet", :gen_tcp_socket, {_pid, {:"$socket", socket_ref}}}, _, _},
        _ssl_pids}, _, _, _, _} ->
        {:ok, socket_ref}

      # Plain TCP socket structure with $socket wrapper
      {:session, _host_info, _, _, {:"$socket", socket_ref}, _, _, _, _} ->
        {:ok, socket_ref}

      # Alternative TCP structure with gen_tcp wrapper
      {:session, _host_info, _, _,
       {:gen_tcp, {:"$inet", :gen_tcp_socket, {_pid, {:"$socket", socket_ref}}}}, _, _, _, _} ->
        {:ok, socket_ref}

      # Direct port reference (common for plain HTTP)
      {:session, _host_info, _, _protocol, socket_port, _ssl_opts, _version, _keepalive, _reused}
      when is_port(socket_port) ->
        {:ok, socket_port}

      # Modern Erlang socket format
      {:session, _host_info, _, _, {:gen_tcp, socket_ref}, _, _, _, _} when is_port(socket_ref) ->
        {:ok, socket_ref}

      # Legacy socket format
      {:session, _host_info, _, _, socket_ref, _, _, _, _}
      when is_port(socket_ref) ->
        {:ok, socket_ref}

      _ ->
        {:error, :socket_not_found}
    end
  end

  @doc """
  Extract SSL socket from session tuple structure.
  """
  def extract_ssl_socket(session) do
    case session do
      {:session, _host_info, _, _, {:sslsocket, _tcp_socket, _ssl_pids} = ssl_socket, _, _, _, _} ->
        {:ok, ssl_socket}

      _ ->
        {:error, :not_ssl_socket}
    end
  end

  @doc """
  Get socket addresses (local and peer) from socket reference.
  """
  def get_socket_addresses(socket_ref) do
    %{
      peer: get_peer_address(socket_ref),
      local: get_local_address(socket_ref)
    }
  end

  @doc """
  Get peer (remote) address from socket.
  """
  def get_peer_address(socket_ref) do
    case :inet.peername(socket_ref) do
      {:ok, {ip_tuple, port}} ->
        %{
          ip: ip_tuple_to_string(ip_tuple),
          port: port,
          ip_tuple: ip_tuple
        }

      {:error, reason} ->
        %{error: reason}
    end
  end

  @doc """
  Get local address from socket.
  """
  def get_local_address(socket_ref) do
    case :inet.sockname(socket_ref) do
      {:ok, {ip_tuple, port}} ->
        %{
          ip: ip_tuple_to_string(ip_tuple),
          port: port,
          ip_tuple: ip_tuple
        }

      {:error, reason} ->
        %{error: reason}
    end
  end

  @doc """
  Get socket statistics (bytes sent/received, etc.).
  """
  def get_socket_stats(socket_ref) do
    case :inet.getstat(socket_ref) do
      {:ok, stats} ->
        stats
        |> Enum.into(%{})
        |> Map.merge(%{
          status: :ok,
          recv_bytes: stats[:recv_oct] || 0,
          send_bytes: stats[:send_oct] || 0,
          recv_packets: stats[:recv_cnt] || 0,
          send_packets: stats[:send_cnt] || 0
        })

      {:error, reason} ->
        %{error: reason}
    end
  end

  @doc """
  Get socket options (buffer sizes, timeouts, etc.).
  """
  def get_socket_options(socket_ref) do
    opts_to_check = [
      :active,
      :buffer,
      :delay_send,
      :exit_on_close,
      :header,
      :keepalive,
      :nodelay,
      :packet,
      :packet_size,
      :read_packets,
      :recbuf,
      :reuseaddr,
      :send_timeout,
      :send_timeout_close,
      :sndbuf,
      :priority,
      :tos
    ]

    case :inet.getopts(socket_ref, opts_to_check) do
      {:ok, opts} ->
        opts |> Enum.into(%{})

      {:error, reason} ->
        %{error: reason}
    end
  end

  @doc """
  Check if socket is healthy and responsive.
  """
  def check_socket_health(socket_ref) do
    case :inet.getstat(socket_ref, [:recv_oct]) do
      {:ok, _} -> :healthy
      {:error, :closed} -> :closed
      {:error, :enotconn} -> :not_connected
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get SSL/TLS connection information.
  """
  def get_ssl_connection_info(ssl_socket) do
    case :ssl.connection_information(ssl_socket) do
      {:ok, info} ->
        info_map = info |> Enum.into(%{})

        %{
          protocol: info_map[:protocol],
          cipher_suite: describe_cipher_suite(info_map[:selected_cipher_suite]),
          sni_hostname: info_map[:sni_hostname],
          session_id: format_session_id(info_map[:session_id]),
          compression: info_map[:compression],
          status: :connected
        }

      {:error, reason} ->
        %{error: reason, status: :ssl_error}
    end
  end

  @doc """
  Convert IP tuple to string representation.
  """
  def ip_tuple_to_string({a, b, c, d}) when is_integer(a) do
    "#{a}.#{b}.#{c}.#{d}"
  end

  def ip_tuple_to_string({a, b, c, d, e, f, g, h}) when is_integer(a) do
    # IPv6 address
    :inet.ntoa({a, b, c, d, e, f, g, h}) |> to_string()
  end

  def ip_tuple_to_string(ip) do
    inspect(ip)
  end

  @doc """
  Monitor a specific socket for changes over time.
  """
  def monitor_socket(socket_ref, duration_ms \\ 60_000) do
    Logger.info("#{__MODULE__}; Starting socket monitor for #{inspect(socket_ref)}")

    monitor_pid =
      spawn(fn ->
        monitor_socket_loop(socket_ref, 0, duration_ms)
      end)

    {:ok, monitor_pid}
  end

  @doc """
  Find potentially hanging sockets based on various criteria.
  """
  def find_hanging_connections do
    debug_all_connections()
    |> Enum.filter(&is_potentially_hanging/1)
  end

  # Private functions

  defp monitor_socket_loop(socket_ref, elapsed_ms, max_duration)
       when elapsed_ms >= max_duration do
    Logger.info("#{__MODULE__}; Socket monitoring completed for #{inspect(socket_ref)}")
  end

  defp monitor_socket_loop(socket_ref, elapsed_ms, max_duration) do
    stats = get_socket_stats(socket_ref)
    health = check_socket_health(socket_ref)

    Logger.info(
      "#{__MODULE__}; Socket #{inspect(socket_ref)}: health=#{inspect(health)}, stats=#{inspect(stats)}"
    )

    # Check every 5 seconds
    Process.sleep(5_000)
    monitor_socket_loop(socket_ref, elapsed_ms + 5_000, max_duration)
  end

  defp is_potentially_hanging(connection_info) do
    socket_info = connection_info[:socket_info]
    session_info = connection_info[:session_info]

    cond do
      # Socket is closed or errored
      socket_info[:socket_health] in [:closed, :not_connected] ->
        true

      # Process is dead but socket still exists
      session_info[:process_alive] == false ->
        true

      # High number of received bytes but no recent activity (would need timestamp comparison)
      socket_info[:socket_stats][:recv_bytes] > 1_000_000 ->
        true

      # SSL connection errors
      Map.has_key?(socket_info, :error) or
          connection_info[:ssl_info][:status] == :ssl_error ->
        true

      true ->
        false
    end
  end

  defp describe_cipher_suite(nil), do: "unknown"

  defp describe_cipher_suite({key_exchange, cipher, hash, signature}) do
    "#{key_exchange}_#{cipher}_#{hash}_#{signature}"
  end

  defp describe_cipher_suite(other), do: inspect(other)

  defp format_session_id(nil), do: nil

  defp format_session_id(session_id) when is_binary(session_id) do
    Base.encode16(session_id)
  end

  defp format_session_id(session_id), do: inspect(session_id)

  @doc """
  Example: Send GET request through SSL socket connection.

  Returns `{:ok, response_map}` on success or `{:error, reason}` on failure.
  The response map contains status, headers, and body fields.
  """
  def ssl_get(host, port \\ 443, path \\ "/") do
    # SSL socket options with certificate verification
    ssl_options = [
      :binary,
      active: false,
      packet: :http_bin,
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    Logger.info("#{__MODULE__}; Connecting to #{host}:#{port} via SSL")

    # Connect to SSL socket
    with {:ok, socket} <- :ssl.connect(String.to_charlist(host), port, ssl_options),
         :ok <- send_http_request(socket, host, path),
         {:ok, response} <- receive_http_response(socket) do
      :ssl.close(socket)
      Logger.info("#{__MODULE__}; SSL connection closed successfully")
      {:ok, response}
    else
      error ->
        Logger.error("#{__MODULE__}; SSL connection failed: #{inspect(error)}")
        error
    end
  end

  @doc """
  Example: Send GET request with raw SSL socket (manual packet handling).
  """
  def ssl_get_raw(host, port \\ 443, path \\ "/") do
    ssl_options = [
      :binary,
      active: false,
      # Handle packets manually
      packet: :raw,
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host)
    ]

    with {:ok, socket} <- :ssl.connect(String.to_charlist(host), port, ssl_options),
         :ok <- send_raw_http_request(socket, host, path),
         {:ok, response} <- receive_raw_response(socket) do
      :ssl.close(socket)
      {:ok, response}
    else
      error -> error
    end
  end

  @doc """
  Example: Test SSL GET request with common endpoints.
  """
  def test_ssl_requests do
    test_cases = [
      {"httpbin.org", 443, "/get"},
      {"api.github.com", 443, "/zen"},
      {"jsonplaceholder.typicode.com", 443, "/posts/1"}
    ]

    Enum.each(test_cases, fn {host, port, path} ->
      IO.puts("\n=== Testing #{host}#{path} ===")

      case ssl_get(host, port, path) do
        {:ok, %{status: {code, reason}, body: body}} ->
          IO.puts("✓ Status: #{code} #{reason}")
          IO.puts("  Body: #{String.slice(body, 0, 100)}...")

        {:error, reason} ->
          IO.puts("✗ Error: #{inspect(reason)}")
      end
    end)
  end

  # Private helper functions for SSL examples

  defp send_http_request(socket, host, path) do
    request = [
      "GET #{path} HTTP/1.1\r\n",
      "Host: #{host}\r\n",
      "User-Agent: Unleash-Elixir-SSL-Debug/1.0\r\n",
      "Accept: */*\r\n",
      "Connection: close\r\n",
      "\r\n"
    ]

    :ssl.send(socket, request)
  end

  defp send_raw_http_request(socket, host, path) do
    request =
      "GET #{path} HTTP/1.1\r\nHost: #{host}\r\nUser-Agent: Unleash-Raw-SSL/1.0\r\nConnection: close\r\n\r\n"

    :ssl.send(socket, request)
  end

  defp receive_http_response(socket) do
    receive_http_response(socket, %{status: nil, headers: [], body: ""})
  end

  defp receive_http_response(socket, acc) do
    case :ssl.recv(socket, 0, 5000) do
      {:ok, {:http_response, _version, status_code, reason_phrase}} ->
        receive_http_response(socket, %{acc | status: {status_code, to_string(reason_phrase)}})

      {:ok, {:http_header, _length, field, _reserved, value}} ->
        header = {normalize_header_field(field), to_string(value)}
        receive_http_response(socket, %{acc | headers: [header | acc.headers]})

      {:ok, :http_eoh} ->
        # End of headers, switch to binary mode for body
        :ssl.setopts(socket, packet: :raw)
        {:ok, body} = receive_body_data(socket, "")
        {:ok, %{acc | body: body, headers: Enum.reverse(acc.headers)}}

      {:error, :closed} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp receive_raw_response(socket) do
    case :ssl.recv(socket, 0, 5000) do
      {:ok, data} ->
        parse_raw_http_response(data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp receive_body_data(socket, acc) do
    case :ssl.recv(socket, 0, 5000) do
      {:ok, data} ->
        receive_body_data(socket, acc <> data)

      {:error, :closed} ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_header_field(field) when is_atom(field), do: Atom.to_string(field)
  defp normalize_header_field(field) when is_binary(field), do: field

  defp parse_raw_http_response(data) do
    case String.split(data, "\r\n\r\n", parts: 2) do
      [headers_part, body] ->
        lines = String.split(headers_part, "\r\n")
        [status_line | header_lines] = lines

        status = parse_status_line(status_line)
        headers = parse_header_lines(header_lines)

        {:ok, %{status: status, headers: headers, body: body}}

      [headers_part] ->
        lines = String.split(headers_part, "\r\n")
        [status_line | header_lines] = lines

        status = parse_status_line(status_line)
        headers = parse_header_lines(header_lines)

        {:ok, %{status: status, headers: headers, body: ""}}
    end
  end

  defp parse_status_line(line) do
    case String.split(line, " ", parts: 3) do
      [_version, code, reason] -> {String.to_integer(code), reason}
      [_version, code] -> {String.to_integer(code), ""}
      _ -> {500, "Invalid status line"}
    end
  end

  defp parse_header_lines(lines) do
    Enum.map(lines, fn line ->
      case String.split(line, ": ", parts: 2) do
        [key, value] -> {String.downcase(key), value}
        [key] -> {String.downcase(key), ""}
      end
    end)
  end
end
