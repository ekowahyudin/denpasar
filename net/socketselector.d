module denpasar.net.socketselector;

public import std.socket;
import core.atomic;
import core.sync.mutex;
import core.sync.condition;
import core.thread;

class SocketSelector {

	static SocketSelector instance()
	{
		if(_instanceCreated)
		{
			synchronized
			{
				if( _instance !is null )
				{
					_instance = new SocketSelector;
				}
			}
		}
		return _instance;
	}

	void onDataReady(Socket socket, void delegate(Socket) nothrow callback){
		lockList();
		scope(exit)
		{
			unlockList();
		}
		onDataReadyNoLock(socket, callback);
	}

	void remove(Socket socket)
	{
		lockList;
		scope(exit) unlockList;
		removeNoLock(socket);
	}

protected:
	void main()
	{
		Thread.getThis.priority = Thread.PRIORITY_MIN;
		_socketSet = new SocketSet();
		debug{
			immutable int secondsSelect = 3;
		}
		else{
			immutable int secondsSelect = 5;
		}

		while(!_isTerminated)
		{
			if( loadSocketsIntoSocketSet )
			{
				Socket.select(_socketSet, null, null, dur!"seconds"(secondsSelect));

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
		foreach(Socket socket; _callbacks.byKey)
		{
			if( socketSet.isSet(socket) )
			{
				auto dg = _callbacks[socket];
				dg(socket);
				tobeRemoved ~= socket;
			}
		}
		foreach(Socket socket; tobeRemoved)
		{
			removeNoLock(socket);
		}
	}

	void onDataReadyNoLock(Socket socket, void delegate(Socket) nothrow callback)
	{
		_callbacks[socket] = callback;
		_hasSocket.notify;
	}

	bool registerSocketNoLock()
	{
		while(true){
			int count = 0;
			foreach(Socket socket; _callbacks.byKey)
			{
				_socketSet.add(socket);
				count++;
			}
			if( count > 0 )
				return true;

			waitForSocketNoLock();
			if( _isTerminated )
			{
				return false;
			}
		}
	}

	void waitForSocketNoLock()
	{
		_hasSocket.wait;
	}

	void removeNoLock(Socket socket)
	{
		_callbacks.remove(socket);
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
		_thread = new Thread(&main);
		_mutex = new Mutex;
		_hasSocket = new Condition(_mutex);
	}

	~this()
	{
		_hasSocket.destroy;
		_mutex.destroy;
		_thread.join;
		_thread.destroy;
	}

	Thread _thread=null;
	Mutex _mutex=null;
	Condition _hasSocket=null;
	void delegate(Socket) nothrow [Socket] _callbacks;
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
