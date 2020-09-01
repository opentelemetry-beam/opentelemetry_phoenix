defmodule OpentelemetryPhoenix.PubSub do
  def inject_msg_ctx(msg) do
    ctx = Tracer.current_span_ctx()
    Map.put(msg, :__ot_trace_parent, ctx)
  end

  @doc """
  Extracts the trace context from a Message
  """
  def extract_msg_ctx(msg) do
    Map.pop(msg, :__ot_trace_parent, :undefined)
  end
end
