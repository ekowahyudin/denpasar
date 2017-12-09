module denpasar.net.httpserver;

public  import denpasar.core.kernel;
public  import denpasar.net.listener;
private import denpasar.net.tcpserver;
private import denpasar.stream.memorystream;
private import denpasar.utils.array;
private import denpasar.utils.logger;
private import denpasar.utils.set;
private import denpasar.utils.strings;
private import std.conv;
private import std.string;
private import std.traits;
private import std.uni;

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

    RequestParam header() @property
    {
        return _header;
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

    ushort targetPort() @property
    {
        return _targetPort;
    }

    void targetPort(ushort value) @property
    {
        _targetPort = value;
    }

    string targetHost() @property
    {
        return _targetHost;
    }

    void targetHost(string value) @property
    {
        _targetHost = value;
    }
private:
    ushort _targetPort = 80;
    string _targetHost;
    string _talkingProtocol;
    string _commandMethod;
    string _resourcePath;
    RequestParam _param;
    RequestParam _header;
    double _protocolVersion=1.0;
}

class Response
{
    void opAssign(S)(S s) if( isSomeString!S )
    {
        auto resultStream = new MemoryStream();
        resultStream.write(s);
        contentBody = resultStream;
    }

    void opOpAssign(string op, S)(S s) if( op=="~" && isSomeString!S )
    {
        auto current = this.contentBody;
        if( current is null )
        {
            opAssign(s);
        }
        else
        {
            StreamOverStream sos = cast(StreamOverStream) current;
            if( sos is null )
            {
                sos = new StreamOverStream(current);
                contentBody = sos;
            }
            sos ~= s;
        }
    }

    @property IReadableStream contentBody()
    {
        return _contentBody;
    }

    @property void contentBody(IReadableStream value)
    {
        _contentBody = value;
    }

private:
    IReadableStream _contentBody = null;
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

        try
        {
            generateResponse(context);
        }
        catch(Throwable t)
        {
            generateFailureContent(context, t);
        }

        try
        {
            sendResponse(context);
        }
        catch(Throwable t)
        {
            logError("Failed to send response: %s",t.msg);
        }
        connection.unregisterContext(context);
    }

	//@Parallel
	Request http1GetRequest(Connection connection)
	{
		Request result = new Request();

        http1ExtractCommandLine(connection, result);
        http1ExtractHeader(connection, result);
		return result;
	}

    void http1ExtractHeader(Connection connection, Request result)
    {
        debug
        {
            string debugLine;
        }
        auto stream = connection.stream;
        while(true)
        {
            char[] line = stream.readLine!(char[])(4096);
            if( line.length == 0 )
            {
                break;
            }
            sizediff_t colonPos = line.indexOf(':');
            if( colonPos < 0 )
            {
                throw new RequestException("Invalid request header. " ~ cast(string)line );
            }
            else
            {
                char[] dirtyKey = strip( line[0..colonPos] );
                toLowerInPlace( dirtyKey );
                char[] dirtyVal = strip( line[colonPos+1..$] );

                if( dirtyKey == "host" )
                {
                    sizediff_t portSeparator = dirtyVal.indexOf(':');
                    if( portSeparator > 0 )
                    {
                        char[] portString = dirtyVal[portSeparator+1..$];
                        try
                        {
                            ushort port = to!ushort(portString);
                            result.targetPort = port;
                            debug
                            {
                                debugLine ~= format("\n   port: %d", port);
                            }
                        }
                        catch(Throwable t)
                        {
                            throw new RequestException("Invalid port value on host");
                        }
                        dirtyVal = dirtyVal[0..portSeparator];
                    }
                }

                string key = cast(string) dirtyKey;
                string val = cast(string) dirtyVal;
                result.header[key] = val;
                debug
                {
                    debugLine ~= format("\n   %s: %s", key, val);
                }
            }
        }
        debug
        {
            logDebug(debugLine);
        }
    }

    void http1ExtractCommandLine(Connection connection, Request request)
    {
        auto stream = connection.stream;
        char[] line = stream.readLine!(char[])(65536);

        extractTalkingProtocol(line, request);
        extractCommandMethod(line, request);
        extractRequestUri(line, request);
    }

    void extractRequestUri(ref char[] line, Request request)
    {
        line = line.strip;
        sizediff_t questionPos = line.indexOf('?');
        if( questionPos >= 0 )
        {
            char[] params = line[questionPos+1 .. $];
            extractRequestParam(params, request);
            line = line[0..questionPos];
        }
        request.resourcePath = cast(string) unescapeUrlComponent(line);
    }

    void extractRequestParam(char[] line, Request request)
    {
        debug
        {
            string debugLine = "";
        }
        char[][] keyValues = line.split('&');
        foreach(char[] keyValue; keyValues)
        {
            string key, value;

            sizediff_t equalPos = keyValue.indexOf('=');
            if( equalPos > 0 )
            {
                char[] escapedKey = keyValue[0..equalPos];
                char[] escapedValue = keyValue[equalPos+1..$];
                key = cast(string) escapedKey.unescapeUrlComponent;
                value = cast(string) escapedValue.unescapeUrlComponent;
            }
            else
            {
                key = cast(string) keyValue.unescapeUrlComponent;
            }
            debug
            {
                debugLine ~= format("\n    %s:%s", key,value);
            }
            request.param[key] = value;
        }
        request.param.rehash;
        debug
        {
            logDebug(debugLine);
        }
    }

    void unknownTalkingProtocol()
    {
        throw new RequestException("Unknown talking protocol");
    }

    void extractCommandMethod(ref char[] line, Request request)
    {
        line = line.stripLeft;
        sizediff_t index = line.indexOf(' ');
        if( index < 0 )
        {
            unknownTalkingProtocol;
        }

        char[] commandMethod = line[0..index];
        toUpperInPlace(commandMethod);

        request.commandMethod = cast(string) commandMethod;
        line = line[index+1..$];
    }


    void extractTalkingProtocol(ref char[] line, Request request)
    {
        line = line.stripRight;
        sizediff_t index = lastIndexOf(line, ' ');
        if( index < 0 )
        {
            unknownTalkingProtocol;
        }
        
        char[] protocol = line[index+1..$];
        line = line[0..index];
        index = indexOf(line, '/');
        if( index < 0 )
        {
            unknownTalkingProtocol;
        }
        
        char[] protocolVersion = protocol[index+1..$];
        protocol = protocol[0..index];
        toUpperInPlace(protocol);
        
        if(protocol!="HTTP" && protocol!="HTTPS")
        {
            unknownTalkingProtocol;
        }

        request.talkingProtocol = cast(string) protocol;

        switch( protocolVersion )
        {
            case "1.0":
                request.protocolVersion = 1.0;
                break;
            case "1.1":
                request.protocolVersion = 1.1;
                break;
            default:
                if( protocolVersion.startsWith("1.") ){
                    request.protocolVersion = 1.1;
                    break;
                }
                unknownTalkingProtocol;
        }
    }


	void generateResponse(Context context)
	{
        Response response = context.response;
        response = "hi? my name is eko wahyudin";
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
