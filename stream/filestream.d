module denpasar.stream.filestream;

import denpasar.stream.basestream;

import std.file;
import std.path;
import std.stdio;

enum FileMode{
	READ,
	WRITE,
	CREATE_IF_NOT_EXIST,
	CREATE_NEW
}

class FileStream : Stream{
	mixin FlowableTemplate;

	this(OpenModes...)(string filename, OpenModes modes) {
		bool isRead = false;
		bool isCreateIfNotExists = false;
		bool isCreateNew = false;
		foreach(mode; modes){
			static if( is(typeof(mode) == FileMode)  ){
				if( mode == FileMode.READ ){
					isRead = true;
				}
				else if( mode == FileMode.WRITE ){
					isWrite = true;
				}
				else if ( mode == FileMode.CREATE_IF_NOT_EXIST ){
					isCreateIfNotExists = true;
				}
				else if( mode == FileMode.CREATE_NEW ){
					isCreateNew = true;
				}
			}
		}

		string fileMode;
		if( isCreateNew ){
			fileMode = "w";
		}
		else if( isCreateIfNotExists ){
			fileMode = exists(filename) ? "r" : "w";
		}
		if( isWrite ){
			fileMode ~= '+';
		}
		fileMode ~= 'b';

		file = File(filename, fileMode);
		fileName = filename;
	}

	~this(){
		close;
	}

	string fileName() @property{
		return _fileName;
	}

	protected void fileName(string value) @property{
		_fileName = value;
	}

	bool isSeekable() @property{
		return true;
	}

	size_t size() @property{
		return file.size;
	}

	size_t position() @property{
		return file.tell;
	}

	void position(size_t pos) @property{
		seek(SeekFrom.BEGINING, cast(sizediff_t) pos);
	}

	size_t seek(SeekFrom from, sizediff_t delta){
		file.seek(delta, seekFrom(from));
		return position;
	}

	void close(){
		file.close;
	}

	void clear(){
		file.reopen(fileName, isForUpdate? "w+b" : "wb");
	}

	size_t readAny(void* targetPtr, size_t bytes){
		ubyte* ptr = cast(ubyte*) targetPtr;
		ubyte[] result = file.rawRead(ptr[0..bytes]);
		return result.length;
	}

	size_t writeAny(void* source, size_t bytes){
		ubyte* ptr = cast(ubyte*) source;
		file.rawWrite(ptr[0..bytes]);
		return bytes;
	}

protected:
	void dataNotReady(){
		//reading is failed so data is not ready
	}

	void streamNotReady(){
		//writing is failed so stream is not ready
	}

private:
	bool isForUpdate = false;
	File file;
	string _fileName;

	pure int seekFrom(SeekFrom from){
		switch(from){
			case SeekFrom.END:
				return SEEK_END;
			case SeekFrom.CURRENT:
				return SEEK_CUR;
			case SeekFrom.BEGINING:
			default:
				return SEEK_SET;
		}
	}
}
