module denpasar.net.httpserver;

public  import denpasar.core.kernel;
private import denpasar.net.tcpserver;
public  import denpasar.net.listener;
private import denpasar.utils.set;

enum TalkingProtocol:byte
{
	http1_0, http1_1, http2, webSocket
}

class HttpConnection
{
	mixin TcpConnection;

	this()
	{
		_contexts = new ThreadSaveSetOf!Context;
	}

	TalkingProtocol talkingProtocol() @property
	{
		return _talkingProtocol;
	}

	void talkingProtocol(TalkingProtocol value) @property
	{
		_talkingProtocol = value;
	}

	void registerContext(Context context)
	{
		contexts ~= context;
	}

	void unregisterContext(Context context)
	{
		contexts -= context;
	}

	SetOf!Context contexts() @property
	{
		return _contexts;
	}
private:
	SetOf!Context _contexts;
	TalkingProtocol _talkingProtocol=TalkingProtocol.http1_1;
	void delegate(typeof(this))[] _onClossed;
}

class Context 
{
	Request request() @property
	{
		return _request;
	}
	
	Response response() @property
	{
		return _response;
	}

	HttpConnection conection() @property
	{
		return _connection;
	}

	void request(Request value) @property
	{
		_request = value;
	}

	void response(Response value) @property
	{
		_response = value;
	}

	void connection(HttpConnection value) nothrow @property
	{
		_connection = value;
	}

	HttpConnection connection() nothrow @property
	{
		return _connection;
	}

private:
	Request _request;
	Response _response;
	HttpConnection _connection;
}

class Request
{
	
}

class Response
{
	
}

class HttpServer : TcpServer!HttpConnection
{
	this() 
	{
        super();
		// Constructor code
	}

	override
	void executeConnection(HttpConnection connection)
	{
		switch(connection.talkingProtocol)
		{
			case TalkingProtocol.http1_0: 
				goto case;
			case TalkingProtocol.http1_1:
				executeHttp1Connection(connection);
				break;
			default:
				connection.close;
		}
	}

	void executeHttp1Connection(HttpConnection connection)
	{
		auto httpRequestTask = parallelTask(&getHttp1Request, connection);
		Context context = new Context();
		connection.registerContext(context);

		context.connection = connection;
		context.response = new Response();
        context.request = httpRequestTask.workForce;

		auto httpResponseTask = parallelTask(&generateResponse, context);

		httpResponseTask.onSuccess = delegate void()
		{
			sendResponseTask(context);
		};

		httpResponseTask.onFailure = delegate void(Exception e)
		{
			generateFailureContent(context, e);
			sendResponseTask(context);
		};
	}

	protected void sendResponseTask(Context context)
	{
		auto sendResponseTask = parallelTask(&sendResponse, context);
		sendResponseTask.onDone = delegate void()
		{
			HttpConnection connection = context.connection;
			connection.unregisterContext(context);
		};
	}

	//@Parallel
	Request getHttp1Request(HttpConnection connection)
	{
		Request result = new Request();

		return result;
	}

	void generateResponse(Context context)
	{

	}

	void generateFailureContent(Context context, Throwable t) nothrow
	{
		
	}

	void sendResponse(Context context)
	{

	}

}

