defmodule OpentelemetryPhoenix do
  @moduledoc """
  OpentelemetryPhoenix uses [telemetry](https://hexdocs.pm/telemetry/) handlers to create `OpenTelemetry` spans.

  Current events which are supported include endpoint start/stop, router start/stop,
  and router exceptions.

  ## Usage

  In your application start:

      def start(_type, _args) do
        OpenTelemetry.register_application_tracer(:my_app)
        OpentelemetryPhoenix.setup()

        children = [
          {Phoenix.PubSub, name: MyApp.PubSub},
          MyAppWeb.Endpoint
        ]

        opts = [strategy: :one_for_one, name: MyStore.Supervisor]
        Supervisor.start_link(children, opts)
      end

  """

  require OpenTelemetry.Tracer
  alias OpenTelemetry.{Span, Tracer}
  alias OpentelemetryPhoenix.Reason

  @typedoc "Setup options"
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
    attach_router_start_handler(opts)
    attach_router_dispatch_exception_handler(opts)

    :ok
  end

  defp ensure_opts(opts), do: Keyword.merge(default_opts(), opts)

  defp default_opts do
    [endpoint_prefix: [:phoenix, :endpoint]]
  end

  @spec attach_endpoint_start_handler(nil | maybe_improper_list | map) ::
          :ok | {:error, :already_exists}
  @doc false
  def attach_endpoint_start_handler(opts) do
    :telemetry.attach(
      {__MODULE__, :endpoint_start},
      opts[:endpoint_prefix] ++ [:start],
      &__MODULE__.handle_endpoint_start/4,
      opts
    )
  end

  @doc false
  def attach_endpoint_stop_handler(opts) do
    :telemetry.attach(
      {__MODULE__, :endpoint_stop},
      opts[:endpoint_prefix] ++ [:stop],
      &__MODULE__.handle_endpoint_stop/4,
      opts
    )
  end

  @doc false
  def attach_router_start_handler do
    :telemetry.attach(
      {__MODULE__, :router_dispatch_start},
      [:phoenix, :router_dispatch, :start],
      &__MODULE__.handle_router_dispatch_start/4,
      opts
    )
  end

  @doc false
  def attach_router_dispatch_exception_handler do
    :telemetry.attach(
      {__MODULE__, :router_dispatch_exception},
      [:phoenix, :router_dispatch, :exception],
      &__MODULE__.handle_router_dispatch_exception/4,
      opts
    )
  end

  @doc false
  def handle_endpoint_start(_event, _measurements, %{conn: %{adapter: adapter} = conn}, config) do
    # TODO: maybe add config for what paths are traced? Via sampler?
    :otel_propagator.text_map_extract(conn.req_headers)

    span_name = "HTTP #{conn.method}"
    new_ctx = Tracer.start_span(span_name, %{kind: :SERVER})
    _ = Tracer.set_current_span(new_ctx)

    peer_data = Plug.Conn.get_peer_data(conn)

    user_agent = header_value(conn, "user-agent")
    peer_ip = Map.get(peer_data, :address)

    attributes = [
      "http.client_ip": client_ip(conn),
      "http.flavor": http_flavor(adapter),
      "http.host": conn.host,
      "http.method": conn.method,
      "http.scheme": "#{conn.scheme}",
      "http.target": conn.request_path,
      "http.user_agent": user_agent,
      "net.host.ip": to_string(:inet_parse.ntoa(conn.remote_ip)),
      "net.host.port": conn.port,
      "net.peer.ip": to_string(:inet_parse.ntoa(peer_ip)),
      "net.peer.port": peer_data.port,
      "net.transport": :"IP.TCP"
    ] ++ build_additional_attributes(config)

    Span.set_attributes(new_ctx, attributes)
  end

  @doc false
  def handle_endpoint_stop(_event, _measurements, %{conn: conn}, _config) do
    span_ctx = Tracer.current_span_ctx()
    Span.set_attribute(span_ctx, :"http.status", conn.status)
    Span.end_span(span_ctx)
  end

  @doc false
  def handle_router_dispatch_start(_event, _measurements, meta, _config) do
    attributes = [
      "phoenix.plug": meta.plug,
      "phoenix.action": meta.plug_opts,
      "http.target": meta.route
    ]

    span_ctx = Tracer.current_span_ctx()
    Span.update_name(span_ctx, "#{meta.conn.method} #{meta.route}")
    Span.set_attributes(span_ctx, attributes)
  end

  @doc false
  def handle_router_dispatch_exception(
        _event,
        _measurements,
        %{kind: kind, reason: reason, stacktrace: stacktrace},
        _config
      ) do
    exception_attrs =
      Keyword.merge(
        [
          type: kind,
          stacktrace: Exception.format_stacktrace(stacktrace)
        ],
        Reason.normalize(reason)
      )

    status = OpenTelemetry.status(:Error, "Error")
    span_ctx = Tracer.current_span_ctx()

    Span.add_event(span_ctx, "exception", exception_attrs)
    Span.set_status(span_ctx, status)
  end

  defp http_flavor({_adapter_name, meta}) do
    case Map.get(meta, :version) do
      :"HTTP/1.0" -> :"1.0"
      :"HTTP/1.1" -> :"1.1"
      :"HTTP/2.0" -> :"2.0"
      :SPDY -> :SPDY
      :QUIC -> :QUIC
      nil -> ""
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

  defp build_additional_attributes([additional_attributes: {func, args}]), do:
    apply(func, args)

  defp build_additional_attributes([additional_attributes: attributes]) when is_list(attributes), do:
    attributes

  defp build_additional_attributes(), do: []
end
