module denpasar.utils.logger;

import std.datetime;
import std.stdio;
import std.string;

void log(string severity)(string s) nothrow
{
    try
    {
        string timestamp = Clock.currTime(UTC()).toISOString;
        timestamp = timestamp[9..$];
        timestamp.length = 13;
        string output = format("%-20s %-10s %s", timestamp, severity, s);
        writeln(output);
    }
    catch(Throwable t)
    {

    }
}

void logDebug(Args...)(string s, Args args) nothrow
{
    debug
    {
        try
        {
            log!"debug"(format(s, args));
        }
        catch(Throwable t)
        {

        }

    }
}

void logError(Args...)(string s, Args args) nothrow
{
    try
    {
        log!"error"(format(s, args));
    }
    catch(Throwable t)
    {

    }
}
