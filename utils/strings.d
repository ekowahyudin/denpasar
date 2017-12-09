module denpasar.utils.strings;

import std.conv;
import std.traits;

S unescapeUrlComponent(S)(S input) if( isArray!S && isSomeChar!(ForeachType!S) )
{
    alias C = ForeachType!S;
    bool escape = false;
    sizediff_t j = input.length;
    sizediff_t target = 0;
    C[2] hex;
    sizediff_t hexIndex=0;
    for(sizediff_t i=0; i<j; i++)
    {
        C c = input[i];
        switch(c)
        {
            case '+':
                input[target++] = ' ';
                continue;
            case '%':
                escape = true;
                continue;
            default:
                if( escape )
                {
                    hex[hexIndex++] = c;
                    if( hexIndex == 2 )
                    {
                        string ss = cast(string) hex;
                        int ii = parse!int(ss,16);
                        C c2 = cast(C) ii;
                        input[target++] = c2;
                        hexIndex = 0;
                        escape = false;
                    }
                    break;
                }
                input[target++] = c;
        }
    }
    return input[0..target];
}
