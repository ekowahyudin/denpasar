module denpasar.utils.array;

import std.traits;

void addItemSet(T)(ref T[] list, T item)
{
	for(sizediff_t i = list.length-1; i>=0; i--)
	{
		if( list[i] == item )
			return;
	}
	list ~= item;
}

void removeItemSet(T)(ref T[] list, T item)
{
	sizediff_t j = list.length - 1;
	for(sizediff_t i=j; i>=0; i--)
	{
		if( list[i] == item )
		{
			list[i] = list[j];
			static if( isPointer!T )
			{
				list[j] = null;
			}
			list.length = j;
			break;
		}
	}
}
