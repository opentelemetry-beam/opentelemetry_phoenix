defmodule OpentelemetryPhoenix do
  @moduledoc """
  OpentelemetryPhoenix uses Telemetry handlers to create OpenTelemetry spans.

  ## Usage

  In your application start:

  `OpentelemetryPhoenix.setup()`
  """

  require OpenTelemetry.Tracer
  require OpenTelemetry.Span

  @type opts :: [endpoint_prefix()]

  @typedoc "The endpoint prefix in your endpoint. Defaults to `[:phoenix, :endpoint]`"
  @type endpoint_prefix :: {:endpoint_prefix, [atom()]}

  @doc """
  Initializes and configures the telemetry handlers.
  """
  @spec setup(opts()) :: :ok
  def setup(opts \\ []) do
    opts = ensure_opts(opts)

    _ = OpenTelemetry.register_application_tracer(:opentelemetry_phoenix)
    attach_endpoint_start_handler(opts)
    attach_endpoint_stop_handler(opts)
    attach_exception_handler()
    attach_router_start_handler()
    attach_router_dispatch_exception_handler()

    :ok
  end

  defp ensure_opts(opts), do: Keyword.merge(default_opts(), opts)

  defp default_opts do
    [endpoint_prefix: [:phoenix, :endpoint]]
  end

  @doc false
  def attach_endpoint_start_handler(opts) do
    :telemetry.attach(
      {__MODULE__, :endpoint_start},
      opts[:endpoint_prefix] ++ [:start],
      &__MODULE__.handle_endpoint_start/4,
      %{}
    )
  end

  @doc false
  def attach_endpoint_stop_handler(opts) do
    :telemetry.attach(
      {__MODULE__, :endpoint_stop},
      opts[:endpoint_prefix] ++ [:stop],
      &__MODULE__.handle_endpoint_stop/4,
      %{}
    )
  end

  @doc false
  def attach_router_start_handler do
    :telemetry.attach(
      {__MODULE__, :router_dispatch_start},
      [:phoenix, :router_dispatch, :start],
      &__MODULE__.handle_router_dispatch_start/4,
      %{}
    )
  end

  @doc false
  def attach_router_dispatch_exception_handler do
    :telemetry.attach(
      {__MODULE__, :router_dispatch_exception},
      [:phoenix, :router_dispatch, :exception],
      &__MODULE__.handle_router_dispatch_exception/4,
      %{}
    )
  end

  @doc false
  def attach_exception_handler do
    :telemetry.attach(
      {__MODULE__, :endpoint_exception},
      [:phoenix, :error_rendered],
      &__MODULE__.handle_exception/4,
      %{}
    )
  end

  @doc false
  def handle_endpoint_start(_event, _measurements, %{conn: conn}, _config) do
    # TODO: maybe add config for what paths are traced
    ctx = :ot_propagation.http_extract(conn.req_headers)

    span_name = "HTTP #{conn.method}"

    OpenTelemetry.Tracer.start_span(span_name, %{kind: :SERVER, parent: ctx})

    peer_data = Plug.Conn.get_peer_data(conn)

    user_agent = header_value(conn, "user-agent")
    peer_ip = Map.get(peer_data, :address)

    attributes = [
      {"http.client_ip", client_ip(conn)},
      {"http.host", conn.host},
      {"http.method", conn.method},
      {"http.scheme", "#{conn.scheme}"},
      {"http.target", conn.request_path},
      {"http.user_agent", user_agent},
      {"net.host.ip", to_string(:inet_parse.ntoa(conn.remote_ip))},
      {"net.host.port", conn.port},
      {"net.peer.ip", to_string(:inet_parse.ntoa(peer_ip))},
      {"net.peer.port", peer_data.port},
      {"net.transport", "IP.TCP"}
    ]

    OpenTelemetry.Span.set_attributes(attributes)
  end

  def handle_endpoint_stop(_event, _measurements, %{conn: conn}, _config) do
    OpenTelemetry.Span.set_attribute("http.status", conn.status)
    span_status(conn.status) |> OpenTelemetry.Span.set_status()
    OpenTelemetry.Tracer.end_span()
  end

  def handle_router_dispatch_start(_event, _measurements, meta, _config) do
    OpenTelemetry.Span.update_name("#{meta.conn.method} #{meta.route}")

    attributes = [
      {"phoenix.plug", to_string(meta.plug)},
      {"phoenix.action", to_string(meta.plug_opts)}
    ]

    OpenTelemetry.Span.set_attributes(attributes)
  end

  def handle_exception(_event, _measurements, meta, _config) do
    exception_attrs = [
      {"type", to_string(meta.kind)},
      {"message", meta.reason.message},
      {"stacktrace", "#{inspect(meta.stacktrace)}"},
      {"error", "true"}
    ]

    # TODO: events don't seem to be supported in Jaeger or Zipkin but do in Lightstep
    OpenTelemetry.Span.add_event("exception", exception_attrs)
    OpenTelemetry.Span.set_attributes([{"http.status", meta.status}])
    span_status(meta.status) |> OpenTelemetry.Span.set_status()
    OpenTelemetry.Tracer.end_span()
  end

  def handle_router_dispatch_exception(_event, _measurements, meta, _config) do
    # TODO: reason is a %Plug.Conn.WrapperError{} so no message
    exception_attrs = [
      {"type", to_string(meta.kind)},
      {"stacktrace", "#{inspect(meta.stacktrace)}"},
      {"error", "true"}
    ]

    # TODO: events don't seem to be supported in Jaeger or Zipkin but do in Lightstep
    OpenTelemetry.Span.add_event("exception", exception_attrs)
    OpenTelemetry.Span.set_attributes([{"http.status", 500}])
    span_status(500) |> OpenTelemetry.Span.set_status()
    OpenTelemetry.Tracer.end_span()
  end

  # 300s as Ok for now until redirect condition handled
  # https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/trace/semantic_conventions/http.md#status
  # move this to opentelemetry_erlang_api
  defp span_status(code, msg \\ nil) do
    case code do
      code when code >= 100 and code < 300 ->
        OpenTelemetry.status(:Ok, msg || "Ok")

      code when code >= 300 and code < 400 ->
        OpenTelemetry.status(:Ok, msg || "Ok")

      401 ->
        OpenTelemetry.status(:Unauthenticated, msg || "Unauthorized")

      403 ->
        OpenTelemetry.status(:PermissionDenied, msg || "Forbidden")

      404 ->
        OpenTelemetry.status(:NotFound, msg || "Not Found")

      412 ->
        OpenTelemetry.status(:FailedPrecondition, msg || "Failed Precondition")

      416 ->
        OpenTelemetry.status(:OutOfRange, msg || "Range Not Satisfiable")

      429 ->
        OpenTelemetry.status(:ResourceExhausted, msg || "Too Many Requests")

      code when code >= 400 and code < 500 ->
        OpenTelemetry.status(:InvalidArgument, msg || "Bad Argument")

      501 ->
        OpenTelemetry.status(:Unimplemented, msg || "Not Implemented")

      503 ->
        OpenTelemetry.status(:Unavailable, msg || "Service Unavailable")

      504 ->
        OpenTelemetry.status(:DeadlineExceeded, msg || "Gateway Timeout")

      code when code >= 500 ->
        OpenTelemetry.status(:InternalError, msg || "Internal Error")

      _ ->
        OpenTelemetry.status(:UnknownError, msg || "Unknown Status")
    end
  end

  defp client_ip(%{remote_ip: remote_ip} = conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [] ->
        to_string(:inet_parse.ntoa(remote_ip))

      [client | _] ->
        client
    end
  end

  defp header_value(conn, header) do
    case Plug.Conn.get_req_header(conn, header) do
      [] ->
        ""

      [value | _] ->
        value
    end
  end
end
