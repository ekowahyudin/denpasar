module denpasar.utils.array;

import std.algorithm;
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

T[] splitFirst(T, K)(T haystack, K splitter) if( (isArray!T || isSomeString!T) && (is(T==K) || is(ForeachType!T==K)) )
{
    T[] result = null;
    auto pos = countUntil(haystack, splitter);
    if( pos < 0 )
    {
        T empty;
        result ~= haystack;
        result ~= empty;
    }
    else
    {
        alias C = ForeachType!T;
        static if( is(C == K) ){
            const splitterLen = 1;
        }
        else{
            immutable splitterLen = splitter.length;
        }
        result ~= haystack[0..pos];
        result ~= haystack[pos+splitterLen..$];
    }
    return result;
}