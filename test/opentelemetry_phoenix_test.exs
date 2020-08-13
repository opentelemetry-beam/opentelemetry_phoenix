defmodule OpentelemetryPhoenixTest do
  use ExUnit.Case, async: false
  doctest OpentelemetryPhoenix

  require OpenTelemetry.Tracer
  require OpenTelemetry.Span
  require Record

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry/include/ot_span.hrl") do
    Record.defrecord(name, spec)
  end

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry_api/include/opentelemetry.hrl") do
    Record.defrecord(name, spec)
  end

  @conn %Plug.Conn{
    adapter: {
      Plug.Cowboy.Conn,
      %{
        bindings: %{},
        body_length: 0,
        cert: :undefined,
        has_body: false,
        headers: %{
          "accept" =>
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
          "accept-encoding" => "gzip, deflate",
          "accept-language" => "en-US,en;q=0.5",
          "connection" => "keep-alive",
          "cookie" => "",
          "host" => "mystore:4000",
          "referer" => "http://mystore:4000/users/123/orders",
          "upgrade-insecure-requests" => "1",
          "user-agent" =>
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:79.0) Gecko/20100101 Firefox/79.0"
        },
        host: "mystore",
        host_info: :undefined,
        method: "GET",
        path: "/users/123/orders",
        path_info: :undefined,
        peer: {{10, 211, 55, 2}, 64291},
        # pid: #PID<0.999.0>,
        port: 4000,
        qs: "",
        ref: MyStoreWeb.Endpoint.HTTP,
        scheme: "http",
        sock: {{172, 18, 0, 6}, 4000},
        streamid: 1,
        version: :"HTTP/1.1"
      }
    },
    assigns: %{},
    before_send: [],
    body_params: %Plug.Conn.Unfetched{aspect: :body_params},
    cookies: %Plug.Conn.Unfetched{aspect: :cookies},
    halted: false,
    host: "mystore",
    method: "GET",
    # owner: #PID<0.1000.0>,
    params: %Plug.Conn.Unfetched{aspect: :params},
    path_info: ["users", "123", "orders"],
    path_params: %{},
    port: 4000,
    private: %{phoenix_endpoint: MyStoreWeb.Endpoint},
    query_params: %Plug.Conn.Unfetched{aspect: :query_params},
    query_string: "",
    remote_ip: {10, 211, 55, 2},
    req_cookies: %Plug.Conn.Unfetched{aspect: :cookies},
    req_headers: [
      {"accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"},
      {"accept-encoding", "gzip, deflate"},
      {"accept-language", "en-US,en;q=0.5"},
      {"connection", "keep-alive"},
      {"cookie", ""},
      {"host", "mystore:4000"},
      {"referer", "http://mystore:4000/users/123/orders"},
      {"traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"},
      {"tracestate", "congo=t61rcWkgMzE"},
      {"upgrade-insecure-requests", "1"},
      {"user-agent",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:79.0) Gecko/20100101 Firefox/79.0"}
    ],
    request_path: "/users/123/orders",
    resp_body: nil,
    resp_cookies: %{},
    resp_headers: [
      {"cache-control", "max-age=0, private, must-revalidate"},
      {"x-request-id", "FiV5LWESM10-hB0AAAKB"}
    ],
    scheme: :http,
    script_name: [],
    secret_key_base: :...,
    state: :unset,
    status: nil
  }

  setup do
    :application.stop(:opentelemetry)
    :application.set_env(:opentelemetry, :tracer, :ot_tracer_default)

    :application.set_env(:opentelemetry, :processors, [
      {:ot_batch_processor, %{scheduled_delay_ms: 1}}
    ])

    :application.start(:opentelemetry)

    :ot_batch_processor.set_exporter(:ot_exporter_pid, self())
    :ok
  end

  test "records spans for Phoenix web requests" do
    OpentelemetryPhoenix.setup()

    :telemetry.execute(
      [:phoenix, :endpoint, :start],
      %{system_time: System.system_time()},
      %{conn: @conn, options: []}
    )

    :telemetry.execute(
      [:phoenix, :router_dispatch, :start],
      %{system_time: System.system_time()},
      %{
        conn: @conn,
        plug: MyStoreWeb.UserOrdersController,
        plug_opts: :index,
        route: "/users/{user_id}/orders",
        path_params: %{"user_id" => "123"}
      }
    )

    :telemetry.execute(
      [:phoenix, :endpoint, :stop],
      %{duration: 444},
      %{conn: stop_conn(@conn), options: []}
    )

    expected_status = OpenTelemetry.status(:Ok, "Ok")

    assert_receive {:span,
                    span(
                      name: "/users/{user_id}/orders",
                      attributes: list,
                      status: ^expected_status
                    )}

    assert [
             {"http.client_ip", "10.211.55.2"},
             {"http.host", "mystore"},
             {"http.method", "GET"},
             {"http.scheme", "http"},
             {"http.status", 200},
             {"http.target", "/users/123/orders"},
             {"http.user_agent",
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:79.0) Gecko/20100101 Firefox/79.0"},
             {"net.host.ip", "10.211.55.2"},
             {"net.host.port", 4000},
             {"net.peer.ip", "10.211.55.2"},
             {"net.peer.port", 64291},
             {"net.transport", "IP.TCP"},
             {"phoenix.action", "index"},
             {"phoenix.plug", "Elixir.MyStoreWeb.UserOrdersController"}
           ] == List.keysort(list, 0)
  end

  test "records exceptions for Phoenix web requests" do
    OpentelemetryPhoenix.setup()

    :telemetry.execute(
      [:phoenix, :endpoint, :start],
      %{system_time: System.system_time()},
      %{conn: @conn, options: []}
    )

    :telemetry.execute(
      [:phoenix, :router_dispatch, :start],
      %{system_time: System.system_time()},
      %{
        conn: @conn,
        plug: MyStoreWeb.UserOrdersController,
        plug_opts: :index,
        route: "/users/{user_id}/orders",
        path_params: %{"user_id" => "123"}
      }
    )

    try do
      raise ArgumentError, "Wrong argument type for x"
    catch
      error, reason ->
        stacktrace = __STACKTRACE__
        conn = exception_conn(@conn)

        :telemetry.execute(
          [:phoenix, :error_rendered],
          %{duration: 222},
          %{kind: error, reason: reason, stacktrace: stacktrace, conn: conn, status: conn.status}
        )
    end

    :telemetry.execute(
      [:phoenix, :endpoint, :stop],
      %{duration: 444},
      %{conn: exception_conn(@conn), options: []}
    )

    expected_status = OpenTelemetry.status(:InternalError, "Internal Error")

    assert_receive {:span,
                    span(
                      name: "/users/{user_id}/orders",
                      attributes: list,
                      kind: :SERVER,
                      events: [
                        event(
                          name: "exception",
                          attributes: [
                            {"type", "error"},
                            {"message", "Wrong argument type for x"},
                            {"stacktrace", stacktrace},
                            {"error", "true"}
                          ]
                        )
                      ],
                      status: ^expected_status
                    )}

    assert [
             {"http.client_ip", "10.211.55.2"},
             {"http.host", "mystore"},
             {"http.method", "GET"},
             {"http.scheme", "http"},
             {"http.status", 500},
             {"http.target", "/users/123/orders"},
             {"http.user_agent",
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:79.0) Gecko/20100101 Firefox/79.0"},
             {"net.host.ip", "10.211.55.2"},
             {"net.host.port", 4000},
             {"net.peer.ip", "10.211.55.2"},
             {"net.peer.port", 64291},
             {"net.transport", "IP.TCP"},
             {"phoenix.action", "index"},
             {"phoenix.plug", "Elixir.MyStoreWeb.UserOrdersController"}
           ] == List.keysort(list, 0)
  end

  test "records router exceptions for Phoenix web requests" do
    OpentelemetryPhoenix.setup()

    :telemetry.execute(
      [:phoenix, :endpoint, :start],
      %{system_time: System.system_time()},
      %{conn: @conn, options: []}
    )

    :telemetry.execute(
      [:phoenix, :router_dispatch, :start],
      %{system_time: System.system_time()},
      %{
        conn: @conn,
        plug: MyStoreWeb.UserOrdersController,
        plug_opts: :index,
        route: "/users/{user_id}/orders",
        path_params: %{"user_id" => "123"}
      }
    )

    try do
      raise ArgumentError, "Wrong argument type for x"
    catch
      _error, reason ->
        stacktrace = __STACKTRACE__

        :telemetry.execute(
          [:phoenix, :router_dispatch, :exception],
          %{duration: 222},
          %{kind: :error, reason: reason, stacktrace: stacktrace}
        )
    end

    :telemetry.execute(
      [:phoenix, :endpoint, :stop],
      %{duration: 444},
      %{conn: exception_conn(@conn), options: []}
    )

    expected_status = OpenTelemetry.status(:InternalError, "Internal Error")

    assert_receive {:span,
                    span(
                      name: "/users/{user_id}/orders",
                      attributes: list,
                      events: [
                        event(
                          name: "exception",
                          attributes: [
                            {"type", "error"},
                            {"stacktrace", stacktrace},
                            {"error", "true"}
                          ]
                        )
                      ],
                      status: ^expected_status
                    )}

    assert [
             {"http.client_ip", "10.211.55.2"},
             {"http.host", "mystore"},
             {"http.method", "GET"},
             {"http.scheme", "http"},
             {"http.status", 500},
             {"http.target", "/users/123/orders"},
             {"http.user_agent",
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:79.0) Gecko/20100101 Firefox/79.0"},
             {"net.host.ip", "10.211.55.2"},
             {"net.host.port", 4000},
             {"net.peer.ip", "10.211.55.2"},
             {"net.peer.port", 64291},
             {"net.transport", "IP.TCP"},
             {"phoenix.action", "index"},
             {"phoenix.plug", "Elixir.MyStoreWeb.UserOrdersController"}
           ] == List.keysort(list, 0)
  end

  def stop_conn(conn) do
    assigns = %{
      content: {:safe, []},
      flash: %{},
      layout: {MyStoreWeb.LayoutView, "app.html"},
      live_action: nil,
      live_module: MyStoreWeb.UserIndexLive
    }

    private = %{
      MyStoreWeb.Router => {[], %{}},
      :phoenix_action => :index,
      :phoenix_controller => MyStoreWeb.UserController,
      :phoenix_endpoint => MyStoreWeb.Endpoint,
      :phoenix_flash => %{},
      :phoenix_format => "html",
      :phoenix_layout => {MyStoreWeb.LayoutView, :app},
      :phoenix_router => MyStoreWeb.Router,
      :phoenix_template => "template.html",
      :phoenix_view => Phoenix.LiveView.Static,
      :plug_session => %{"_csrf_token" => "ZgdK3bUC3UKIZ3CiyKzM7wQh"},
      :plug_session_fetch => :done
    }

    resp_headers = [
      {"content-type", "text/html; charset=utf-8"},
      {"cache-control",
       "max-age=0, no-cache, no-store, must-revalidate, post-check=0, pre-check=0"},
      {"x-request-id", "FiV5LWESM10-hB0AAAKB"},
      {"x-frame-options", "SAMEORIGIN"},
      {"x-xss-protection", "1; mode=block"},
      {"x-content-type-options", "nosniff"},
      {"x-download-options", "noopen"},
      {"x-permitted-cross-domain-policies", "none"},
      {"cross-origin-window-policy", "deny"},
      {"vary", "x-requested-with"}
    ]

    conn
    |> Map.put(:assigns, assigns)
    |> Map.put(:body_params, %{})
    |> Map.put(:cookies, %{})
    |> Map.put(:params, %{"user_id" => 123})
    |> Map.put(:private, private)
    |> Map.put(:query_params, %{})
    |> Map.put(:req_cookies, %{})
    |> Map.put(:resp_body, [])
    |> Map.put(:resp_cookies, %{})
    |> Map.put(:resp_headers, resp_headers)
    |> Map.put(:state, :set)
    |> Map.put(:status, 200)
  end

  def exception_conn(conn) do
    conn
    |> stop_conn()
    |> Map.put(:status, 500)
  end
end
