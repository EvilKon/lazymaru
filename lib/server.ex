defmodule Lazymaru.Server do
  defmacro __using__(_) do
    quote do
      use LazyHelper.Params
      use LazyHelper.Response
      import unquote(__MODULE__)
      Module.register_attribute __MODULE__,
             :socks, accumulate: true, persist: false
      Module.register_attribute __MODULE__,
             :statics, accumulate: true, persist: false
      Module.register_attribute __MODULE__,
             :hooks, accumulate: true, persist: false
      @before_compile unquote(__MODULE__)
    end
  end


  defmacro __before_compile__(_) do
    quote do
      def start do
        :application.start(:crypto)
        :application.start(:ranch)
        :application.start(:cowlib)
        :application.start(:cowboy)
         dispatch =
           [ for {url_path, sys_path} <- @statics do
               { "#{url_path}/[...]", :cowboy_static, {:dir, sys_path} }
             end,
             for m <- @socks do
               { "#{m.path}/[...]", m, [] }
             end,
             [{"/[...]", Lazymaru.Handler, %{mod: __MODULE__, hooks: @hooks}}]
           ] |> List.flatten
         dispatch = [{:_, dispatch}] |> :cowboy_router.compile
        :cowboy.start_http(Lazymaru.HTTP, 100, [port: @port], [env: [dispatch: dispatch]])
      end
    end
  end


  defmacro port(port_num) do
    quote do
      @port unquote(port_num)
    end
  end


  defmacro rest({_, _, mod}) do
    endpoints = Module.concat(mod).endpoints
    for i <- endpoints do
      quote do
        dispatch(unquote i)
      end
    end
  end


  defmacro sock({_, _, mod}) do
    m = Module.concat(mod)
    quote do
      @socks unquote(m)
    end
  end


  defmacro static(url_path, sys_path) do
    quote do
      @statics { unquote(url_path), unquote(sys_path) }
    end
  end


  defmacro hook({_, _, mod}) do
    m = Module.concat(mod)
    quote do
      @hooks unquote(m)
    end
  end


  defmacro map_params(n) when n < 0, do: []
  defmacro map_params(n) do
    Enum.map 0..n,
      fn(x) ->
          param_name = :"param_#{x}"
          quote do
            var!(unquote param_name)
          end
      end
  end


  def map_params_path(path), do: map_params_path(path, 0, [])
  def map_params_path([], _, r), do: r |> Enum.reverse
  def map_params_path([h|t], n, r) when is_atom(h) do
    new_path = quote do: var!(unquote :"param_#{n}")
    map_params_path(t, n+1, [new_path|r])
  end
  def map_params_path([h|t], n, r) do
    map_params_path(t, n, [h|r])
  end


  defmacro dispatch({method, path, params, [do: block], params_block}) do
    new_path = map_params_path(path)
    quote do
      def service(unquote(method), unquote(new_path), var!(unquote :conn)) do
        var!(:params) = [ unquote(params), map_params(unquote(length(params)-1))
                        ] |> List.zip |> Enum.into %{}
        unquote(params_block)
        unquote(block)
      end
    end
  end

end