module denpasar.net.tcpserver;

import denpasar.base.classes;
import denpasar.kernel;
import denpasar.net.listener;
import denpasar.net.tcpserver;

class TcpServer : Activable {

	void opOpAssign(string op)(Listener listener) if(op=="~") {
		_listeners ~= listener;
	}

	void opOpAssign(string op)(Listener listener) if(op=="-") {
		removeItemSet(_listeners, listener);
	}

protected:

	override void rawActivate() 
	{
		foreach(Listener listener; _listeners)
		{
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

private:
	Listener[] _listeners;
}

