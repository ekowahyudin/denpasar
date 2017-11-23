module denpasar.net.httpserver;

public  import denpasar.core.kernel;
private import denpasar.net.tcpserver;
public  import denpasar.net.listener;
private import denpasar.utils.array;
private import denpasar.utils.set;
private import denpasar.utils.strings;
private import denpasar.utils.logger;
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

    string talkingProtocol() @property
    {
        return _talkingProtocol;
    }

    void talkingProtocol(string value) @property
    {
        _talkingProtocol = value;
    }

    double protocolVersion() @property
    {
        return _protocolVersion;
    }

    void protocolVersion(double v) @property
    {
        _protocolVersion = v;
    }

private:
    string _talkingProtocol;
    string _commandMethod;
    string _resourcePath;
    RequestParam _param;
    double _protocolVersion=1.0;
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
        http1GetProtocol(stream, request);
    }

    void http1GetCommand(AbstractStream stream, Request request)
    {
        stream.stripLeft!char;
        const max = 9;
        char[max] result;
        sizediff_t index = -1;
        while(index<max)
        {
            char c = stream.read!char;
            c = cast(char)toUpper(c);
            if( isWhite(c) )
                break;
            result[++index] = c;
        }
        ++index;
        request.commandMethod = cast(string) result[0..index];
        if( index == max )
        {
            throw new RequestException("Invalid command method");
        }
        debug
        {
            logDebug("request.commandMethod:%s", request.commandMethod);
        }
    }

    void http1GetResource(AbstractStream stream, Request request)
    {
        stream.stripLeft!char;
        bool hasParam = false;
        char[] buf = stream.read!(char[])(
            delegate bool(ref char[] currentBuf)
            {
                sizediff_t j = currentBuf.length - 1;
                if( j<0 )
                    return true;
                if( j>4096 )
                    throw new RequestException("Request path too long");

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
        debug
        {
            logDebug("request.path: "~request.resourcePath);
        }


        if( hasParam )
        {
            buf = stream.read!(char[])(
                delegate bool(ref char[] currentBuf)
                {
                    sizediff_t j = currentBuf.length - 1;
                    if( j< 0 )
                        return true;
                    if( j > 16*1024 )
                    {
                        throw new RequestException("Request parameter too long");
                    }
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

                debug
                {
                    logDebug("request.param[%s]=%s", cast(string) key, cast(string) val);
                }

            }
            request.param.rehash;
        }

        stream.stripLeft!char;
   }

    void http1GetProtocol(AbstractStream stream, Request request)
    {
        char[] protocol;
        while(true)
        {
            char c = cast(char) toUpper( stream.read!char );
            if( c == '/' )
            {
                break;
            }
            if( protocol.length > 5 )
            {
                goto unknowTalkingProtocol;
            }
            protocol ~= c;
        }
        if( protocol != "HTTP" && protocol != "HTTPS" )
        {
        unknowTalkingProtocol:
            throw new RequestException("Unknow talking protocol");
        }
        request.talkingProtocol = cast(string) protocol;

        char majorVersion = stream.read!char;
        if( majorVersion != '1' )
        {
        unsupportProtocolVersion:
            throw new RequestException("Unsupported protocol version");
        }
        char dot = stream.read!char;
        if( dot != '.' )
            goto unsupportProtocolVersion;
        char minorVersion = stream.read!char;
        switch( minorVersion )
        {
            case '0':
                request.protocolVersion = 1.0;
                break;
            case '1':
                request.protocolVersion = 1.1;
                break;
            default:
                goto unsupportProtocolVersion;
        }

        debug
        {
            logDebug("request.protocol:%s/%f", request.talkingProtocol, request.protocolVersion );
        }

        stream.readLine!(char[]);
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

class ClientException : Exception
{
    this(Connection client, string message, string file=__FILE__, size_t line=__LINE__)
    {
        this.client = client;
        super(message, file, line);
    }

    Connection client;
}

class RequestException : ClientException
{
    this(string message, string file=__FILE__, size_t line=__LINE__)
    {
        super(null, message, file, line);
    }
}