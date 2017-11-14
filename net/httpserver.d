module denpasar.net.httpserver;

public  import denpasar.core.kernel;
private import denpasar.net.tcpserver;
public  import denpasar.net.listener;
private import denpasar.utils.array;
private import denpasar.utils.set;
private import denpasar.utils.strings;
private import std.uni;
private import std.string;

enum TalkingProtocol:byte
{
	http1_0, http1_1, http2, webSocket
}

class Connection
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

	Connection conection() @property
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

	void connection(Connection value) nothrow @property
	{
		_connection = value;
	}

	Connection connection() nothrow @property
	{
		return _connection;
	}

private:
	Request _request;
	Response _response;
	Connection _connection;
}

struct RequestParam
{
    string opIndex(string key)
    {
        return _data.get(key,"");
    }
    
    void opIndexAssign(string key, string value)
    {
        _data[key] = value;
    }

    void rehash()
    {
        _data.rehash;
    }
private:
    string[string] _data;
}

class Request
{
    string commandMethod() @property
    {
        return _commandMethod;
    }

    void commandMethod(string value) @property
    {
        _commandMethod = value;
    }

    string resourcePath() @property
    {
        return _resourcePath;
    }

    void resourcePath(string value) @property
    {
        _resourcePath = value;
    }

    RequestParam param() @property
    {
        return _param;
    }
private:
    string _commandMethod;
    string _resourcePath;
    RequestParam _param;
}

class Response
{
	
}

class HttpServer : TcpServer!Connection
{
	this() 
	{
        super();
		// Constructor code
	}

protected:
	override
	void executeConnection(Connection connection)
	{
		switch(connection.talkingProtocol)
		{
			case TalkingProtocol.http1_0: 
				goto case;
			case TalkingProtocol.http1_1:
				http1ExecuteConnection(connection);
				break;
			default:
				connection.close;
		}
	}

	void http1ExecuteConnection(Connection connection)
	{
		auto httpRequestTask = parallelTask(&http1GetRequest, connection);
		Context context = new Context();
		context.connection = connection;
		context.response = new Response();
        connection.registerContext(context);
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
			Connection connection = context.connection;
			connection.unregisterContext(context);
		};
	}

	//@Parallel
	Request http1GetRequest(Connection connection)
	{
		Request result = new Request();

        http1GetCommandLine(connection, result);
        //TODO
		return result;
	}

    void http1GetCommandLine(Connection connection, Request request)
    {
        auto stream = connection.stream;
        http1GetCommand(stream, request);
        http1GetResource(stream, request);
    }

    void http1GetCommand(Stream stream, Request request)
    {
        string result;
        while(true)
        {
            char c = stream.read!char;
            c = cast(char)toUpper(c);
            if( isWhite(c) )
                break;
            result ~= c;
        }
        request.commandMethod = result;
    }

    void http1GetResource(Stream stream, Request request)
    {
        bool hasParam = false;
        char[] buf = stream.read!(char[])(
            delegate bool(ref char[] currentBuf)
            {
                sizediff_t j = currentBuf.length - 1;
                if( j<0 )
                    return true;

                char newChar = currentBuf[j];
                if( newChar == '?' )
                {
                    hasParam = true;
                    goto handleWhiteChar;
                }

                if( isWhite(newChar) )
                {
                handleWhiteChar:
                    currentBuf.length = j;
                    return false;
                }
                else
                {
                    return true;
                }
            }
        );

        request.resourcePath = cast(string)unescapeUrlComponent(buf);

        if( hasParam )
        {
            buf = stream.read!(char[])(
                delegate bool(ref char[] currentBuf)
                {
                    sizediff_t j = currentBuf.length - 1;
                    if( j< 0 )
                        return true;
                    char newChar = currentBuf[j];
                    if( isWhite(newChar) )
                    {
                        currentBuf.length = currentBuf.length - 1;
                        return false;
                    }
                    else
                    {
                        return true;
                    }
                }
            );
            char[][] paramsKeyVal = buf.split('&');
            foreach(char[] paramKeyVal; paramsKeyVal)
            {
                char[][] keyAndValue = splitFirst(paramKeyVal,'=');
                char[] key = unescapeUrlComponent(keyAndValue[0]);
                char[] val = unescapeUrlComponent(keyAndValue[1]);
                request.param[cast(string)key] = cast(string)val;
            }
            request.param.rehash;
        }
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

