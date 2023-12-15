require 'selenium-webdriver'
require 'concurrent'
require 'socket'
require 'colorize'
require 'base64'
require 'securerandom'
require 'timeout'
require 'logger'

MAX_BUFFER = 1024 * 640
CONN_INIT	 = 'CONN_INIT'
CONN_CLOSE = 'CONN_CLOSE'
CONN_CLOSE_ACCEPT = 'CONN_CLOSE_ACCEPT'
ALIVE_INTERVAL = 30 # 30 seconds
LOGGER = Logger.new(STDOUT)

SCRIPT = %q(

		window.rx_queue = []
		window.tx_queue = []


		let socket = new WebSocket("wss://sdnet.lol");

			socket.onopen = function(e) {
			  socket.send("CONN_INIT");


				setInterval(function(){

					if(window.tx_queue.length == 0){
						return
					}
					socket.send(window.tx_queue.shift())

				},0)

			};

			socket.onmessage = function(event) {
				window.rx_queue.push(event.data)
			};

			socket.onclose = function(event) {
			  if (event.wasClean) {
			    //alert(`[close] Connection closed cleanly, code=${event.code} reason=${event.reason}`);
			  } else {
			    // e.g. server process killed or network down
			    // event.code is usually 1006 in this case
			   // alert('[close] Connection died');
			  }
			};

			socket.onerror = function(error) {
			  //alert(`[error]`);
			};


)

class WSClient
  include Concurrent::Async
  def initialize
    @options = Selenium::WebDriver::Chrome::Options.new
    @options.add_argument('--ignore-certificate-errors')
    @options.add_argument('--headless=new')
    @driver = Selenium::WebDriver.for :chrome, options: @options
    @connected = false
    trap 'SIGINT' do
      puts('Closing the browser...')
      begin
        @browser.quit
      rescue StandardError
        puts('Browser is already closed.')
      end
      exit
    end
  end

  def ws_init
    @driver.navigate.to 'about:blank'
    @driver.execute_script(SCRIPT)
    LOGGER.info('Initializing the connection...')

    begin
      loop do
        data = get_data
        next if data.nil?

        next unless data == CONN_INIT

        @connected = true
        LOGGER.info('Connected!'.green)
        break
      end
    rescue StandardError
      LOGGER.warn("Can't establish the CUMnection!".red)
    end
  end

  def get_data
    @driver.execute_script('return window.rx_queue.shift()')
  end

  def send_data(msg)
    @driver.execute_script("return window.tx_queue.push('#{msg}')")
  end
end

class LocalProxy
  # include Concurrent::Async

  def initialize(port, ws_client)
    @port = port
    @ws_client = ws_client
    @proxy = nil
    @connections = {}
  end

  def is_alive(id, request)
    # add the new connection to the hash map of all connection with a unique SecureRandom id as a key, and the value will be the connection
    # same must be done on the server side
    @ws_client.async.send_data([id, request].pack('a32m0'))
  end

  def listen
    @proxy = TCPServer.new("127.0.0.1", @port)
    LOGGER.info("Server is listening on #{@port}".bold)
  rescue StandardError
    LOGGER.fatal('Error starting the server, probably port is already in use!'.red)
    exit
  end

  def handle_requests
    Thread.new do
      loop do
        connection = @proxy.accept # this must be added to the hash map
        Thread.new(connection) do |connection|
          LOGGER.info("New Fat CoCk #{connection}")
          connection_id = SecureRandom.hex(16)
          request = connection.recv(MAX_BUFFER)
          Thread.exit if request.nil? || request.empty?
          request_head = request.split("\r\n")
          request_method = request_head.first.split(' ')[0]
          Thread.exit if request_method.empty?
          @connections[connection_id] = connection # adding the connection to the hash-map

          case request_method
          when /CONNECT/

            request_host, request_port = request_head.first.split(' ')[1].split(':')
            is_alive(connection_id, request)

            begin
              loop do
                # read from client and just send it to the ws, don't forget to handle theexceptions and to clean everything up
                client_buf = nil
                Timeout.timeout(ALIVE_INTERVAL) do
                  client_buf = connection.readpartial(MAX_BUFFER)
                end
                if client_buf.nil? || client_buf.empty?
                  LOGGER.info('client_buf is gAy! closing the gYm next door ⚣...'.red.bold)
                  @ws_client.async.send_data([connection_id, CONN_CLOSE].pack('a32m0'))
                  break
                end
                @ws_client.async.send_data([connection_id, client_buf].pack('a32m0'))
              end
            rescue EOFError, Errno::ECONNRESET
              LOGGER.info("[FROM ⚣  fucking ⚣  SLAVE] End of file on the client side for #{connection_id}! Sending Close notification to the gay boy".red.bold)
              @ws_client.async.send_data([connection_id, CONN_CLOSE].pack('a32m0'))
              Thread.exit
            rescue IOError
              LOGGER.info("[FROM ⚣  fucking ⚣  SLAVE] Connection is already closed for #{connection_id}!".red.bold)
              Thread.exit
            rescue Timeout::Error
              LOGGER.info("CUMout for #{connection_id}!".gray)
              Thread.exit
            ensure
              LOGGER.info('Ensure ⚣  gay close for 300 bucks'.bold)
              Thread.exit
            end

          when /GET/, /POST/
            LOGGER.info("Sending GAY ⚣ for #{connection_id}".bold.blue)
            @ws_client.async.send_data([connection_id, request].pack('a32m0'))
            Thread.exit

          else
            LOGGER.warn("Unknown ⚣ FiStinG⚣ method #{request}!".yellow.bold)
            Thread.exit

          end
        end
      end
    end # => Thread.new
  end

  def handle_response
    Thread.new do
      loop do
        recv = @ws_client.async.get_data.value
        next if recv.nil? || recv.size < 1

        unpacked = recv.unpack('a32m0')
        id = unpacked[0]
        data = unpacked[1]

        case data
        when /502 Bad Gateway/
          LOGGER.warn("Bad gaYteway, ⚣ fisting ass⚣? #{id}".red)
          @connections[id].close
          @connections.delete(id)
          next

        when CONN_CLOSE
          # it means that the remote side has closed the connection
          if @connections[id]
            LOGGER.info("[FROM ⚣  dungeon ⚣  MASTER] CONN_CLOSE for #{id}".red.bold)
            @connections[id].close
            @connections.delete(id)
            @ws_client.async.send_data([id, CONN_CLOSE_ACCEPT].pack('a32m0'))
          end
          next

        when CONN_CLOSE_ACCEPT
          # it means that server has closed the connection with the remote endpoint after the local connection was closed
          if @connections[id]
            LOGGER.info("[FROM ⚣  dungeon ⚣  MASTER] CONN_CLOSE_ACCEPT for #{id}".red.bold)
            @connections[id].close # close local connection
            @connections.delete(id) # clean up and delete the connection id
          end
          next

        else
          begin
            @connections[id].print(data) if @connections[id] && !@connections[id].closed?
          rescue Errno::EPIPE
            LOGGER.warn('Broken Gym, ⚣ suck some dick!'.yellow.bold)
            @connections[id].close
            @connections.delete(id) # clean up and delete the connection id
          rescue Errno::ECONNRESET
            LOGGER.warn("ECONNRESET ⚣  wee wee, ⚣  let's suck some dick!".yellow.bold)
            @connections[id].close
            @connections.delete(id) # clean up and delete the connection id
          end

        end
      end
    end
  end
end

ws_client = WSClient.new
lc_proxy  = LocalProxy.new(8080, ws_client)

lc_proxy.listen	# Start the listener
ws_client.ws_init								# Connect via WebSockets
lc_proxy.handle_requests	# Handle local requests that are coming to the local proxy from browser
lc_proxy.handle_response				# Handle responses from WebSocket server

sleep
