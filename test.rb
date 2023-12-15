require "timeout"

loop do
	require 'timeout'
	status = Timeout::timeout(5) {
		sleep 10
		puts "hi"
	  # Something that should be interrupted if it takes more than 5 seconds...
	}
	puts status
end
