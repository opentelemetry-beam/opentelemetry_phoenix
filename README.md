# OpentelemetryPhoenix

Telemetry handler that creates Opentelemetry spans from Phoenix events.

After installing, setup the handler in your application behaviour before your
top-level supervisor starts.

```elixir
OpentelemetryEcto.setup()
```

See the documentation for `OpentelemetryPhoenix.setup/1` for additional options that
may be supplied.


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `opentelemetry_phoenix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:opentelemetry_phoenix, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/opentelemetry_phoenix](https://hexdocs.pm/opentelemetry_phoenix).

