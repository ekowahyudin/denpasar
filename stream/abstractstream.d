//TODO chunked read/write stream
module denpasar.stream.abstractstream;

import denpasar.base.classes;
import denpasar.core.kernel;
import denpasar.utils.set;

import std.ascii;
import std.bitmanip;
import std.traits;

/**
 * Set of seek mode
 */
enum SeekFrom
{
    /**
     * from begining of stream
     */
	begining,
    /**
     * from current position of stream
     */
	currentPosition,
    /**
     * from end of stream
     */
	end
}

/**
 * Throw this class if somthing wrong with stream
 */
class StreamException : Exception
{
    /**
     * constructor
     */
	this(string message, string file=__FILE__, size_t line=__LINE__)
    {
		super(message, file, line);
	}
}

/**
 * Indicate if stream is error when seeking operation
 */
class StreamSeekException : StreamException
{
    /**
     * constructor
     */
	this(string message, string file=__FILE__, size_t line=__LINE__){
		super(message, file, line);
	}
}

/**
 * Throw StreamWrietException if someting error when write into stream operation
 */
class StreamWriteException : StreamException
{
    /**
     * constructor
     */
    this(string message, string file=__FILE__, size_t line=__LINE__)
    {
        super(message, file, line);
    }
}

/**
 * THrow StreamReadException if something error when performing reading operation
 */
class StreamReadException : StreamException
{
    /**
     * constructor
     */
    this(string message, string file=__FILE__, size_t line=__LINE__)
    {
        super(message, file, line);
    }
}

/**
 * basic of stream
 */
interface IAbstractStream
{
    /**
     * indicate if stream and current system has same endian
     */
    bool isSameEndian() @property;

    /**
     * return true if stream in little endian mode
     */
    bool isLittleEndian() @property;
    
    /**
     * set stream in little endian or not
     */
    void isLittleEndian(bool) @property;
    
    /**
     * return true if stream is readable
     */
    bool isReadable() @property;

    /**
     * set the stream is readable or not
     */
    void isReadable(bool) @property;
    
    /**
     * get the stream is writable or not
     */
    bool isWritable() @property;

    /**
     * set the stream is writable or not
     */
    void isWritable(bool) @property;
    
    /**
     * get the stream is seekable or not
     */
    bool isSeekable() @property;

    /**
     * set the stream is seekable or not
     */
    void isSeekable(bool) @property;
    
    /**
     * get the stream has valid size or not
     */
    bool hasSize() @property;
    
    /**
     * set the stream has valid size or not
     */
    void hasSize(bool) @property;
    
    /**
     * make the stream empty
     */
    void clear();

    /**
     * close the stream
     */
    void close();
}

/**
 * Readable stream interface
 */
interface IReceivableStream : IAbstractStream
{
    /**
     * event callback when reading operation but no data received
     */
    public void onDataNotReady(EventNotify) @property;

    /**
     * read any bytes from buffer and from lowlevel stream
     */
    public size_t getAny(void* targetPtr, size_t bytes);

    /**
     * unread data
     */
    public void unget(void* sourcePtr, size_t bytes);

    /**
     * read exact n bytes, into pointer
     */
    public void getExact(void* targetBuffer, size_t bytes);

    ////////////////////////// templates /////////////////////////

    /**
     * clean white space at front of stream, with reading unit C
     */
    void stripLeft(C)() if( isSomeChar!C )
    {
        while(true)
        {
            C c = read!C();
            if( !isWhite(c) )
            {
                unread(c);
                break;
            }
        }
    }

    /**
     * get numeric (integer or float) or characters
     */
    public T get(T)() if( isNumeric!T || isSomeChar!T )
    {
        if( T.sizeof == 1 || isSameEndian )
        {
            T result;
            getExact(&result, T.sizeof);
            return result;
        }
        else
        {
            ubyte[T.sizeof] buf;
            getExact(buf.ptr, T.sizeof);
            return isLittleEndian ? littleEndianToNative!T(buf) : bigEndianToNative!T(buf);
        }
    }

    /**
     * get string by n elements
     */
    public T get(T)(size_t n) if( isSomeString!T || isArray!T )
    {
        alias C = ForeachType!T;
        C[] result;
        if( T.sizeof == 1 || isSameEndian )
        {
            getExact(result.ptr, n*T.sizeof);
        }
        else
        {
            for(; n>0; n--)
            {
                C c = get!C;
                result ~= c;
            }
        }
        return cast(T) result;
    }

    /**
     * get array or string, with custom stop condition
     */
    public T get(T, C)( bool delegate(ref C[]) shouldContinue ) 
    if( (isArray!T || isSomeString!T) && is(ForeachType!T == C) )
    {
        C[] result;
        while( shouldContinue(result) )
        {
            C c = get!C;
            result ~= c;
        }
        return cast(T) result;
    }

    /**
     * get array or string from stream until got '\r\n', '\n' or '\r'
     */
    public T getLine(T)(size_t maxChar=size_t.max) if( isArray!T || isSomeString!T )
    {
        alias C = ForeachType!T;
        C[] result;
        C lastChar;
    loop:
        while(result.length < maxChar)
        {
            C c = get!C;
            switch(c)
            {
                case '\n':
                    break loop;
                case '\r':
                    lastChar = c;
                    break;
                default:
                    if( lastChar == '\r' )
                    {
                        unget(c);
                        break loop;
                    }
                    lastChar = c;
                    result ~= c;
                    break;
            }
        }
        return cast(T) result;
    }

    /**
     * unread numeric / characters
     */
    void unget(C)(C c) if( isNumeric!C || isSomeChar!C )
    {
        if( C.sizeof == 1 || isSameEndian )
        {
            unget(&c, C.sizeof);
        }
        else
        {
            ubyte[C.sizeof] buf = isLittleEndian? nativeToLittleEndian(c) : nativeToBigEndian(c);
            unget(buf.ptr, C.sizeof);
        }
    }

    /**
     * unread string or array
     */
    void unget(S)(S str) if( isArray!S || isSomeString!S )
    {
        alias C = ForeachType!S;
        foreach_reverse(C c; str)
        {
            unget(c);
        }
    }
}

/**
 * interface of storable stream
 */
interface IStorableStream : IAbstractStream
{
    /**
     * event callback during write operation but stream is not ready
     */
    public void onStreamNotReady(EventNotify) @property;
    
    /**
     * put any data to the stream by size, return number of bytes written
     */
    public size_t putAny(immutable void* sourcePtr, size_t bytes);
    
    /**
     * write extact n bytes
     */
    public void putExact(Ptr)(Ptr sourcePtr, size_t bytes) if( isPointer!Ptr )
    {
        if( bytes == 0 )
            return;
        while(true)
        {
            size_t written = putAny(cast(immutable(void*)) sourcePtr, bytes);
            bytes -= written;
            if( bytes <= 0 )
            {
                break;
            }
            yieldWaitForStream();
        }
    }

    /**
     * put integer/float or character type
     */
    public void put(T)(T data) if( isNumeric!T || isSomeChar!T )
    {
        if( T.sizeof == 1 || isSameEndian )
        {
            putExact(&data, T.sizeof);
        }
        else
        {
            immutable ubyte[T.sizeof] temp = isLittleEndian? nativeToLittleEndian(data) : nativeToBigEndian(data);
            putExact(temp.ptr, T.sizeof);
        }
    }

    /**
     * put array or string into stream
     */
    public void put(T, Args...)(T str, Args args) if( isSomeString!T || isArray!T )
    {
        import std.string;
        T data = args.length == 0? cast(T)str : cast(T)format(str, args);
        alias C = ForeachType!T;
        if( C.sizeof == 1 || isSameEndian )
        {
            putExact(data.ptr, data.length * C.sizeof );
        }
        else
        {
            foreach(C c; data)
            {
                put(c);
            }
        }
    }

    public void put(S)(S stream) if( is(S==IReceivableStream))
    {
        ubyte[1024] buf;
        size_t bufSize;
        while( !stream.isEndOfStream )
        {
            bufSize = stream.getAny(buf.ptr, buf.length);
            putExact(buf.ptr, bufSize);
        }
    }

    /**
     * put array or string into stream, length will put first
     */
    public void putArray(T)(T data) if( isSomeString!T || isArray!T )
    {
        alias C = ForeachType!T;
        immutable uint len = data.length;
        put(len);
        put(data);
    }

    public void opOpAssign(string op,S)(S s) if(isSomeString!S && op=="~")
    {
        if( isSeekable )
        {
            ISeekableStream seekableStream = cast(ISeekableStream) this;
            if( seekableStream !is null )
            {
                seekableStream.seek(SeekFrom.end, 0);
            }
        }

        put(s);
    }

protected:
    void yieldWaitForStream();
}

/**
 * Seekable Stream Interface
 */
interface ISeekableStream : IAbstractStream
{
    size_t position() @property;
    void position(size_t) @property;

    /**
     * perform seek of cursor position
     */
    size_t seek(SeekFrom from, sizediff_t delta);
}

/**
 * has property size
 */
interface IHasSize
{
    /**
     * get size of stream
     */
    size_t size() @property;
}

/**
 * abstract stream class
 */
abstract class Stream: IAbstractStream, IReceivableStream, IStorableStream, ISeekableStream, IHasSize
{
public:
    /**
     * constructor
     */
    this()
    {
        _onDataNotReady = new SetOf!EventNotify;
    }

    ~this()
    {
        _onDataNotReady.destroy;
    }

    public void onDataNotReady(EventNotify callback) @property
    {
        _onDataNotReady ~= callback;
    }

    public void onStreamNotReady(EventNotify callback) @property
    {
        _onStreamNotReady ~= callback;
    }

    bool isReadable() @property
    {
        return _isReadable;
    }

    void isReadable(bool value) @property
    {
        _isReadable = value;
    }

    bool isWritable() @property
    {
        return _isWritable;
    }
    void isWritable(bool value) @property
    {
        _isWritable = value;
    }

    bool isSeekable() @property
    {
        return _isSeekable;
    }
    void isSeekable(bool value) @property
    {
        _isSeekable = value;
    }

    bool isSameEndian() @property
    {
        version(LittleEndian)
        {
            return isLittleEndian;
        }
        else
        {
            return !isLittleEndian;
        }
    }

    bool isLittleEndian() @property
    {
        return _isLittleEndian;
    }

    void isLittleEndian(bool value) @property
    {
        _isLittleEndian = value;
    }

    bool hasSize() @property
    {
        return _hasSize;
    }
    void hasSize(bool value) @property
    {
        _hasSize = value;
    }

    /**
     * read any bytes to buffer and from lowlevel stream
     */
    size_t getAny(void* targetPtr, size_t bytes)
    {
        ubyte* ptr = cast(ubyte*) targetPtr;
        sizediff_t j = _ungetData.length - 1;
        size_t result = 0;
        while(j >= 0 && bytes > 0)
        {
            *(ptr++) = _ungetData[j];
            _ungetData.length = j--;
            --bytes;
            ++result;
        }
        return result + rawGetAny(targetPtr, bytes);
    }

    /**
     * read exact number amount of bytes
     */
    public void getExact(void* targetBuffer, size_t bytes)
    {
        ubyte* ptr = cast(ubyte*) targetBuffer;
        while(true)
        {
            size_t read = getAny(ptr, bytes);
            bytes -= read;
            ptr += read;
            if( bytes == 0 )
            {
                break;
            }
            yieldWaitForData;
        }
    }

    public void unget(void* sourcePtr, size_t bytes)
    {
        ubyte* ptr = cast(ubyte*) sourcePtr;
        foreach_reverse(ubyte b; ptr[0..bytes])
        {
            _ungetData ~= b;
        }
    }

    /**
     * write any bytes from buffer into low level stream
     */
    size_t putAny(immutable void *sourcePtr, size_t bytes)
    {
        return rawPutAny(sourcePtr, bytes);
    }

    size_t position() @property
    {
        return seek(SeekFrom.currentPosition, 0);
    }

    void position(size_t value) @property
    {
        seek(SeekFrom.begining, value);
    }

    size_t seek(SeekFrom from, sizediff_t delta)
    {
        switch(from)
        {
            case SeekFrom.begining:
                if( delta < 0 )
                {
                    throw new StreamSeekException("Unable seeking to negative position");
                }
                break;
            case SeekFrom.end:
                if( delta > 0 )
                {
                    throw new StreamSeekException("Unable seeking to outside of stream");
                }
                break;
            default:
                break;
        }
        return rawSeek(from, delta);
    }

    size_t size() @property
    {
        size_t currentPos = position;
        size_t result = seek(SeekFrom.end, 0);
        position = currentPos;
        return result;
    }

    void close() @property
    {
        rawClose();
    }

    void clear() @property
    {
        rawClear();
    }

protected:
    void yieldWaitForData()
    {
        fireEvent(_onDataNotReady, this);
    }

    void yieldWaitForStream()
    {
        fireEvent(_onStreamNotReady, this);
    }

    void seekError()
    {
        throw new StreamSeekException("Unable seeking "~className);
    }

    void writeError()
    {
        throw new StreamWriteException("Unable write into stream "~className);
    }

    void readError()
    {
        throw new StreamReadException("Unable read from stream "~className);
    }

    string className() @property
    {
        return this.classinfo.name;
    }

    abstract size_t rawGetAny(void* targetPtr, size_t bytes);
    abstract size_t rawPutAny(immutable void* sourcePtr, size_t bytes);
    abstract size_t rawSeek(SeekFrom from, sizediff_t delta);
    abstract void rawClose();
    abstract void rawClear();
private:
    ubyte[] _ungetData;
    version(LittleEndian)
    {
        bool _isLittleEndian = true;
    }
    else
    {
        bool _isLittleEndian = false;
    }
    bool _isReadable = true;
    bool _isWritable = true;
    bool _isSeekable = true;
    bool _hasSize = true;
    SetOf!EventNotify _onDataNotReady;
    SetOf!EventNotify _onStreamNotReady;
}