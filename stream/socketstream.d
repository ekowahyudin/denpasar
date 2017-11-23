module denpasar.stream.socketstream;

public import denpasar.stream.abstractstream;
import denpasar.utils.set;
import denpasar.core.kernel;

import std.socket;

class SocketStream : AbstractStream
{
    this(Socket socket){
        _socket = socket;
        isSeekable = false;
    }
    
    ~this(){
        close();
    }

    @property Socket socket()
    {
        return _socket;
    }

    @property void socket(Socket value)
    {
        _socket = value;
    }

protected:

    override size_t rawSeek(SeekFrom seekFrom, sizediff_t delta)
    {
        if( seekFrom == SeekFrom.end && delta==0 )
        {
            return socket.isAlive ? size_t.max : 0;
        }
        seekError;
        return 0;
    }
    
    override size_t rawReadAny(void* targetPtr, size_t bytes)
    {
        Socket socket = this.socket;
        ubyte* ubytePtr = cast(ubyte*) targetPtr;
        sizediff_t received = socket.receive(ubytePtr[0..bytes]);
        checkSocketError(received);
        return received;
    }
    
    override size_t rawWriteAny(void* sourcePtr, size_t bytes)
    {
        Socket socket = this.socket;
        ubyte* ubytePtr = cast(ubyte*) sourcePtr;
        sizediff_t sent = socket.send(ubytePtr[0..bytes]);
        checkSocketError(sent);
        return sent;
    }

    override void rawClear()
    {
        //do nothing
    }

    override void rawClose()
    {
        if( socket.isAlive )
            socket.close;
    }

    void checkSocketError(sizediff_t socketReturnValue){
        if( socketReturnValue == Socket.ERROR || (socketReturnValue == 0 && !socket.isAlive)){
            throwSocketException;
        }
    }
    
    protected void streamNotReady()
    {
        //stream on blocking socket always ready!!
        throwSocketException();
    }
    
    protected void dataNotReady()
    {
        //non blocking is abstract here
    }

    protected void throwSocketException()
    {
        throw new SocketException("Socket error");
    }
 
private:
    Socket _socket;
}

class BlockingSocketStream : SocketStream{

	this(Socket socket){
        super(socket);
	}
}

class NonBlockingSocketStream : SocketStream{
	this(Socket socket){
		super(socket);
        _onStreamNotReady = new SetOf!(void delegate(Object));
        _onDataNotReady = new SetOf!(void delegate(Object));
	}

	@property void onDataNotReady(void delegate(Object sender) callback)
    {
        _onDataNotReady ~= callback;
    }

    @property void onStreamNotReady(void  delegate(Object sender) callback)
    {
        _onStreamNotReady ~= callback;
    }

    /**
     * write operation and stream is not ready
     */
	protected override void streamNotReady()
    {
        fireEvent(_onStreamNotReady, this);
	}
	
    /**
     * read operation and data is not ready
     */
	protected override void dataNotReady()
    {
        fireEvent(_onDataNotReady, this);
	}
private:
    SetOf!(void delegate(Object sender)) _onStreamNotReady;
    SetOf!(void delegate(Object sender)) _onDataNotReady;
}
