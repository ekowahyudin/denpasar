module denpasar.stream.memorystream;

import denpasar.stream.abstractstream;

import std.algorithm;

class MemoryStream : AbstractStream
{

	~this()
    {
		close();
	}

protected:
	override size_t rawSeek(SeekFrom seekFrom, sizediff_t delta)
    {
        if( seekFrom==SeekFrom.currentPosition && delta==0 )
        {
            return _position;
        }

        sizediff_t newPos = delta;
		switch(seekFrom)
        {
			case SeekFrom.currentPosition:
                newPos += _position;
                break;

            case SeekFrom.end:
                newPos += _data.length;
                break;

			default:
                break;
		}

        checkNewPosition(newPos);
        _position = newPos;
        return newPos;
	}

    override size_t rawReadAny(void* targetPtr, size_t bytes)
    {
        size_t pos = _position;
        size_t bytesAvailable = _data.length - pos;
        size_t copySize = min(bytesAvailable, bytes);
        
        if( copySize == 0 )
            return 0;
        
        ubyte* target = cast(ubyte*) targetPtr;
        target[0..copySize] = _data[pos..pos+copySize];
        _position += copySize;
        return copySize;
    }
    
    override size_t rawWriteAny(void* sourcePtr, size_t bytes)
    {
        auto result = bytes;
        ubyte* uPtr = cast(ubyte*) sourcePtr;
        size_t pos = _position;
        sizediff_t size = _data.length;
        if( pos < size )
        {
            size_t bytesOverlap = size-pos;
            size_t copySize = min(bytes, bytesOverlap);
            _data[pos..pos+copySize] = uPtr[0..copySize];
            bytes -= copySize;
            uPtr += copySize;
        }
        if( bytes > 0 )
        {
            _data ~= uPtr[0..bytes];
            position = _data.length;
        }
        return result;
    }

    override void rawClear()
    {
		_data = null;
	}

	override void rawClose()
    {
        _data = null;
	}

    void checkNewPosition(sizediff_t newPos)
    {
        if( newPos < 0 )
            negativeSeekError;
        if( newPos > _data.length )
            overSeekError;
    }

	void negativeSeekError(){
		throw new StreamSeekException("Seeking to negative position");
	}

	void overSeekError(){
		throw new StreamSeekException("Seeking to outside of stream size");
	}

	void streamNotReady(){
		//imposible case on memory stream!
	}

	void dataNotReady(){
		throwSeekingOutside;
	}

    void throwSeekingOutside()
    {
        throw new StreamSeekException("Seeking to outside of memory bound.");
    }

    ubyte[] _data;

private:
    size_t _position=0;

}
