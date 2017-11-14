module denpasar.stream.basestream;

import std.bitmanip;
import std.traits;

enum SeekFrom{
	BEGINING,
	CURRENT,
	END
}

interface Flowable{
	bool isSeekable() @property;
	bool isLittleEndian() @property;
	void isLittleEndian(bool) @property;
	bool isSameEndian() @property;
	size_t size() @property;
	size_t position() @property;
	void close();
}

interface Seekable{
	void position(size_t) @property;
	size_t seek(SeekFrom, sizediff_t delta);
}

interface Readable : Flowable{
	size_t readAny(void* targetPtr, size_t bytes);

	protected void dataNotReady();

	void readExact(P)(P ptr, size_t bytes) if( isPointer!P ){
		ubyte* ubPtr = cast(ubyte*) ptr;
		for(; bytes > 0; dataNotReady ){
			auto r = readAny(ubPtr, bytes);
			ubPtr += r;
			bytes -= r;
		}
	}

	T read(T)() if( isNumeric!T || isSomeChar!T ){
		if( T.sizeof==1 || isSameEndian ){
			T result;
			readExact(&result, T.sizeof);
			return result;
		}
		else{
			ubyte[T.sizeof] buf;
			readExact(buf.ptr, T.sizeof);
			return isLittleEndian ? 
				littleEndianToNative!T(buf) : 
				bigEndianToNative!T(buf);
		}
	}

    T read(T)(bool delegate(ref ForeachType!T[] buf) continueLoop ) if( isArray!T || isSomeString!T ){
		alias C = ForeachType!T;
		C[] buf;
		while( continueLoop(buf) ){
			C c = read!C;
			buf ~= c;
		}
		return cast(T) buf;
	}

	T read(T)(size_t nElement) if( isArray!T || isSomeString!T ){
		alias C = ForeachType!T;
		C[] array;
		while(nElement > 0){
			C c = read!C;
			array ~= c;
			nElement--;
		}
		return cast(T)array;
	}

	T readLine(T)() if( isSomeString!T ){
		alias C = ForeachType!T;
		C[] result;
		while(true){
			C c = read!C;

			//ignore '\r'
			if( c == '\r' )
				continue;
			if( c == '\n' )
				break;

			result ~= c;
		}
		return cast(T) result;
	}
}

interface Writable : Flowable{

	size_t writeAny(void* source, size_t bytes);

	void clear();

	protected void streamNotReady();

	void writeExact(P)(P source, size_t bytes) if( isPointer!P ){
		ubyte* src = cast(ubyte*) source;
		for(;bytes>0; streamNotReady){
			size_t written = writeAny(src, bytes);
			bytes -= written;
			src += written;
		}
	}

	void write(T)(T value) if( isNumeric!T || isSomeChar!T ){
		if( T.sizeof == 1 || isSameEndian ){
			writeExact(&value, T.sizeof);
		}
		else{
			ubyte[T.sizeof] temp = isLittleEndian ? nativeToLittleEndian(value) : nativeToBigEndian(value);
			writeExact(temp.ptr, T.sizeof);
		}
	}

	void write(S)(S str) if( isArray!S || isSomeString!S ){
		alias C = ForeachType!S;
		if( C.sizeof == 1 || isSameEndian ){
			writeExact(str.ptr, s.length * C.sizeof);
		}
		else{
			foreach(C c; str){
				write(c);
			}
		}
	}

	void opAssign(S)(S str) if( isArray!S || isSomeString!S){
		clear();
		write(s);
	}

	void opOpAssign(string op, S)(S str) if( op=="~" && (isArray!S || isSomeString!S) ){
		write(s);
	}
}

interface Stream : Readable, Writable, Seekable{

}

mixin template FlowableTemplate(){

	version(LittleEndian){
		private bool _isLittleEndian = true;
	}
	else{
		private bool _isLittleEndian = false;
	}

	bool isLittleEndian() @property{
		return _isLittleEndian;
	}

	void isLittleEndian(bool value) @property{
		_isLittleEndian = value;
	}

	bool isSameEndian() @property{
		version(LittleEndian){
			return isLittleEndian;
		}
		else{
			return !isLittleEndian;
		}
	}

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