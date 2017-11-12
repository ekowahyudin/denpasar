module denpasar.net.listener;

private import denpasar.base.classes;
public  import denpasar.core.kernel;
private import denpasar.net.socketselector;
public  import std.socket;

class Listener : Activable {
	this(ushort portNumber=8080, string ipAddress="", int ipVersion=4)
	{
		this.portNumber = portNumber;
		this.ipAddress = ipAddress;
		this.ipVersion = ipVersion;
	}
	
    ushort portNumber() @property
	{
		return _portNumber;
	}
	
    void portNumber(ushort value) @property
	{
		_portNumber = value;
	}
	
    string ipAddress() @property
	{
		return _ipAddress;
	}
	
    void ipAddress(string value) @property
	{
		_ipAddress = value;
	}
	
    int ipVersion() @property
	{
		return _ipVersion;
	}
	
    void ipVersion(int value) @property
	{
		_ipVersion = value;
	}

    int backlog() @property
    {
        return _backlog;
    }

    void backlog(int value) @property
    {
        _backlog = value;
    }

    Socket socket() @property
	{
		return _socket;
	}

	void onIncommingClient(void delegate(Listener, Socket) callback)
	{
		_onIncommingClient = callback;
	}

	void onFirewallCheck(void delegate(Listener, Socket) callback)
	{
		_onFirewallCheck = callback;
	}

protected:

	@property
	void socket(Socket value)
	{
		_socket = value;
	}

	Address internetAddress()
	{
		return ipVersion==4? 
			ipAddress.length == 0 ? new InternetAddress(portNumber) : new InternetAddress(ipAddress, portNumber) :
			ipAddress.length == 0 ? new Internet6Address(portNumber) : new Internet6Address(ipAddress, portNumber);
	}

	override
	void rawActivate() 
	{
		socket = new TcpSocket();
		bind;
		listen;
        waitSocketEvent;
	}
	
	override
	void rawDeactivate() 
	{
		closeSocket;
		socket = null;
	}

	void closeSocket()
	{
		SocketSelector.instance.remove(socket);
		socket.close;
	}

	void bind()
	{
		socket.bind(this.internetAddress);
	}
	
	void listen()
	{
        socket.listen(backlog);
	}

    void waitSocketEvent()
    {
        SocketSelector.instance.onDataReady(socket, &handleIncommingClient);
    }

    void handleIncommingClient(Socket socket) nothrow
    {
        Socket peer = null;
        try
        {
            peer = socket.accept;
            peer.blocking = false;
            firewallCheck(peer);
            futureTask(_onIncommingClient, this, peer);
        }
        catch(Throwable e)
        {
            if( peer !is null)
                peer.close;
        }
        finally
        {
            futureTask(&waitSocketEvent);
        }
    }

	/**
	 * throw exception if connection is rejected
	 */
	void firewallCheck(Socket socket)
	{
		fireEvent(_onFirewallCheck, this, socket);
	}

private:
	void delegate(Listener,Socket) _onIncommingClient, _onFirewallCheck;
	ushort _portNumber;
	string _ipAddress;
	int _ipVersion;
	Socket _socket;
    int _backlog = 256;
}


