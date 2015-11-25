defmodule DBConnection.Sojourn do

  @behaviour DBConnection.Pool

  @broker    DBConnection.Sojourn.Timeout
  @time_unit :micro_seconds

  import Supervisor.Spec

  def start_link(mod, opts) do
    Supervisor.start_link(children(mod, opts), [strategy: :rest_for_one])
  end

  def child_spec(mod, opts, child_opts \\ []) do
    args = [children(mod, opts), [strategy: :rest_for_one]]
    supervisor(Supervisor, args, child_opts)
  end

  def checkout(broker, opts) do
    case ask(broker, opts) do
      {:go, ref, {pid, mod, state}, _, _}    -> {:ok, {pid, ref}, mod, state}
      {drop, _} when drop in [:drop, :retry] -> :error
    end
  end

  def checkin({pid, ref}, state, _) do
    DBConnection.Sojourn.Connection.checkin(pid, ref, state)
  end

  def disconnect({pid, ref}, err, state, _) do
    DBConnection.Sojourn.Connection.disconnect(pid, ref, err, state)
  end

  def stop({pid, ref}, reason, state, _) do
    DBConnection.Sojourn.Connection.stop(pid, ref, reason, state)
  end

  ## Helpers

  defp children(mod, opts) do
    [broker(opts), conn_sup(mod, opts), starter(opts)]
  end

  defp broker(opts) do
    case Keyword.get(opts, :name, nil) do
      nil ->
        worker(:sbroker, broker_args(opts))
      name when is_atom(name) ->
        worker(:sbroker, [{:local, name} | broker_args(opts)])
      name ->
        worker(:sbroker, [name | broker_args(opts)])
    end
  end

  defp broker_args(opts) do
    mod        = Keyword.get(opts, :broker, @broker)
    start_opts = Keyword.get(opts, :broker_start_opt, [time_unit: @time_unit])
    [mod, opts, start_opts]
  end

  defp conn_sup(mod, opts) do
    conn = DBConnection.Connection.child_spec(mod, opts, :sojourn, [])
    supervisor(Supervisor, [[conn], [strategy: :simple_one_for_one]])
  end

  defp starter(opts) do
    worker(DBConnection.Sojourn.Starter, [opts], [restart: :transient])
  end

  defp ask(broker, opts) do
    case Keyword.get(opts, :queue, true) do
      true  -> :sbroker.ask(broker)
      false -> :sbroker.nb_ask(broker)
    end
  end
end
