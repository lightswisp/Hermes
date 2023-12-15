require "websocket-eventmachine-server"
require "socket"
require "openssl"
require "colorize"
require "timeout"

CONN_INIT	= "CONN_INIT"
SERVER_NAME = "WSTunnel"
CONN_OK = "HTTP/1.1 200 Established\r\nDate: #{Time.now}\r\nServer: #{SERVER_NAME}\r\n\r\n"
CONN_FAIL = "HTTP/1.1 502 Bad Gateway\r\nDate: #{Time.now}\r\nServer: #{SERVER_NAME}\r\n\r\n<h1>502 Bad Gateway</h1>"
CONN_CLOSE = "CONN_CLOSE"
CONN_CLOSE_ACCEPT = "CONN_CLOSE_ACCEPT"
MAX_BUFFER = 1024 * 640

ALIVE_INTERVAL = 30 # 30 seconds

CONNECTIONS = {}


class RemoteConnectionHandler

	def initialize(ws, id, endpoint_connection)
		@ws = ws
		@endpoint_connection = endpoint_connection
		@id = id
	end

	def handle_http(data)
		Thread.new do

			@endpoint_connection.puts(data)

			begin
				loop do
					endpoint_buf = nil
					Timeout::timeout(ALIVE_INTERVAL) {
						endpoint_buf = @endpoint_connection.readpartial(MAX_BUFFER)
					}
					if endpoint_buf.nil? || endpoint_buf.empty?
						puts "endpoint_buf is empty! closing the thread...".red.bold
						@ws.send([@id, CONN_CLOSE].pack("a32m0"))
						break
					end
					@ws.send([@id, endpoint_buf].pack("a32m0"))
				end
			rescue EOFError, Errno::ECONNRESET
				puts "Connection is closed by the remote server for #{@id}!".red
				@ws.send([@id, CONN_CLOSE].pack("a32m0"))
				Thread.exit
			rescue IOError
				puts "Connection is already closed for #{@id}!".red
				Thread.exit
			rescue Timeout::Error
				puts "Timeout for #{@id}!".red.bold
				Thread.exit
			ensure
				puts "Ensure close".bold.red
				Thread.exit
			end


		  # @endpoint_connection.puts(data)
		  # endpoint_buf = @endpoint_connection.readpartial(MAX_BUFFER)
			# @ws.send([@id, endpoint_buf].pack("a32m0"))
			# @endpoint_connection.close
			# @ws.send([@id, CONN_CLOSE].pack("a32m0"))
			# Thread.exit

			
		end
	end

	def handle_https()
	
		Thread.new do
		
			begin
				loop do
					endpoint_buf = nil
					Timeout::timeout(ALIVE_INTERVAL) {
						endpoint_buf = @endpoint_connection.readpartial(MAX_BUFFER)
					}
					if endpoint_buf.nil? || endpoint_buf.empty?
						puts "endpoint_buf is empty! closing the thread...".red.bold
						@ws.send([@id, CONN_CLOSE].pack("a32m0"))
						break
					end
					@ws.send([@id, endpoint_buf].pack("a32m0"))
					
				end
			rescue EOFError, Errno::ECONNRESET
				puts "Connection is closed by the remote server for #{@id}!".red
				@ws.send([@id, CONN_CLOSE].pack("a32m0"))
				Thread.exit
			rescue IOError
				puts "Connection is already closed for #{@id}!".red
				Thread.exit
			rescue Timeout::Error
				puts "Timeout for #{@id}!".red.bold
				Thread.exit
			ensure
				puts "Ensure close".bold.red
				Thread.exit
			end
			
		end

	end
end

EM.run do

  WebSocket::EventMachine::Server.start(
        :host => "0.0.0.0", 
        :port => 443, 
        :secure => true,
        :tls_options => {
      :private_key_file => "private.key",
      :cert_chain_file => "certificate.crt",
     }) do |ws|
      
    ws.onopen do
      puts "Client connected"
    end

    ws.onmessage do |request, type|
      #puts "Received message: #{request}"
      if request == CONN_INIT
      	ws.send request, :type => type
      else
      	begin
      	request = request.unpack("a32m0")
      	rescue ArgumentError
					ws.send "Error, malformed request!"
					next
      	end
      	id = request[0]
      	data = request[1]

      	if id.empty? || data.empty?
					ws.send "Error, data or id are empty!"
					next
      	end

      	if data[0...3] == "GET" || data[0...4] == "POST"
		   		request_split = data.split("\r\n")
				  host = request_split[1].downcase.gsub('host:', '').strip
			    endpoint_host, endpoint_port = host.split(':')
			    endpoint_port = 80 if endpoint_port.nil?
			    endpoint_port = endpoint_port.to_i

			    begin
			    	# `initialize': string contains null byte (ArgumentError)
			    
						endpoint_connection = TCPSocket.new(endpoint_host, endpoint_port)
			    rescue Errno::ENETUNREACH, Errno::ECONNREFUSED, SocketError, Errno::ETIMEDOUT
						ws.send([id, CONN_FAIL].pack("a32m0"))
						next
			    end

		    	handler = RemoteConnectionHandler.new(ws, id, endpoint_connection)
		     	handler.handle_http(data)

				elsif data[0...7] == "CONNECT"

					request_split = data.split("\r\n")
					endpoint_host, endpoint_port = request_split.first.split(' ')[1].split(':')
					
					begin
						endpoint_connection = TCPSocket.new(endpoint_host, endpoint_port)

					rescue Errno::ENETUNREACH, Errno::ECONNREFUSED, SocketError, Errno::ETIMEDOUT
						ws.send([id, CONN_FAIL].pack("a32m0"))
						next
					end


					CONNECTIONS[id] = endpoint_connection # add the connection to the hash-map with it's unique id		
					ws.send([id, CONN_OK].pack("a32m0"))

					handler = RemoteConnectionHandler.new(ws, id, endpoint_connection)
					handler.handle_https()

				elsif data[0...10] == CONN_CLOSE

					if CONNECTIONS[id]
						puts "CONN_CLOSE for #{id}, sending CONN_CLOSE_ACCEPT to the client".yellow
						CONNECTIONS[id].close
						CONNECTIONS.delete(id)
						ws.send([id, CONN_CLOSE_ACCEPT].pack("a32m0"))
					end

				elsif data[0...17] == CONN_CLOSE_ACCEPT

					if CONNECTIONS[id]
						puts "CONN_CLOSE_ACCEPT for #{id}".green
						CONNECTIONS[id].close
						CONNECTIONS.delete(id)
					end

				else

					begin
						if CONNECTIONS[id] && !CONNECTIONS[id].closed?
							CONNECTIONS[id].print(data) 
						end
					rescue Errno::EPIPE
						puts "Broken pipe for #{data}".red.bold
						CONNECTIONS[id].close
						CONNECTIONS.delete(id)
					rescue Errno::ECONNRESET
						puts "Errno::ECONNRESET"
						CONNECTIONS[id].close
						CONNECTIONS.delete(id)
					end
					
      	end

	
      	
      end
    end

    ws.onclose do
      puts "Client disconnected"
    end
  end

end
