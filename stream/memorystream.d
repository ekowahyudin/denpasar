module denpasar.stream.memorystream;

import denpasar.stream.basestream;

import std.algorithm;

class MemoryStream : Stream{
	mixin FlowableTemplate;

	~this(){
		close();
	}

	protected ubyte[] _data;
	private size_t _position=0;

	bool isSeekable() @property{
		return true;
	}

	size_t size() @property{
		return _data.length;
	}

	size_t position() @property{
		return _position;
	}

	void position(size_t value) @property{
		if( value <= size ){
			_position = value;
		}
		else{
			throwSeekingOutside();
		}
	}

	size_t seek(SeekFrom seekFrom, sizediff_t delta){
		switch(seekFrom){
			case SeekFrom.CURRENT:
				sizediff_t newPos = position + delta;
				if( newPos <0 )
					throwSeekingNegative;
				position = newPos;
				break;
			case SeekFrom.END:
				position = size;
				break;
			default:
				if( delta >= 0 ){
					position = cast(size_t) delta;
				}
				else{
					throwSeekingNegative;
				}
				break;
		}
		return position;
	}

	size_t readAny(void* targetPtr, size_t bytes){
		size_t pos = position;
		size_t bytesAvailable = size - pos;
		size_t copySize = min(bytesAvailable, bytes);
		if( copySize == 0 )
			return 0;
		ubyte* target = cast(ubyte*) targetPtr;
		target[0..copySize] = _data[pos..pos+copySize];
		position = position + copySize;
		return copySize;
	}

	size_t writeAny(void* sourcePtr, size_t bytes){
		auto result = bytes;
		ubyte* uPtr = cast(ubyte*) sourcePtr;
		size_t pos = position;
		if( pos < size ){
			size_t bytesOverlap = size-pos;
			size_t copySize = min(bytes, bytesOverlap);
			_data[pos..pos+copySize] = uPtr[0..copySize];
			bytes -= copySize;
			uPtr += copySize;
		}
		if( bytes > 0 ){
			_data ~= uPtr[0..bytes];
			position = _data.length;
		}
		return result;
	}

	void clear(){
		_data = null;
	}

	void close(){
		clear;
	}

	protected void throwSeekingNegative(){
		throw new StreamSeekException("Seeking to negative position");
	}

	protected void throwSeekingOutside(){
		throw new StreamSeekException("Seeking to outside of stream size");
	}

	protected void streamNotReady(){
		//imposible case on memory stream!
	}

	protected void dataNotReady(){
		throwSeekingOutside;
	}
}
