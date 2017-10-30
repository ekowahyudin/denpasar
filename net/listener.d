﻿module denpasar.net.listener;

private import denpasar.base.classes;
private import denpasar.net.socketselector;
public import std.socket;
public import denpasar.kernel;

class Listener : Activable {
	this(ushort portNumber=8080, string ipAddress="", int ipVersion=4)
	{
		this.portNumber = portNumber;
		this.ipAddress = ipAddress;
		this.ipVersion = ipVersion;
	}
	
	@property
	ushort portNumber()
	{
		return _portNumber;
	}
	
	@property
	void portNumber(ushort value)
	{
		_portNumber = value;
	}
	
	@property
	string ipAddress()
	{
		return _ipAddress;
	}
	
	@property
	void ipAddress(string value)
	{
		_ipAddress = value;
	}
	
	@property
	int ipVersion()
	{
		return _ipVersion;
	}
	
	@property
	void ipVersion(int value)
	{
		_ipVersion = value;
	}

	@property
	Socket socket()
	{
		return _socket;
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
		SocketSelector.instance.onDataReady(socket,
			delegate(Socket socket) nothrow
			{
				try{
					Socket peer = socket.accept;
					firewallCheck(peer);
					parallelTask(_onIncommingClient, this, peer);
				}
				catch(Throwable e){
				}
				finally{
					futureTask(&listen);
				}
			}
		);
	}

	void firewallCheck(Socket socket)
	{
		callEvent(_onFirewallCheck, this, socket);
	}

private:
	void delegate(Listener,Socket) _onIncommingClient, _onFirewallCheck;
	ushort _portNumber;
	string _ipAddress;
	int _ipVersion;
	Socket _socket;
}

