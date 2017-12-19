module denpasar.net.socketselector;

import core.thread;
import denpasar.core.kernel;
import denpasar.utils.logger;
public import std.datetime;
public import std.socket;

/**
 * Socket Selector
 */
class SocketSelector {

	/**
	 * singleton instance of SocketSelector
	 */
	static SocketSelector instance()
	{
		if(!_instanceCreated)
		{
			synchronized
			{
				if( _instance is null )
				{
					_instance = new SocketSelector;
					_instanceCreated = true;
				}
			}
		}
		return _instance;
	}

	/**
	 * on data ready on socket
	 */
	void onDataReady(Socket socket, void delegate(Socket) nothrow callback)
	{
		waitEvent(socket, Duration.max, callback, null);
	}

	/**
	 * wait for socket event
	 */
	void waitEvent(
		Socket socket, 
		Duration timeoutDuration, 
		void delegate(Socket) nothrow onReady,
		void delegate(Socket) nothrow onTimeout)
	{
		synchronized(this)
		{
			waitEventNoLock(socket, timeoutDuration, onReady, onTimeout);
		}
	}

	/**
	 * remove socket event listener
	 */
	void remove(Socket socket)
	{
		synchronized(this)
		{
			removeNoLock(socket);
		}
	}

protected:
	struct SocketInfo
	{
		this(Duration timeoutLimit, void delegate(Socket) nothrow onDataReady, void delegate(Socket) nothrow onTimeout)
		{
			this.timeoutLimit = timeoutLimit == Duration.max? long.max : Clock.currStdTime + timeoutLimit.total!"hnsecs";
			this.onDataReady = onDataReady;
			this.onTimeout = onTimeout;
		}

		long timeoutLimit;
		void delegate(Socket) onDataReady;
		void delegate(Socket) onTimeout;
	}

	void main()
	{
        Thread thisThread = Thread.getThis;
		thisThread.priority = Thread.PRIORITY_MIN;

		SocketSet socketSet = _socketSet = new SocketSet();

        try
        {
            while(!_isTerminated)
            {
                if( loadSocketsIntoSocketSet )
                {
                    Socket.select(socketSet, null, null, dur!"seconds"(10));
                    checkSocketEvent;
                    socketSet.reset;
                }
            }
        }
        catch(Throwable t)
        {
            logError("Unhandle exception on SocketSelector. System will not receive new connection anymore\n"~t.msg);
        }
		socketSet.destroy;
	}

	bool loadSocketsIntoSocketSet()
	{
		synchronized(this)
		{
			return registerSocketNoLock;
		}
	}

	void checkSocketEvent()
	{
		synchronized(this)
		{
			checkSocketEventNoLock;
		}
	}

	void checkSocketEventNoLock(){
		Socket[] tobeRemoved;
		SocketSet socketSet = _socketSet;
		foreach(Socket socket; _socketInfos.byKey)
		{
			SocketInfo* socketInfo = _socketInfos[socket];
			if( socketSet.isSet(socket) )
			{
                debug
                {
                    logDebug("Socket %s Ready", socket.toString);
                }
                auto dg = socketInfo.onDataReady;
				if( dg !is null )
					dg(socket);
				tobeRemoved ~= socket;
			}
			else
			{
                immutable long timeoutLimit = socketInfo.timeoutLimit;
				if( Clock.currStdTime >= timeoutLimit )
				{
                    debug
                    {
                        logDebug("Socket %s Timeout", socket.toString);
                    }
                    fireEvent(socketInfo.onTimeout, socket);
					tobeRemoved ~= socket;
                }
			}
		}
        if( tobeRemoved.length > 0)
        {
            foreach(Socket socket; tobeRemoved)
            {
                removeNoLock(socket);
            }
            _socketInfos.rehash;
        }
	}

	void waitEventNoLock(
		Socket socket, 
		Duration timeoutDuration,
		void delegate(Socket) nothrow onDataReady,
		void delegate(Socket) nothrow onTimeout)
	{
		SocketInfo* socketInfo = new SocketInfo(timeoutDuration, onDataReady, onTimeout);

		_socketInfos[socket] = socketInfo;

	}

	bool registerSocketNoLock()
	{
		foreach(Socket socket; _socketInfos.byKey)
		{
			_socketSet.add(socket);
		}
		return true;
	}

	void removeNoLock(Socket socket)
	{
		_socketInfos.remove(socket);
	}

	void terminate()
	{
		synchronized(this)
		{
			_isTerminated = true;
		}
	}

private:
	this()
	{
		debug(SocketSelector)
		{
			logDebug("creating SocketSelector instance");
		}
		_thread = new Thread(&main);
		_thread.start;
	}

	~this()
	{
		_thread.destroy;
		debug(SocketSelector)
		{
			logDebug("creating SocketSelector destroyed");
		}
	}

	Thread _thread=null;
	SocketInfo*[Socket] _socketInfos;
	bool _isTerminated = false;
	SocketSet _socketSet=null;

	__gshared
	{
		bool _instanceCreated = false;
		SocketSelector _instance = null;
	}
}


shared static ~this()
{
	SocketSelector.instance.terminate;
}
