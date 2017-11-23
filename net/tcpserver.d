module denpasar.net.tcpserver;

import denpasar.base.classes;
import denpasar.core.kernel;
public import denpasar.stream.abstractstream;
public import denpasar.stream.socketstream;
import denpasar.utils.set;
public import denpasar.net.listener;
import denpasar.utils.array;
import std.traits;

class TcpServer(Connection) : Activable 
{

	this()
	{
		_listeners = new SetOf!Listener;
		_connections = new ThreadSaveSetOf!Connection;
	}

	~this()
	{
		_connections.destroy;
		_listeners.destroy;
	}

	void opOpAssign(string op)(Listener listener) if(op=="~") 
	{
		listeners ~= listener;
	}

	void opOpAssign(string op)(Listener listener) if(op=="-") 
	{
		listeners.remove(listener);
	}

	void opOpAssign(string op)(Connection connection) if(op=="~") 
	{
		connections ~= connection;
	}
	
	void opOpAssign(string op)(Connection connection) if(op=="-") 
	{
		connection -= connection;
	}

	SetOf!Listener listeners() @property
	{
		return _listeners;
	}

	SetOf!Connection connections() @property
	{
		return _connections;
	}

protected:

	override void rawActivate() 
	{
		foreach(Listener listener; _listeners)
		{
			listener.onFirewallCheck = &handleFirewallCheck;
			listener.onIncommingClient = &handleIncommingConnection;
			listener.isActive = true;
		}
	}

	override void rawDeactivate()
	{
		foreach(Listener listener; _listeners)
		{
			listener.isActive = false;
		}
	}

	void handleFirewallCheck(Listener listener, Socket peer)
	{
		//do nothing at this time
	}

	/**
	 * we have new connection
	 */
	void handleIncommingConnection(Listener listener, Socket peer)
	{
		Connection connection = createConnection(listener, peer);
		registerConnection(connection);
		fireIncommingConnection(connection);
		executeConnection(connection);
	}

	Connection createConnection(Listener listener, Socket peer)
	{
		Connection result = new Connection;
		result.server = this;
		result.listener = listener;
		result.socket = peer;
		result.onClossed = &handleConnectionClossed;
		return result;
	}

	void registerConnection(Connection connection)
	{
        connections ~= connection;
	}

	void unregisterConnection(Connection connection)
	{
		connections -= connection;
	}

	void fireIncommingConnection(Connection connection)
	{
		fireEvent(_onIncommingConnection, connection);
	}

	void fireConnectionClossed(Connection connection)
	{
		fireEvent(_onConnectionClossed, connection);
	}

	void handleConnectionClossed(Connection connection)
	{
		unregisterConnection(connection);
		fireConnectionClossed(connection);
	}

	void executeConnection(Connection connection)
	{
		static if( __traits(compiles, connection.execute) )
		{
			connection.execute;
		}
	}

private:
	SetOf!Listener _listeners;
	SetOf!Connection _connections;
	void delegate(Connection)[] _onIncommingConnection, _onConnectionClossed, _onExecuteConnection;
}

mixin template TcpConnection() 
{
	~this()
	{
		close;
		_server = null;
		_listener = null;
		_socket = null;
	}

	Object server() @property
	{
		return _server;
	}

	void server(Object value) @property
	{
		_server = value;
	}

	Listener listener() @property
	{
		return _listener;
	}

	void listener(Listener value) @property
	{
		_listener = value;
	}

	Socket socket() @property
	{
		return _socket;
	}

	void socket(Socket value) @property
	{
		_socket = value;
        stream = value !is null ? new NonBlockingSocketStream(value) : null;
	}

    AbstractStream stream() @property
    {
        return _stream;
    }

    void stream(AbstractStream value) @property
    {
        _stream = value;
    }

	void close()
	{
		if( socket.isAlive )
		{
			closeNoCheck();
		}
		fireEvent(_onClossed, this);
		_onClossed = null;
	}

	void onClossed(void delegate(typeof(this)) dg) @property
	{
		_onClossed ~= dg;
	}

protected:
	void closeNoCheck()
	{
		socket.close();
	}

private:
	void delegate(typeof(this))[] _onClossed;
	Object _server;
	Listener _listener;
	Socket _socket;
    AbstractStream _stream;
}
