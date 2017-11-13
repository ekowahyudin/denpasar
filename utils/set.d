module denpasar.utils.set;

import std.traits;

class SetOf(T) {

	this() nothrow
	{
        _data = null;
	}

	void opOpAssign(string op)(T item) if( op=="~" )
	{
		put(item);
	}

	void opOpAssign(string op)(T item) if( op=="-" )
	{
		remove(item);
	}

	int opApply(int delegate(ref T item) dg)
	{
		for(sizediff_t i=_data.length-1; i>=0; i--)
		{
			int ret = dg(_data[i]);
			if( ret != 0 )
			{
				return ret;
			}
		}
		return 0;
	}

	size_t count()
	{
		return _data.length;
	}

	void put(T item)
	{
		for(sizediff_t i=_data.length-1; i>=0; i--)
		{
			if( _data[i] == item )
			{
				return;
			}
		}
		_data ~= item;
	}

	void remove(T item)
	{
		for(sizediff_t i=_data.length - 1; i>=0; i--)
		{
			if( _data[i] == item )
			{
				removeByIndexNoValidate(i);
				return;
			}
		}
	}

	void removeByIndex(sizediff_t index)
	{
		validateIndex(index);
		removeByIndexNoValidate(index);
	}

	T get(size_t index)
	{
		return _data[index];
	}

	T pop(size_t index=0)
	{
		validateIndex(index);
		T result = _data[index];
		removeByIndexNoValidate(index);
		return result;
	}

protected:
	T[] _data;

	void removeByIndexNoValidate(sizediff_t index)
	{
		sizediff_t j = _data.length - 1;
		_data[index] = _data[j];
		static if( is(T:Object) || isPointer!T )
		{
			_data[j] = null;
		}
		_data.length = j;
	}

	void validateIndex(sizediff_t index, bool throwException = true)
	{
		if( index < 0 || index >= _data.length )
		{
			throw new Exception("Getting item out of bound");
		}
	}
}

class ThreadSaveSetOf(T) : SetOf!T
{
	this() nothrow
	{
		super();
	}

	override size_t count()
	{
		synchronized(this)
		{
			return super.count;
		}
	}

	override void put(T item)
	{
		synchronized(this)
		{
			super.put(item);
		}
	}

	override void remove(T item)
	{
		synchronized(this)
		{
			super.remove(item);
		}
	}

	override void removeByIndex(sizediff_t index)
	{
		synchronized(this)
		{
			super.removeByIndex(index);
		}
	}

	override T get(size_t index)
	{
		synchronized(this)
		{
			return super.get(index);
		}
	}

	override T pop(size_t index=0)
	{
		synchronized(this)
		{
			return super.pop(index); 
		}
	}
}