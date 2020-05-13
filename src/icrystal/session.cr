require "zeromq"
require "openssl/hmac"
require "uuid"
require "json"

module ICrystal
  class Message
    DELIM = "<IDS|MSG>"

    class_property! key : String?

    class Header
      include JSON::Serializable

      @[JSON::Field(key: "msg_id")]
      property id : String = UUID.random.to_s
      @[JSON::Field(key: "msg_type")]
      property type : String
      @[JSON::Field(key: "date")]
      property timestamp : String = Time::Format::ISO_8601_DATE_TIME.format(Time.local)
      property version : String = "5.3" # protocol version
      property username : String = "kernel"
      property session : String

      def initialize(@type, @session)
      end
    end

    alias Any = String | Int64 | Bool | Nil
    alias Dict = Hash(String, Any | Array(Any) | Hash(String, Any) | Array(Hash(String, Any)))

    property id : String
    property header : Header
    property parent_header : Header?
    property metadata = Dict.new
    property content : Dict

    def serialize
      ph = if parent_header = @parent_header
             parent_header.to_json
           else
             "{}"
           end

      msg = {@header.to_json, ph, @metadata.to_json, @content.to_json}
      signed = Message.sign(msg.join)

      {@id, DELIM, signed} + msg
    end

    def initialize(@id, @header, @content = Dict.new)
    end

    def initialize(@id, @header, @parent_header, @metadata, @content)
    end

    def self.sign(data)
      OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, self.key, data)
    end

    def self.deserialize(data)
      if data.size >= 6 && data[1] == DELIM
        id = data[0]

        signature = data[2]
        parts = data.values_at(3, 4, 5, 6)
        header, header2, metadata, content = parts

        if signature != self.sign(parts.join)
          raise "Invalid signature"
        end

        parent_header = header2 == "{}" ? nil : Header.from_json(header2)

        Message.new(id, Header.from_json(header), parent_header,
          Dict.from_json(metadata), Dict.from_json(content))
      else
        raise "Malformed message #{data}"
      end
    end
  end

  class Session
    private getter! heartbeat : ZMQ::Socket, iopub : ZMQ::Socket,
      stdin : ZMQ::Socket, shell : ZMQ::Socket

    getter context
    getter session_id = UUID.random
    @last_received_message : Message?

    def initialize(@config : Config)
      @context = ZMQ::Context.new

      if @config.signature_scheme != "hmac-sha256"
        raise "Unknown signature scheme #{@config.signature_scheme}"
      end

      setup_sockets
      setup_heartbeat
    end

    private def identifiers_for(msg_type, content)
      if msg_type == "stream"
        "stream.#{content["name"]}"
      else
        msg_type
      end
    end

    # sends a message over the iopub socket.
    def publish(msg_type, content)
      id = identifiers_for(msg_type, content)
      send(iopub, msg_type, id, content)
    end

    # sends a message over the shell socket.
    def send_reply(msg_type, content)
      id = if last_msg = @last_received_message
             last_msg.id
           else
             identifiers_for(msg_type, content)
           end

      send(shell, msg_type, id, content)
    end

    private def send(socket, msg_type, id, content)
      header = Message::Header.new(msg_type, @session_id.to_s)
      msg = Message.new(id, header, content)
      msg.parent_header = @last_received_message.try &.header
      data = msg.serialize

      Log.debug { "Send #{data}" }
      send_parts(socket, data)
    end

    private def send_parts(socket, data)
      data.each_with_index do |part, i|
        flags = i == data.size - 1 ? 0 : ZMQ::SNDMORE
        socket.send_string(part, flags)
      end
    end

    # receive a message from the shell socket
    def receive_reply
      data = shell.receive_strings
      @last_received_message = Message.deserialize(data)
    end

    # receive an input from the stdin socket
    def receive_input
      data = stdin.receive_strings
      Message.deserialize(data).content["value"]
    end

    private def setup_sockets
      @iopub = context.socket(ZMQ::PUB)
      @config.iopub_port = bind_socket(iopub, @config.iopub_port)

      @stdin = context.socket(ZMQ::ROUTER)
      @config.stdin_port = bind_socket(stdin, @config.stdin_port)

      @shell = context.socket(ZMQ::ROUTER)
      @config.shell_port = bind_socket(shell, @config.shell_port)
    end

    private def setup_heartbeat
      @heartbeat = @context.socket(ZMQ::REP)
      @config.hb_port = bind_socket(heartbeat, @config.hb_port)

      spawn heartbeat_loop
    end

    private def heartbeat_loop
      Log.debug { "Starting heartbeat loop..." }
      loop do
        msg = heartbeat.receive_string
        Log.debug { "💌" }
        heartbeat.send_string(msg)
        Fiber.yield
      end
      Log.debug { "Stopping heartbeat loop..." }
    end

    private def bind_socket(socket, port)
      port = if port <= 0
               bind_to_random_port(socket)
             else
               socket.bind("#{@config.transport}://#{@config.ip}:#{port}") ? port : nil
             end

      raise "could not bind socket" unless port
      port
    end

    private def bind_to_random_port(socket)
      max_tries = 500
      tries = 0
      binded = false

      while !binded && tries < max_tries
        tries += 1
        random = rand(55534) + 10_000
        binded = socket.bind "#{@config.transport}://#{@config.ip}:#{random}"
      end

      binded ? random : nil
    end
  end
end
