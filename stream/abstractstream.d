//TODO chunked read/write stream
module denpasar.stream.abstractstream;

import std.bitmanip;
import std.traits;
import std.ascii;
import denpasar.base.classes;
import denpasar.core.kernel;
import denpasar.utils.set;

enum SeekFrom{
	begining,
	currentPosition,
	end
}

class StreamException : Exception{
	this(string message, string file=__FILE__, size_t line=__LINE__){
		super(message, file, line);
	}
}

class StreamSeekException : StreamException{
	this(string message, string file=__FILE__, size_t line=__LINE__){
		super(message, file, line);
	}
}

class StreamWriteException : StreamException
{
    this(string message, string file=__FILE__, size_t line=__LINE__)
    {
        super(message, file, line);
    }
}

class StreamReadException : StreamException
{
    this(string message, string file=__FILE__, size_t line=__LINE__)
    {
        super(message, file, line);
    }
}


interface IBaseStream
{
    bool isSameEndian() @property;
    bool isLittleEndian() @property;
    void isLittleEndian(bool) @property;
    bool isReadable() @property;
    void isReadable(bool) @property;
    bool isWritable() @property;
    void isWritable(bool) @property;
    bool isSeekable() @property;
    void isSeekable(bool) @property;
    bool hasSize() @property;
    void hasSize(bool) @property;
    void clear();
    void close();
}

interface IReadableStream : IBaseStream
{
    public void onWaitForDataReady(EventNotify) @property;

    /**
     * read any bytes from buffer and from lowlevel stream
     */
    public size_t readAny(void* targetPtr, size_t bytes);

    /**
     * unread data
     */
    public void unread(void* sourcePtr, size_t bytes);

    /**
     * read exact n bytes, into pointer
     */
    public void readExact(void* targetBuffer, size_t bytes);

    /**
     * clean white space at front of stream
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
     * read numeric (integer or float) or characters
     */
    public T read(T)() if( isNumeric!T || isSomeChar!T )
    {
        if( T.sizeof == 1 || isSameEndian )
        {
            T result;
            readExact(&result, T.sizeof);
            return result;
        }
        else
        {
            ubyte[T.sizeof] buf;
            readExact(buf.ptr, T.sizeof);
            return isLittleEndian ? littleEndianToNative!T(buf) : bigEndianToNative!T(buf);
        }
    }

    /**
     * read string by n elements
     */
    public T read(T)(size_t n) if( isSomeString!T || isArray!T )
    {
        alias C = ForeachType!T;
        C[] result;
        if( T.sizeof == 1 || isSameEndian )
        {
            readExact(result.ptr, n*T.sizeof);
        }
        else
        {
            for(; n>0; n--)
            {
                C c = read!C;
                result ~= c;
            }
        }
        return cast(T) result;
    }

    public T read(T, C)( bool delegate(ref C[]) shouldContinue ) if( is(ForeachType!T == C) )
    {
        alias C = ForeachType!T;
        C[] result;
        while( shouldContinue(result) )
        {
            C c = read!C;
            result ~= c;
        }
        return cast(T) result;
    }

    public T readLine(T)(size_t maxChar=size_t.max)if( isSomeString!T )
    {
        alias C = ForeachType!T;
        C[] result;
        C lastChar;
    loop:
        while(result.length < maxChar)
        {
            C c = read!C;
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
                        unread(c);
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
    void unread(C)(C c) if( isNumeric!C || isSomeChar!C )
    {
        if( C.sizeof == 1 || isSameEndian )
        {
            unread(&c, C.sizeof);
        }
        else
        {
            ubyte[C.sizeof] buf = isLittleEndian? nativeToLittleEndian(c) : nativeToBigEndian(c);
            unread(buf.ptr, C.sizeof);
        }
    }

    /**
     * unread string or array
     */
    void unread(S)(S str) if( isArray!S || isSomeString!S )
    {
        foreach_reverse(C c; str)
        {
            unread(&c, C.sizeof);
        }
    }
}

interface IWritableStream : IBaseStream
{
    public void onWaitForDataReady(EventNotify) @property;
    public size_t writeAny(immutable void* sourcePtr, size_t bytes);
    public void writeExact(immutable void* sourcePtr, size_t bytes);

    public void write(T)(T data) if( isNumeric!T || isSomeChar!T )
    {
        if( T.sizeof == 1 || isSameEndian )
        {
            writeExact(&data, T.sizeof);
        }
        else
        {
            ubyte[T.sizeof] temp = isLittleEndian? nativeToLittleEndian(data) : nativeToBigEndian(data);
            writeExact(&data, T.sizeof);
        }
    }

    public void write(T)(T data) if( isSomeString!T || isArray!T )
    {
        alias C = ForeachType!T;
        if( C.sizeof == 1 || isSameEndian )
        {
            writeExact(data.ptr, data.length * T.sizeof );
        }
        else
        {
            foreach(C c; data)
            {
                write(c);
            }
        }
    }

    public void writeArray(T)(T data) if( isSomeString!T || isArray!T )
    {
        alias C = ForeachType!T;
        uint len = data.length;
        write(len);
        write(data);
    }
}

interface ISeekableStream : IBaseStream
{
    size_t size() @property;
    size_t position() @property;
    void position(size_t) @property;
    size_t seek(SeekFrom from, sizediff_t delta);
}

abstract class AbstractStream: IBaseStream, IReadableStream, IWritableStream
{
public:
    this()
    {
        _onWaitForDataReady = new SetOf!EventNotify;
    }

    ~this()
    {
        _onWaitForDataReady.destroy;
    }

    public void onWaitForDataReady(EventNotify callback) @property
    {
        _onWaitForDataReady ~= callback;
    }

    public void onWaitForStreamReady(EventNotify callback) @property
    {
        _onWaitForStreamReady ~= callback;
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
    size_t readAny(void* targetPtr, size_t bytes)
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
        return result + rawReadAny(targetPtr, bytes);
    }

    /**
     * read exact number amount of bytes
     */
    public void readExact(void* targetBuffer, size_t bytes)
    {
        ubyte* ptr = cast(ubyte*) targetBuffer;
        while(true)
        {
            size_t read = readAny(ptr, bytes);
            bytes -= read;
            ptr += read;
            if( bytes == 0 )
            {
                break;
            }
            yieldWaitForData;
        }
    }

    public void unread(void* sourcePtr, size_t bytes)
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
    size_t writeAny(immutable void *sourcePtr, size_t bytes)
    {
        return rawWriteAny(sourcePtr, bytes);
    }

    public void writeExact(immutable void* sourcePtr, size_t bytes)
    {
        if( bytes == 0 )
            return;
        while(true)
        {
            size_t written = writeAny(sourcePtr, bytes);
            bytes -= written;
            if( bytes <= 0 )
            {
                break;
            }
            yieldWaitForStream();
        }
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
        fireEvent(_onWaitForDataReady, this);
    }

    void yieldWaitForStream()
    {
        fireEvent(_onWaitForStreamReady, this);
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

    abstract size_t rawReadAny(void* targetPtr, size_t bytes);
    abstract size_t rawWriteAny(immutable void* sourcePtr, size_t bytes);
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
    SetOf!EventNotify _onWaitForDataReady;
    SetOf!EventNotify _onWaitForStreamReady;
}