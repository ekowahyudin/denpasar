module denpasar.net.socketselector;

public import std.datetime;
public import std.socket;
import std.stdio;
import core.atomic;
import core.sync.mutex;
import core.sync.condition;
import core.thread;

class SocketSelector {

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

	void onDataReady(Socket socket, void delegate(Socket) nothrow callback)
	{
		waitEvent(socket, Duration.max, callback, null);
	}

	void waitEvent(
		Socket socket, 
		Duration timeoutDuration, 
		void delegate(Socket) nothrow onReady,
		void delegate(Socket) nothrow onTimeout)
	{
		lockList();
		scope(exit)
		{
			unlockList();
		}
		waitEventNoLock(socket, timeoutDuration, onReady, onTimeout);
	}

	void remove(Socket socket)
	{
		lockList;
		scope(exit) unlockList;
		removeNoLock(socket);
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
		Thread.getThis.priority = Thread.PRIORITY_MIN;
		_socketSet = new SocketSet();

		while(!_isTerminated)
		{
			if( loadSocketsIntoSocketSet )
			{
				Socket.select(_socketSet, null, null, dur!"seconds"(1));

				checkSocketEvent;

				_socketSet.reset;
			}
		}
		_socketSet.destroy;
	}

	bool loadSocketsIntoSocketSet()
	{
		lockList();
		scope(exit)
		{
			unlockList();
		}
		return registerSocketNoLock;
	}

	void checkSocketEvent()
	{
		lockList;
		scope(exit) unlockList;
		checkSocketEventNoLock;
	}

	void checkSocketEventNoLock(){
		Socket[] tobeRemoved;
		SocketSet socketSet = _socketSet;
		foreach(Socket socket; _socketInfos.byKey)
		{
			SocketInfo* socketInfo = _socketInfos[socket];
			if( socketSet.isSet(socket) )
			{
				auto dg = socketInfo.onDataReady;
				if( dg !is null )
					dg(socket);
				tobeRemoved ~= socket;
			}
			else
			{
				long timeoutLimit = socketInfo.timeoutLimit;
				if( Clock.currStdTime >= timeoutLimit )
				{
					auto dg = socketInfo.onTimeout;
					if( dg !is null )
						dg(socket);
					tobeRemoved ~= socket;
				}
			}
		}
		foreach(Socket socket; tobeRemoved)
		{
			removeNoLock(socket);
		}
		_socketInfos.rehash;
	}

	void waitEventNoLock(
		Socket socket, 
		Duration timeoutDuration,
		void delegate(Socket) nothrow onDataReady,
		void delegate(Socket) nothrow onTimeout)
	{
		SocketInfo* socketInfo = new SocketInfo(timeoutDuration, onDataReady, onTimeout);

		_socketInfos[socket] = socketInfo;

		_hasSocket.notify;
	}

	bool registerSocketNoLock()
	{
		while(!_isTerminated){
			int count = 0;
			foreach(Socket socket; _socketInfos.byKey)
			{
				_socketSet.add(socket);
				count++;
			}
			if( count > 0 )
				return true;

			waitForSocketNoLock();
		}
		return false;
	}

	void waitForSocketNoLock()
	{
		_hasSocket.wait;
	}

	void removeNoLock(Socket socket)
	{
		_socketInfos.remove(socket);
	}

	void terminate()
	{
		lockList;
		scope(exit) unlockList;

		_isTerminated = true;
		_hasSocket.notifyAll;
	}

	void lockList()
	{
		while( !_mutex.tryLock )
		{
			Thread.yield;
		}
	}

	void unlockList()
	{
		_mutex.unlock;
	}

private:
	this()
	{
		debug(SocketSelector)
		{
			writeln("creating SocketSelector instance");
		}
		_thread = new Thread(&main);
		_mutex = new Mutex;
		_hasSocket = new Condition(_mutex);
		_thread.start;
		_thread.name = "SocketSelector";
	}

	~this()
	{
		_hasSocket.destroy;
		_mutex.destroy;
		_thread.join;
		_thread.destroy;
		debug(SocketSelector)
		{
			writeln("creating SocketSelector destroyed");
		}
	}

	Thread _thread=null;
	Mutex _mutex=null;
	Condition _hasSocket=null;
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
