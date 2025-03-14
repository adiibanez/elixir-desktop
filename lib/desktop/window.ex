defmodule Desktop.Window do
  @moduledoc ~S"""
  Defines a Desktop Window.
  ... (rest of the original module documentation) ...
  """

  use WxEx
  alias Desktop.{OS, Window, Wx, Menu, Fallback}
  require Logger

  @enforce_keys [:frame]
  defstruct [
    :module,
    :taskbar,
    :frame,
    :notifications,
    :webview,
    :home_url,
    :last_url,
    :title
  ]

  @doc false
  def child_spec(opts) do
    Logger.debug("#{__MODULE__}.child_spec(opts: #{inspect(opts)})")
    app = Keyword.fetch!(opts, :app)
    id = Keyword.fetch!(opts, :id)

    spec = %{
      id: id,
      start: {__MODULE__, :start_link, [opts ++ [app: app, id: id]]}
    }

    Logger.debug("#{__MODULE__}.child_spec - Returning spec: #{inspect(spec)}")
    spec
  end

  @doc false
  def start_link(opts) do
    Logger.debug("#{__MODULE__}.start_link(opts: #{inspect(opts)})")
    id = Keyword.fetch!(opts, :id)
    {_ref, _num, _type, pid} = :wx_object.start_link({:local, id}, __MODULE__, opts, [])
    Logger.debug("#{__MODULE__}.start_link - Started with pid: #{inspect(pid)}")
    {:ok, pid}
  end

  @doc false
  def init(options) do
    Logger.debug("#{__MODULE__}.init(options: #{inspect(options)})")
    window_title = options[:title] || Atom.to_string(options[:id])
    size = options[:size] || {600, 500}
    min_size = options[:min_size]
    app = options[:app]
    icon = options[:icon]
    taskbar_icon = options[:taskbar_icon]
    # not supported on mobile atm
    menubar = unless OS.mobile?(), do: options[:menubar]
    icon_menu = unless OS.mobile?(), do: options[:icon_menu]
    hidden = unless OS.mobile?(), do: options[:hidden]
    url = options[:url]

    env = Desktop.Env.wx_env()
    GenServer.cast(Desktop.Env, {:register_window, self()})
    :wx.set_env(env)

    frame =
      :wxFrame.new(Desktop.Env.wx(), Wx.wxID_ANY(), window_title, [
        {:size, size},
        {:style, Wx.wxDEFAULT_FRAME_STYLE()}
      ])

    :wxFrame.connect(frame, :close_window,
      callback: &close_window/2,
      userData: self()
    )

    Logger.debug("#{__MODULE__}.init - Connected close_window event to frame: #{inspect(frame)}")

    if min_size do
      :wxFrame.setMinSize(frame, min_size)
      Logger.debug("#{__MODULE__}.init - Set minimum size to min_size: #{inspect(min_size)}")
    end

    :wxFrame.setSizer(frame, :wxBoxSizer.new(Wx.wxHORIZONTAL()))
    Logger.debug("#{__MODULE__}.init - Set horizontal box sizer for frame: #{inspect(frame)}")

    {:ok, icon} =
      case icon do
        nil ->
          icon = :wxArtProvider.getIcon("wxART_EXECUTABLE_FILE")

          Logger.debug(
            "#{__MODULE__}.init - Using default executable file icon: #{inspect(icon)}"
          )

          {:ok, icon}

        filename ->
          {:ok, icon} = Desktop.Image.new_icon(app, filename)

          Logger.debug(
            "#{__MODULE__}.init - Loaded custom icon from filename: #{inspect(filename)}, icon: #{inspect(icon)}"
          )

          {:ok, icon}
      end

    :wxTopLevelWindow.setIcon(frame, icon)
    Logger.debug("#{__MODULE__}.init - Set window icon to icon: #{inspect(icon)}")

    wx_menubar =
      if menubar do
        {:ok, menu_pid} =
          Menu.start_link(
            module: menubar,
            app: app,
            env: env,
            wx: :wxMenuBar.new()
          )

        Logger.debug("#{__MODULE__}.init - Started menubar with menu_pid: #{inspect(menu_pid)}")

        wx_menubar = Menu.menubar(menu_pid)
        :wxFrame.setMenuBar(frame, wx_menubar)
        Logger.debug("#{__MODULE__}.init - Set menubar on frame: #{inspect(frame)}")
        wx_menubar
      else
        nil
      end

    if OS.type() == MacOS do
      update_apple_menu(window_title, frame, wx_menubar || :wxMenuBar.new())
      Logger.debug("#{__MODULE__}.init - Updated macOS apple menu")
    end

    taskbar =
      if icon_menu do
        sni_link = Desktop.Env.sni()
        adapter = if sni_link != nil, do: Menu.Adapter.DBus

        {:ok, taskbar_icon} =
          case taskbar_icon do
            nil ->
              taskbar_icon = icon

              Logger.debug(
                "#{__MODULE__}.init - Using window icon for taskbar icon: #{inspect(taskbar_icon)}"
              )

              {:ok, taskbar_icon}

            filename ->
              {:ok, taskbar_icon} = Desktop.Image.new_icon(app, filename)

              Logger.debug(
                "#{__MODULE__}.init - Loaded custom taskbar icon from filename: #{inspect(filename)}, taskbar_icon: #{inspect(taskbar_icon)}"
              )

              {:ok, taskbar_icon}
          end

        {:ok, menu_pid} =
          Menu.start_link(
            module: icon_menu,
            app: app,
            adapter: adapter,
            env: env,
            sni: sni_link,
            icon: taskbar_icon,
            wx: {:taskbar, taskbar_icon}
          )

        Logger.debug(
          "#{__MODULE__}.init - Started taskbar menu with menu_pid: #{inspect(menu_pid)}"
        )

        menu_pid
      else
        nil
      end

    ui = %Window{
      frame: frame,
      webview: Fallback.webview_new(frame),
      notifications: %{},
      home_url: url,
      title: window_title,
      taskbar: taskbar
    }

    Logger.debug("#{__MODULE__}.init - Created UI struct: ui: #{inspect(ui)}")

    if hidden != true do
      show(self(), url)
      Logger.debug("#{__MODULE__}.init - Showing window (hidden=false), url: #{inspect(url)}")
    else
      Logger.debug("#{__MODULE__}.init - Window Hidden. Not showing.")
    end

    Logger.debug("#{__MODULE__}.init - Returning {frame: #{inspect(frame)}, ui: #{inspect(ui)}}")
    {frame, ui}
  end

  @doc """
  Returns the url currently shown of the Window.

    * `pid` - The pid or atom of the Window

  ## Examples

      iex> Desktop.Window.url(pid)
      http://localhost:1234/main

  """
  def url(pid) do
    Logger.debug("#{__MODULE__}.url(pid: #{inspect(pid)}) - Called")
    ret = GenServer.call(pid, :url)
    Logger.debug("#{__MODULE__}.url(pid: #{inspect(pid)}) - Returning ret: #{inspect(ret)}")
    ret
  end

  @doc """
  Show the Window if not visible with the given url.

    * `pid` - The pid or atom of the Window
    * `url` - The endpoint url to show. If non is provided
      the url callback will be used to get one.

  ## Examples

      iex> Desktop.Window.show(pid, "/")
      :ok

  """
  def show(pid, url \\ nil) do
    Logger.debug("#{__MODULE__}.show(pid: #{inspect(pid)}, url: #{inspect(url)}) - Called")
    GenServer.cast(pid, {:show, url})
    Logger.debug("#{__MODULE__}.show(pid: #{inspect(pid)}, url: #{inspect(url)}) - Cast sent")
    # Added for consistency
    :ok
  end

  @doc """
  Hide the Window if visible (noop on mobile platforms)

    * `pid` - The pid or atom of the Window

  ## Examples

      iex> Desktop.Window.hide(pid)
      :ok

  """
  def hide(pid) do
    Logger.debug("#{__MODULE__}.hide(pid: #{inspect(pid)}) - Called")
    GenServer.cast(pid, :hide)
    Logger.debug("#{__MODULE__}.hide(pid: #{inspect(pid)}) - Cast sent")
    # Added for consistency
    :ok
  end

  @doc """
  Returns true if the window is hidden. Always returns false
  on mobile platforms.

    * `pid` - The pid or atom of the Window

  ## Examples

      iex> Desktop.Window.is_hidden?(pid)
      false

  """
  def hidden?(pid) do
    Logger.debug("#{__MODULE__}.hidden?(pid: #{inspect(pid)}) - Called")
    ret = GenServer.call(pid, :is_hidden?)
    Logger.debug("#{__MODULE__}.hidden?(pid: #{inspect(pid)}) - Returning ret: #{inspect(ret)}")
    ret
  end

  @doc false
  @deprecated "Use hidden?/1 instead"
  # credo:disable-for-next-line
  def is_hidden?(pid) do
    hidden?(pid)
  end

  @doc """
  Returns true if the window is active. Always returns true
  on mobile platforms.

    * `pid` - The pid or atom of the Window

  ## Examples

      iex> Desktop.Window.is_active?(pid)
      false

  """
  def active?(pid) do
    Logger.debug("#{__MODULE__}.active?(pid: #{inspect(pid)}) - Called")
    ret = GenServer.call(pid, :is_active?)
    Logger.debug("#{__MODULE__}.active?(pid: #{inspect(pid)}) - Returning ret: #{inspect(ret)}")
    ret
  end

  @doc false
  @deprecated "Use active?/1 instead"
  # credo:disable-for-next-line
  def is_active?(pid) do
    active?(pid)
  end

  @doc """
  Set the windows title

    * `pid` - The pid or atom of the Window
    * `title` - The new windows title

  ## Examples

      iex> Desktop.Window.set_title(pid, "New Window Title")
      :ok

  """
  def set_title(pid, title) do
    Logger.debug(
      "#{__MODULE__}.set_title(pid: #{inspect(pid)}, title: #{inspect(title)}) - Called"
    )

    GenServer.cast(pid, {:set_title, title})

    Logger.debug(
      "#{__MODULE__}.set_title(pid: #{inspect(pid)}, title: #{inspect(title)}) - Cast sent"
    )

    # Added for consistency
    :ok
  end

  @doc """
  Iconize or restore the window

    * `pid` - The pid or atom of the Window
    * `restore` - Optional defaults to false whether the
                  window should be restored
  """
  def iconize(pid, iconize \\ true) do
    Logger.debug(
      "#{__MODULE__}.iconize(pid: #{inspect(pid)}, iconize: #{inspect(iconize)}) - Called"
    )

    GenServer.cast(pid, {:iconize, iconize})

    Logger.debug(
      "#{__MODULE__}.iconize(pid: #{inspect(pid)}, iconize: #{inspect(iconize)}) - Cast sent"
    )

    # Added for consistency
    :ok
  end

  @doc """
  Rebuild the webview. This function is a troubleshooting
  function at this time. On Windows it's sometimes necessary
  to rebuild the WebView2 frame.

    * `pid` - The pid or atom of the Window

  ## Examples

      iex> Desktop.Window.rebuild_webview(pid)
      :ok

  """
  def rebuild_webview(pid) do
    Logger.debug("#{__MODULE__}.rebuild_webview(pid: #{inspect(pid)}) - Called")
    GenServer.cast(pid, :rebuild_webview)
    Logger.debug("#{__MODULE__}.rebuild_webview(pid: #{inspect(pid)}) - Cast sent")
    # Added for consistency
    :ok
  end

  @doc """
  Fetch the underlying :wxWebView instance object. Call
  this if you have to use more advanced :wxWebView functions
  directly on the object.

    * `pid` - The pid or atom of the Window

  ## Examples

      iex> :wx.set_env(Desktop.Env.wx_env())
      iex> :wxWebView.isContextMenuEnabled(Desktop.Window.webview(pid))
      false

  """
  def webview(pid) do
    Logger.debug("#{__MODULE__}.webview(pid: #{inspect(pid)}) - Called")
    webview = GenServer.call(pid, :webview)

    Logger.debug(
      "#{__MODULE__}.webview(pid: #{inspect(pid)}) - Returning webview: #{inspect(webview)}"
    )

    webview
  end

  @doc """
  Fetch the underlying :wxFrame instance object. This represents
  the window which the webview is drawn into.

    * `pid` - The pid or atom of the Window

  ## Examples

      iex> :wx.set_env(Desktop.Env.wx_env())
      iex> :wxWindow.show(Desktop.Window.frame(pid), show: false)
      false

  """
  def frame(pid) do
    Logger.debug("#{__MODULE__}.frame(pid: #{inspect(pid)}) - Called")
    frame = GenServer.call(pid, :frame)
    Logger.debug("#{__MODULE__}.frame(pid: #{inspect(pid)}) - Returning frame: #{inspect(frame)}")
    frame
  end

  @doc """
  Show a desktop notification

    * `pid` - The pid or atom of the Window

    * `text` - The text content to show in the notification

    * `opts` - Additional notification options

      Valid keys are:

        * `:id` - An id for the notification, this is important if you
          want control, the visibility of the notification. The default
          value when none is provided is `:default`

        * `:type` - One of `:info` `:error` `:warn` these will change
          how the notification will be displayed. The default is `:info`

        * `:title` - An alternative title for the notificaion,
          when none is provided the current window title is used.

        * `:timeout` - A timeout hint specifying how long the notification
          should be displayed.

          Possible values are:

            * `:auto` - This is the default and let's the OS decide

            * `:never` - Indicates that notification should not be hidden
              automatically

            * ms - A time value in milliseconds, how long the notification
              should be shown

        * `:callback` - A function to be executed when the user clicks on the
          notification.

  ## Examples

      iex> :wx.set_env(Desktop.Env.wx_env())
      iex> :wxWebView.isContextMenuEnabled(Desktop.Window.webview(pid))
      false

  """
  def show_notification(pid, text, opts \\ []) do
    Logger.debug(
      "#{__MODULE__}.show_notification(pid: #{inspect(pid)}, text: #{inspect(text)}, opts: #{inspect(opts)}) - Called"
    )

    id = Keyword.get(opts, :id, :default)

    type =
      case Keyword.get(opts, :type, :info) do
        :info -> :info
        :error -> :error
        :warn -> :warning
        :warning -> :warning
      end

    title = Keyword.get(opts, :title, nil)

    timeout =
      case Keyword.get(opts, :timeout, :auto) do
        :auto -> -1
        :never -> 0
        ms when is_integer(ms) -> ms
      end

    callback = Keyword.get(opts, :callback, nil)
    GenServer.cast(pid, {:show_notification, text, id, type, title, callback, timeout})

    Logger.debug(
      "#{__MODULE__}.show_notification - Cast sent (pid: #{inspect(pid)}, text: #{inspect(text)}, id: #{inspect(id)}, type: #{inspect(type)}, title: #{inspect(title)}, callback: #{inspect(callback)}, timeout: #{inspect(timeout)})"
    )

    # Added for consistency
    :ok
  end

  @doc """
  Quit the application. This forces a quick termination which can
  be helpful on MacOS/Windows as sometimes the destruction is
  crashing.
  """
  def quit() do
    Logger.debug("#{__MODULE__}.quit() - Called")
    OS.shutdown()
    Logger.debug("#{__MODULE__}.quit() - OS shutdown called")
  end

  # require Record

  # for tag <- [:wx, :wxCommand, :wxClose] do
  #   Record.defrecordp(tag, Record.extract(tag, from_lib: "wx/include/wx.hrl"))
  # end

  @doc false
  def handle_event(wx(event: {:wxWebView, :webview_newwindow, _, _, _target, url}), ui) do
    Logger.debug("#{__MODULE__}.handle_event(webview_newwindow, url: #{inspect(url)}) - Called")
    OS.launch_default_browser(url)

    Logger.debug(
      "#{__MODULE__}.handle_event(webview_newwindow, url: #{inspect(url)}) - Browser launched"
    )

    {:noreply, ui}
  end

  def handle_event(error = wx(event: {:wxWebView, :webview_error, _, _, _target, _url}), ui) do
    Logger.error("wxWebView error: error: #{inspect(error)}, ui: #{inspect(ui)}")
    {:noreply, ui}
  end

  def handle_event(wx(id: id, event: wxCommand(type: :command_menu_selected)), ui) do
    Logger.debug("#{__MODULE__}.handle_event(command_menu_selected, id: #{inspect(id)}) - Called")

    if id == Wx.wxID_EXIT() do
      quit()
    end

    {:noreply, ui}
  end

  def handle_event(wx(obj: obj, event: wxCommand(type: :notification_message_click)), ui) do
    Logger.debug(
      "#{__MODULE__}.handle_event(notification_message_click, obj: #{inspect(obj)}) - Called"
    )

    notification(ui, obj, :click)
    {:noreply, ui}
  end

  def handle_event(wx(obj: obj, event: wxCommand(type: :notification_message_dismissed)), ui) do
    Logger.debug(
      "#{__MODULE__}.handle_event(notification_message_dismissed, obj: #{inspect(obj)}) - Called"
    )

    notification(ui, obj, :dismiss)

    if OS.type() == Linux do
      notification(ui, obj, :action)
    else
      notification(ui, obj, :dismiss)
    end

    {:noreply, ui}
  end

  def handle_event(
        wx(obj: obj, event: wxCommand(commandInt: action, type: :notification_message_action)),
        ui
      ) do
    Logger.debug(
      "#{__MODULE__}.handle_event(notification_message_action, obj: #{inspect(obj)}, action: #{inspect(action)}) - Called"
    )

    notification(ui, obj, {:action, action})
    {:noreply, ui}
  end

  defp notification(%Window{notifications: noties}, obj, action) do
    Logger.debug(
      "#{__MODULE__}.notification(obj: #{inspect(obj)}, action: #{inspect(action)}, notifications: #{inspect(noties)}) - Called"
    )

    case Enum.find(noties, fn {_, {wx_ref, _callback}} -> wx_ref == obj end) do
      nil ->
        Logger.error(
          "Received unhandled notification event obj: #{inspect(obj)}, action: #{inspect(action)}, noties: #{inspect(noties)}"
        )

      {_, {_ref, nil}} ->
        :ok

      {_, {_ref, callback}} ->
        spawn(fn -> callback.(action) end)
    end

    Logger.debug("#{__MODULE__}.notification - Returning")
  end

  def close_window(wx(userData: pid), inev) do
    Logger.debug(
      "#{__MODULE__}.close_window(pid: #{inspect(pid)}, inev: #{inspect(inev)}) - Called"
    )

    # if we don't veto vetoable events on MacOS the app freezes.
    if :wxCloseEvent.canVeto(inev) do
      :wxCloseEvent.veto(inev)
      Logger.debug("#{__MODULE__}.close_window - Close event vetoed")
    end

    GenServer.cast(pid, :close_window)
    Logger.debug("#{__MODULE__}.close_window - Cast sent")
    # Added for consistency
    :ok
  end

  @doc false
  def handle_cast(:close_window, ui = %Window{frame: frame, taskbar: taskbar}) do
    Logger.debug("#{__MODULE__}.handle_cast(:close_window, ui: #{inspect(ui)}) - Called")
    # On macOS, there's no way to differentiate between following two events:
    #
    # * the window close event
    # * the application close event
    #
    # So, this code assumes that if there's a closet_window event coming in while
    # the window in not actually shown, then it must be an application close event.
    #
    # On other platforms, this code should not have any relevance.
    if not :wxFrame.isShown(frame) do
      OS.shutdown()

      Logger.debug(
        "#{__MODULE__}.handle_cast(:close_window) - Frame not shown, calling OS.shutdown()"
      )
    end

    if taskbar == nil do
      OS.shutdown()

      Logger.debug(
        "#{__MODULE__}.handle_cast(:close_window) - Taskbar is nil, calling OS.shutdown()"
      )

      {:noreply, ui}
    else
      :wxFrame.hide(frame)
      Logger.debug("#{__MODULE__}.handle_cast(:close_window) - Hiding frame")
      {:noreply, ui}
    end
  end

  def handle_cast({:set_title, title}, ui = %Window{title: old, frame: frame}) do
    Logger.debug("#{__MODULE__}.handle_cast({:set_title, title: #{inspect(title)}}) - Called")

    if title != old and frame != nil do
      :wxFrame.setTitle(frame, String.to_charlist(title))

      Logger.debug(
        "#{__MODULE__}.handle_cast({:set_title, title: #{inspect(title)}}) - Title set on frame"
      )
    end

    {:noreply, %Window{ui | title: title}}
  end

  def handle_cast({:iconize, iconize}, ui = %Window{frame: frame}) do
    Logger.debug("#{__MODULE__}.handle_cast({:iconize, iconize: #{inspect(iconize)}}) - Called")
    :wxTopLevelWindow.iconize(frame, iconize: iconize)
    Logger.debug("#{__MODULE__}.handle_cast({:iconize, iconize: #{inspect(iconize)}}) - Iconized")
    {:noreply, ui}
  end

  def handle_cast(:rebuild_webview, ui) do
    Logger.debug("#{__MODULE__}.handle_cast(:rebuild_webview, ui: #{inspect(ui)}) - Called")
    {:noreply, %Window{ui | webview: Fallback.webview_rebuild(ui)}}
  end

  def handle_cast(
        {:show_notification, message, id, type, title, callback, timeout},
        ui = %Window{notifications: noties, title: window_title}
      ) do
    Logger.debug(
      "#{__MODULE__}.handle_cast({:show_notification, message: #{inspect(message)}, id: #{inspect(id)}, type: #{inspect(type)}, title: #{inspect(title)}, callback: #{inspect(callback)}, timeout: #{inspect(timeout)}}) - Called"
    )

    {n, _} =
      note =
      case Map.get(noties, id, nil) do
        nil ->
          Logger.debug(
            "#{__MODULE__}.handle_cast(:show_notification) - Creating new notification (id: #{inspect(id)})"
          )

          {Fallback.notification_new(title || window_title, type), callback}

        {note, _} ->
          Logger.debug(
            "#{__MODULE__}.handle_cast(:show_notification) - Reusing existing notification (id: #{inspect(id)})"
          )

          {note, callback}
      end

    Fallback.notification_show(n, message, timeout, title || window_title)

    Logger.debug(
      "#{__MODULE__}.handle_cast(:show_notification) - Notification shown (n: #{inspect(n)}, message: #{inspect(message)}, timeout: #{inspect(timeout)}, title: #{inspect(title || window_title)})"
    )

    noties = Map.put(noties, id, note)
    {:noreply, %Window{ui | notifications: noties}}
  end

  def handle_cast({:show, url}, ui = %Window{home_url: home, last_url: last}) do
    Logger.debug("#{__MODULE__}.handle_cast({:show, url: #{inspect(url)}}) - Called")
    new_url = prepare_url(url || last || home)
    Logger.info("Showing new_url: #{inspect(new_url)}")
    Fallback.webview_show(ui, new_url, url == nil)

    Logger.debug(
      "#{__MODULE__}.handle_cast({:show, url: #{inspect(url)}}) - WebView shown, last_url updated to new_url: #{inspect(new_url)}"
    )

    {:noreply, %Window{ui | last_url: new_url}}
  end

  def handle_cast(:hide, ui = %Window{frame: frame}) do
    Logger.debug("#{__MODULE__}.handle_cast(:hide, ui: #{inspect(ui)}) - Called")

    if frame do
      :wxWindow.hide(frame)
      Logger.debug("#{__MODULE__}.handle_cast(:hide) - Frame hidden")
    end

    {:noreply, ui}
  end

  @doc false
  def handle_call(:is_hidden?, _from, ui = %Window{frame: frame}) do
    Logger.debug("#{__MODULE__}.handle_call(:is_hidden?, ui: #{inspect(ui)}) - Called")

    ret =
      if frame do
        ret = not :wxWindow.isShown(frame)

        Logger.debug(
          "#{__MODULE__}.handle_call(:is_hidden?) - Frame is shown: #{inspect(not ret)}, Returning ret: #{inspect(ret)}"
        )

        ret
      else
        Logger.warn("#{__MODULE__}.handle_call(:is_hidden?) - No frame, returning false")
        false
      end

    {:reply, ret, ui}
  end

  @doc false
  def handle_call(:is_active?, _from, ui = %Window{frame: frame}) do
    Logger.debug("#{__MODULE__}.handle_call(:is_active?, ui: #{inspect(ui)}) - Called")
    ret = :wxTopLevelWindow.isActive(frame)
    Logger.debug("#{__MODULE__}.handle_call(:is_active?) - Returning ret: #{inspect(ret)}")
    {:reply, ret, ui}
  end

  def handle_call(:url, _from, ui) do
    Logger.debug("#{__MODULE__}.handle_call(:url, ui: #{inspect(ui)}) - Called")

    ret =
      case Fallback.webview_url(ui) do
        url when is_list(url) ->
          url_string = List.to_string(url)

          Logger.debug(
            "#{__MODULE__}.handle_call(:url) - URL is a list, converting to string: url_string: #{inspect(url_string)}"
          )

          url_string

        other ->
          Logger.debug(
            "#{__MODULE__}.handle_call(:url) - URL is not a list: other: #{inspect(other)}"
          )

          other
      end

    Logger.debug("#{__MODULE__}.handle_call(:url) - Returning ret: #{inspect(ret)}")
    {:reply, ret, ui}
  end

  def handle_call(:webview, _from, ui = %Window{webview: webview}) do
    Logger.debug("#{__MODULE__}.handle_call(:webview, ui: #{inspect(ui)}) - Called")

    Logger.debug(
      "#{__MODULE__}.handle_call(:webview) - Returning webview instance webview: #{inspect(webview)}"
    )

    {:reply, webview, ui}
  end

  def handle_call(:frame, _from, ui = %Window{frame: frame}) do
    Logger.debug("#{__MODULE__}.handle_call(:frame, ui: #{inspect(ui)}) - Called")

    Logger.debug(
      "#{__MODULE__}.handle_call(:frame) - Returning frame instance frame: #{inspect(frame)}"
    )

    {:reply, frame, ui}
  end

  def prepare_url(url) when is_function(url) do
    Logger.debug("#{__MODULE__}.prepare_url(url: function) - Called")
    ret = prepare_url(url.())
    Logger.debug("#{__MODULE__}.prepare_url(url: function) - Returning ret: #{inspect(ret)}")
    ret
  end

  def prepare_url(nil) do
    Logger.debug("#{__MODULE__}.prepare_url(nil) - Called")
    # returning nil
    nil
  end

  def prepare_url(url) when is_binary(url) do
    Logger.debug("#{__MODULE__}.prepare_url(url: #{inspect(url)}) - Called")
    query = %{"k" => Desktop.Auth.login_key()}
    uri = URI.parse(url)

    case uri do
      %URI{query: nil} ->
        new_query = URI.encode_query(query)

        Logger.debug(
          "#{__MODULE__}.prepare_url - No existing query params, adding new_query: #{inspect(new_query)}"
        )

        new_uri = %URI{uri | query: new_query}
        ret = URI.to_string(new_uri)
        Logger.debug("#{__MODULE__}.prepare_url - Returning ret: #{inspect(ret)}")
        ret

      %URI{query: other} ->
        merged_query = Map.merge(URI.decode_query(other), query)
        new_query = URI.encode_query(merged_query)

        Logger.debug(
          "#{__MODULE__}.prepare_url - Merging existing query with new_query: #{inspect(new_query)}"
        )

        new_uri = %URI{uri | query: new_query}
        ret = URI.to_string(new_uri)
        Logger.debug("#{__MODULE__}.prepare_url - Returning ret: #{inspect(ret)}")
        ret
    end
  end

  defp update_apple_menu(title, frame, menubar) do
    Logger.debug(
      "#{__MODULE__}.update_apple_menu(title: #{inspect(title)}, frame: #{inspect(frame)}, menubar: #{inspect(menubar)}) - Called"
    )

    menu = :wxMenuBar.oSXGetAppleMenu(menubar)
    :wxMenu.setTitle(menu, title)

    Logger.debug(
      "#{__MODULE__}.update_apple_menu - Set apple menu title to title: #{inspect(title)}"
    )

    # Remove all items except for Quit since we don't yet handle the standard items
    # like "Hide <app>", "Hide Others", "Show All", etc
    for item <- :wxMenu.getMenuItems(menu) do
      if :wxMenuItem.getId(item) == Wx.wxID_EXIT() do
        :wxMenuItem.setText(item, "Quit #{title}\tCtrl+Q")
        Logger.debug("#{__MODULE__}.update_apple_menu - Set Quit menu item text")
      else
        :wxMenu.delete(menu, item)
        Logger.debug("#{__MODULE__}.update_apple_menu - Deleted menu item: #{inspect(item)}")
      end
    end

    Logger.debug("#{__MODULE__}.update_apple_menu - Finished updating apple menu")

    :wxFrame.connect(frame, :command_menu_selected)
  end
end
