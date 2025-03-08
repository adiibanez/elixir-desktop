defmodule Desktop.Endpoint do
  @doc false
  defmacro __using__(opts) do
    {scheme, opts} = Keyword.pop(opts, :desktop_scheme, :http)

    quote do
      use Phoenix.Endpoint, unquote(opts)
      defoverridable url: 0

      def url do
        url = super()
        scheme = unquote(scheme)

        case Keyword.get(config(scheme), :port, 0) do
          0 -> String.replace(url, ":0", ":#{get_dynamic_port(scheme)}") |> dbg()
          _port -> url |> dbg()
        end
      end

      def get_dynamic_port(scheme) do
        ref = Module.safe_concat(__MODULE__, scheme |> Atom.to_string() |> String.upcase())
        # :ranch.get_port(ref) |> dbg()
        4500
      end

      # if Version.match?(:phoenix |> Application.spec(:vsn) |> List.to_string(), "~> 1.7.10") do
      #   def get_dynamic_port(scheme) do
      #     {:ok, {_ip, port}} = server_info(scheme)
      #     port |> dbg()
      #   end
      # else
      #   # Supports only cowboy adapter for phoenix
      #   def get_dynamic_port(scheme) do
      #     ref = Module.safe_concat(__MODULE__, scheme |> Atom.to_string() |> String.upcase())
      #     :ranch.get_port(ref) |> dbg()
      #   end
      # end
    end
  end
end
