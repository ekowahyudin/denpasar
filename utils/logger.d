module denpasar.utils.logger;

import std.datetime;
import std.stdio;
import std.string;

void log(string severity)(string s)
{
    string timestamp = Clock.currTime(UTC()).toISOString;
    timestamp = timestamp[9..$];
    timestamp.length = 13;
    string output = format("%-20s %-10s %s", timestamp, severity, s);
    writeln(output);
}

void logDebug(Args...)(string s, Args args)
{
    debug
    {
        log!"debug"(format(s, args));
    }
}

void logError(Args...)(string s, Args args)
{
    log!"error"(format(s, args));
}
