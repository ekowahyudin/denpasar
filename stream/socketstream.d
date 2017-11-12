module denpasar.stream.socketstream;

import denpasar.stream.basestream;

import std.socket;

interface SocketStream : Stream{
	@property Socket socket();
}

class BlockingSocketStream : SocketStream{
	mixin FlowableTemplate;

	this(Socket socket){
		_socket = socket;
	}

	~this(){
		close();
	}

	bool isSeekable() @property{
		return true;
	}

	Socket socket(){
		return _socket;
	}

	size_t size() @property{
		return size_t.max;
	}
	
	size_t position() @property{
		return 0;
	}

	void position(size_t value) @property{
		throwSeekException;
	}

	size_t seek(SeekFrom seekFrom, sizediff_t delta){
		throwSeekException;
		return 0;
	}

	size_t readAny(void* targetPtr, size_t bytes){
		Socket socket = this.socket;
		ubyte* ubytePtr = cast(ubyte*) targetPtr;
		sizediff_t received = socket.receive(ubytePtr[0..bytes]);
		checkSocketError(received);
		return received;
	}

	size_t writeAny(void* sourcePtr, size_t bytes){
		Socket socket = this.socket;
		ubyte* ubytePtr = cast(ubyte*) sourcePtr;
		sizediff_t sent = socket.send(ubytePtr[0..bytes]);
		checkSocketError(sent);
		return sent;
	}

	void clear(){
		//do nothing on socket stream
	}

	void close(){
		if( socket.isAlive )
			socket.close;
	}

	protected void checkSocketError(sizediff_t socketReturnValue){
		if( socketReturnValue == Socket.ERROR || (socketReturnValue == 0 && !socket.isAlive)){
			throwSocketException;
		}
	}

	protected void streamNotReady(){
		//stream on blocking socket always ready!!
		throwSocketException();
	}

	protected void dataNotReady(){
		//non blocking is abstract here
	}

	protected void throwSocketException(){
		throw new StreamException("Connection error/disconnected");
	}

	protected void throwSeekException(){
		throw new StreamSeekException("Unable seek Socket stream");
	}

private:
	Socket _socket;
}

class NonBlockingSocketStream : BlockingSocketStream{
	this(Socket socket){
		super(socket);
	}

	//TODO write in method style
	@property void delegate(Object sender) onDataNotReady;
	@property void delegate(Object sender) onStreamNotReady;

	protected override void streamNotReady()
    {
		auto dg = onDataNotReady;
		if( dg !is null )
			dg(this);
	}
	
	protected override void dataNotReady()
    {
		auto dg = onStreamNotReady;
		if( dg !is null )
			dg( this );
	}
}
