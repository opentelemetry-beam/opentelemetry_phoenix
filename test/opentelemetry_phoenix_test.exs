defmodule OpentelemetryPhoenixTest do
  use ExUnit.Case, async: false
  doctest OpentelemetryPhoenix

  require OpenTelemetry.Tracer
  require OpenTelemetry.Span
  require Record

  alias PhoenixMeta, as: Meta

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry/include/ot_span.hrl") do
    Record.defrecord(name, spec)
  end

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry_api/include/opentelemetry.hrl") do
    Record.defrecord(name, spec)
  end

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
      Meta.endpoint_start()
    )

    :telemetry.execute(
      [:phoenix, :router_dispatch, :start],
      %{system_time: System.system_time()},
      Meta.router_dispatch_start()
    )

    :telemetry.execute(
      [:phoenix, :endpoint, :stop],
      %{duration: 444},
      Meta.endpoint_stop()
    )

    expected_status = OpenTelemetry.status(:Ok, "Ok")

    assert_receive {:span,
                    span(
                      name: "GET /users/:user_id",
                      attributes: list,
                      status: ^expected_status
                    )}

    assert [
             "http.client_ip": "10.211.55.2",
             "http.flavor": :"1.1",
             "http.host": "localhost",
             "http.method": "GET",
             "http.scheme": "http",
             "http.status": 200,
             "http.target": "/users/123",
             "http.user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:81.0) Gecko/20100101 Firefox/81.0",
             "net.host.ip": "10.211.55.2",
             "net.host.port": 4000,
             "net.peer.ip": "10.211.55.2",
             "net.peer.port": 64291,
             "net.transport": :"IP.TCP",
             "phoenix.action": :user,
             "phoenix.plug": Elixir.MyStoreWeb.PageController
           ] == List.keysort(list, 0)
  end

  test "records exceptions for Phoenix web requests" do
    OpentelemetryPhoenix.setup()

    :telemetry.execute(
      [:phoenix, :endpoint, :start],
      %{system_time: System.system_time()},
      Meta.endpoint_start(:exception)
    )

    :telemetry.execute(
      [:phoenix, :router_dispatch, :start],
      %{system_time: System.system_time()},
      Meta.router_dispatch_start(:exception)
    )

    :telemetry.execute(
      [:phoenix, :router_dispatch, :exception],
      %{duration: 222},
      Meta.router_dispatch_exception(:normal)
    )

    :telemetry.execute(
      [:phoenix, :endpoint, :stop],
      %{duration: 444},
      Meta.endpoint_stop(:exception)
    )

    expected_status = OpenTelemetry.status(:InternalError, "Internal Error")

    assert_receive {:span,
                    span(
                      name: "GET /users/:user_id/exception",
                      attributes: list,
                      kind: :SERVER,
                      events: [
                        event(
                          name: "exception",
                          attributes: [
                            type: :error,
                            stacktrace: stacktrace,
                            reason: :badkey,
                            key: :name,
                            map: %{username: "rick"}
                          ]
                        )
                      ],
                      status: ^expected_status
                    )}

    assert [
             "http.client_ip": "10.211.55.2",
             "http.flavor": :"1.1",
             "http.host": "localhost",
             "http.method": "GET",
             "http.scheme": "http",
             "http.status": 500,
             "http.target": "/users/123/exception",
             "http.user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:81.0) Gecko/20100101 Firefox/81.0",
             "net.host.ip": "10.211.55.2",
             "net.host.port": 4000,
             "net.peer.ip": "10.211.55.2",
             "net.peer.port": 64291,
             "net.transport": :"IP.TCP",
             "phoenix.action": :code_exception,
             "phoenix.plug": MyStoreWeb.PageController
           ] == List.keysort(list, 0)
  end

  test "records exceptions for Phoenix web requests with plug wrappers" do
    OpentelemetryPhoenix.setup()

    :telemetry.execute(
      [:phoenix, :endpoint, :start],
      %{system_time: System.system_time()},
      Meta.endpoint_start(:exception)
    )

    :telemetry.execute(
      [:phoenix, :router_dispatch, :start],
      %{system_time: System.system_time()},
      Meta.router_dispatch_start(:exception)
    )

    :telemetry.execute(
      [:phoenix, :router_dispatch, :exception],
      %{duration: 222},
      Meta.router_dispatch_exception(:plug_wrapper)
    )

    :telemetry.execute(
      [:phoenix, :endpoint, :stop],
      %{duration: 444},
      Meta.endpoint_stop(:exception)
    )

    expected_status = OpenTelemetry.status(:InternalError, "Internal Error")

    assert_receive {:span,
                    span(
                      name: "GET /users/:user_id/exception",
                      attributes: list,
                      kind: :SERVER,
                      events: [
                        event(
                          name: "exception",
                          attributes: [
                            type: :error,
                            stacktrace: stacktrace,
                            reason: :badarith
                          ]
                        )
                      ],
                      status: ^expected_status
                    )}

    assert [
             "http.client_ip": "10.211.55.2",
             "http.flavor": :"1.1",
             "http.host": "localhost",
             "http.method": "GET",
             "http.scheme": "http",
             "http.status": 500,
             "http.target": "/users/123/exception",
             "http.user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:81.0) Gecko/20100101 Firefox/81.0",
             "net.host.ip": "10.211.55.2",
             "net.host.port": 4000,
             "net.peer.ip": "10.211.55.2",
             "net.peer.port": 64291,
             "net.transport": :"IP.TCP",
             "phoenix.action": :code_exception,
             "phoenix.plug": MyStoreWeb.PageController
           ] == List.keysort(list, 0)
  end
end
