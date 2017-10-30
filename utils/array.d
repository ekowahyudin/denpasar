module denpasar.utils.array;

import std.traits;

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
