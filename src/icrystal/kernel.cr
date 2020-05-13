require "uuid"

Log.setup_from_env

module ICrystal
  class Config
    include JSON::Serializable

    def initialize
    end

    property control_port : Int32 = 0
    property hb_port : Int32 = 0
    property iopub_port : Int32 = 0
    property shell_port : Int32 = 0
    property stdin_port : Int32 = 0

    property ip : String = "127.0.0.1"
    property transport : String = "tcp"

    property key : String = UUID.random.to_s
    property signature_scheme : String = "hmac-sha256"
  end

  class Kernel
    alias Any = Message::Any

    @running = false

    def initialize(config_file)
      @config = if config_file
                  Config.from_json(File.read(config_file))
                else
                  Config.new
                end
      @execution_count = 0i64

      Log.debug { "Initializing ICrystal kernel..." }
      Log.debug { @config.inspect }

      Message.key = @config.key
      @session = Session.new(@config)
      @backend = ICRBackend.new
    end

    def run
      Log.debug { "Starting ICrystal kernel..." }
      @running = true

      send_status "starting"
      while @running
        msg = @session.receive_reply
        Log.debug { "Received #{msg.inspect}" }
        type = msg.header.type

        begin
          send_status "busy"
          handle_request(type, msg)
        ensure
          send_status "idle"
        end

        Fiber.yield
      end
    rescue e
      Log.error { "Kernel error: #{e.message}\n#{e.backtrace.join('\n')}" }
      @session.publish "error", error_content(e)
    ensure
      Log.debug { "Stopping ICrystal kernel..." }
    end

    def handle_request(type, msg)
      case type
      when "kernel_info_request" then send_kernel_info
      when "connect_request"     then send_connect_info # deprecated in protocol v5.1
      when "shutdown_request"    then shutdown(msg)
      when "history_request"     then send_history
      when "is_complete_request" then send_is_complete(msg)
      when "complete_request"    then send_complete(msg)
      when "inspect_request"     then inspect_request
      when "execute_request"     then execute_request(msg)
      when "comm_open"           then comm_open(msg)
      when "comm_msg"            then comm_msg(msg)
      when "comm_close"          then comm_close(msg)
      when "comm_info_request"   then send_comm_info(msg)
      else
        if type =~ /comm_|_request\Z/
          Log.debug { "Message type '#{type}' not handled" }
        else
          raise "Unknown message type"
        end
      end
    end

    def build_content(**kwargs)
      Message::Dict.new.tap do |content|
        kwargs.each do |k, v|
          content[k.to_s] = v
        end
      end
    end

    def build_hash(**kwargs)
      Hash(String, Any).new.tap do |hash|
        kwargs.each do |k, v|
          hash[k.to_s] = v
        end
      end
    end

    def error_content(e)
      build_content(
        status: "error",
        ename: e.class.to_s,
        evalue: e.message || "",
        traceback: e.backtrace.map &.as(Any)
      )
    end

    def send_status(status)
      @session.publish "status", build_content(execution_state: status)
    end

    def shutdown(msg)
      @session.send_reply "shutdown_reply", msg.content
      @running = false
    end

    def send_history
      # not implemented yet
      @session.send_reply "history_reply", build_content(history: [] of Any)
    end

    def inspect_request
      # not implemented yet

      @session.send_reply("inspect_reply", build_content(
        status: "ok",
        found: "false",
        data: {} of String => Any,
        metadata: {} of String => Any
      ))
    end

    # deprecated in protocol v5.1
    def send_connect_info
      @session.send_reply("connect_reply", build_content(
        shell_port: @config.shell_port.to_i64,
        iopub_port: @config.iopub_port.to_i64,
        stdin_port: @config.stdin_port.to_i64,
        hb_port: @config.hb_port.to_i64
      ))
    end

    def send_kernel_info
      content = build_content(
        protocol_version: "5.3",
        implementation: "icrystal",
        implementation_version: ICrystal::VERSION,
        language_info: build_hash(
          name: "Crystal",
          version: Crystal::VERSION,
          mimetype: "text/x-crystal",
          file_extension: ".cr"
        ),
        banner: "ICrystal #{ICrystal::VERSION}",
        help_links: [
          build_hash(
            text: "Crystal documentation",
            url: "https://crystal-lang.org/reference"
          ),
          build_hash(
            text: "Crystal API",
            url: "https://crystal-lang.org/api"
          ),
        ],
        status: "ok"
      )

      @session.send_reply "kernel_info_reply", content
    end

    def send_is_complete(msg)
      content = Message::Dict.new

      code = msg.content["code"].as(String)
      result = @backend.check_syntax(code)

      content["status"] = case result.status
                          when :ok
                            "complete"
                          when :unexpected_eof, :unterminated_literal
                            "incomplete"
                          when :error
                            "invalid"
                          else
                            "unknown"
                          end

      @session.send_reply "is_complete_reply", content
    end

    def send_complete(msg)
      # not implemented yet

      content = build_content(
        status: "ok",
        matches: [] of Any,
        cursod_start: msg.content["cursor_pos"],
        cursor_end: msg.content["cursor_pos"],
        metadata: {} of String => Any
      )

      @session.send_reply "is_complete_reply", content
    end

    def execute_request(msg)
      code = msg.content["code"].as(String)
      store_history = msg.content["store_history"].as(Bool)
      silent = msg.content["silent"].as(Bool)

      @execution_count += 1 if store_history
      @session.publish("execute_input", build_content(
        code: code,
        execution_count: @execution_count
      ))

      content = build_content(
        status: "ok",
        payload: [] of Any,
        user_expressions: {} of String => Any,
        execution_count: @execution_count
      )

      result = @backend.eval(code, store_history)

      output = nil

      if result.is_a?(Icr::ExecutionResult)
        if result.success?
          output = result.output
          if (value = result.value) && !value.includes?("nil")
            output = if output.nil? || output.empty?
                       value
                     else
                       "#{output}\n#{value}"
                     end
          end
        else
          content["status"] = "error"
          output = result.error_output || ""
          @session.publish "error", content
        end
      else
        if exception = result.err
          content = error_content(exception)
          content["execution_count"] = @execution_count
          @session.publish "error", content
        end
      end

      @session.send_reply "execute_reply", content

      unless silent
        @session.publish("execute_result", build_content(
          data: build_hash("text/plain": output),
          metadata: {} of String => Any,
          execution_count: @execution_count
        ))
      end
    end

    def comm_open(msg)
    end

    def comm_msg(msg)
    end

    def comm_close(msg)
    end

    def send_comm_info(msg)
      @session.send_reply "comm_info_reply", build_content(
        comms: {} of String => Any
      )
    end
  end
end
