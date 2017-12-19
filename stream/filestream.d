module denpasar.stream.filestream;

import denpasar.stream.abstractstream;

import std.file;
import std.path;
import std.stdio;

enum FileMode{
	read,
	write,
	createIfNotExists,
	createNew
}

class FileStream : Stream
{
	this(OpenModes...)(string filename, OpenModes modes) 
    {
		bool isRead = false;
		bool isCreateIfNotExists = false;
		bool isCreateNew = false;
		foreach(mode; modes)
        {
			static if( is(typeof(mode) == FileMode)  )
            {
				if( mode == FileMode.read )
                {
					isRead = true;
				}
				else if( mode == FileMode.write )
                {
					isWrite = true;
				}
				else if ( mode == FileMode.createIfNotExists )
                {
					isCreateIfNotExists = true;
				}
				else if( mode == FileMode.createNew )
                {
					isCreateNew = true;
				}
			}
		}

		string fileMode;
		if( isCreateNew )
        {
			fileMode = "w";
		}
		else if( isCreateIfNotExists )
        {
			fileMode = exists(filename) ? "r" : "w";
		}
		if( isWrite )
        {
			fileMode ~= '+';
		}
		fileMode ~= 'b';

		file = File(filename, fileMode);
		fileName = filename;
	}

	~this()
    {
		close;
	}

	public string fileName() @property
    {
		return _fileName;
	}

protected:

    void fileName(string value) @property
    {
        _fileName = value;
    }

    override size_t rawGetAny(void* targetPtr, size_t bytes)
    {
        ubyte* ptr = cast(ubyte*) targetPtr;
        ubyte[] result = file.rawRead(ptr[0..bytes]);
        return result.length;
    }

    override size_t rawPutAny(immutable void* sourcePtr, size_t bytes)
    {
        ubyte* ptr = cast(ubyte*) sourcePtr;
        file.rawWrite(ptr[0..bytes]);
        return bytes;
    }

    override size_t rawSeek(SeekFrom from, sizediff_t delta)
    {
        if( from!=SeekFrom.currentPosition || delta!=0 ) 
        {
            file.seek(delta, seekFrom(from));
        }
        return file.tell;
    }

    override void rawClose()
    {
        file.close;
    }

    override void rawClear()
    {
        file.reopen(fileName, isForUpdate? "w+b" : "wb");
    }

private:
	bool isForUpdate = false;
	File file;
	string _fileName;

	pure int seekFrom(SeekFrom from){
		switch(from){
			case SeekFrom.end:
				return SEEK_END;
			case SeekFrom.currentPosition:
				return SEEK_CUR;
			case SeekFrom.begining:
			default:
				return SEEK_SET;
		}
	}
}
