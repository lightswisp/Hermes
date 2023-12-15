require 'faye/websocket'
require 'eventmachine'

EM.run do
  ws = Faye::WebSocket::Client.new('wss://sdnet.lol', [], tls: {
                                     verify_peer: false
                                   })

  ws.on :open do |_event|
    p [:open]
    ws.send('Hello, world!')
  end

  ws.on :message do |event|
    p [:message, event.data]
  end

  ws.on :close do |event|
    p [:close, event.code, event.reason]
    ws = nil
  end
end
