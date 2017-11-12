module denpasar.core.kernel;

import core.sync.condition;
import core.sync.mutex;
import core.thread;
import denpasar.base.classes;
import denpasar.utils.set;
import std.meta;
import std.stdio;
import std.traits;

abstract class Task : Executable{
	enum Status:byte{
		detached,
		queued,
		executing,
		done
	}

	this() nothrow
	{
		synchronized
		{
			_id = ++_nextTaskId;
		}
	}

	~this()
	{
		debug(KernelTask){
			writefln("Task destroyed");
		}
	}

	long id()
	{
		return _id;
	}
	
	public Status status() @property{
		return _status;
	}

	public void status(Status value) @property{
		_status = value;
	}

	public Throwable thrownObject() @property{
		return _thrownObject;
	}

	public void thrownObject(Throwable value) @property{
		_thrownObject = value;
	}

	public bool isParallelTask() nothrow @property 
	{
		return _isParallelTask;
	}

	public sizediff_t priority() nothrow @property
	{
		return _priority;
	}

	public void priority(sizediff_t value) nothrow @property
	{
		_priority = value;
	}

	public void onSuccess(void delegate() dg) @property
	{
		installEvent(_onSuccessSet, dg);
	}

	public void onSuccess(void delegate(Throwable) dg) @property
	{
		installEvent(_onSuccessThrownSet, dg, thrownObject);
	}

	public void onFailure(void delegate(Exception) dg) @property
	{
		synchronized(this)
		{
			Exception ex = cast(Exception) this.thrownObject;
			installEventNoSync(_onFailureSet, dg, ex);
		}
	}

	public void onDone(void delegate() dg) @property
	{
		installEvent(_onDoneSet, dg);
	}

	public void onDone(void delegate(Throwable) dg) @property
	{
		installEvent(_onDoneThrownSet, dg, this.thrownObject);
	}

protected:

	void installEvent(Pool, Callback, Args...)(Pool pool, Callback callback, Args args)
	{
		synchronized(this)
		{
			installEventNoSync(pool,callback,args);
		}
	}

	void installEventNoSync(Pool, Callback, Args...)(ref Pool pool, Callback callback, Args args)
	{
		if( !invokeOnDone(callback, args) )
		{
			if( pool is null )
			{
				pool = new Pool;
			}
			pool ~= callback;
		}
	}

	bool invokeOnDone(Func,Args...)(Func func, Args args)
	{
		if( status == Status.done )
		{
			if( isParallelTask )
			{
				parallelTask(func, args);
			}
			else
			{
				futureTask(func, args);
			}
			return true;
		}
		return false;
	}

	size_t queueNumber() nothrow{
		return _queueNumber;
	}
	
	void queueNumber(size_t value) nothrow{
		_queueNumber = value;
	}

	protected void execute()
	{
		auto taskManager = TaskManager.instance;
		taskManager.detachTask(this);
		
		Fiber fiber = _fiber;
		if( fiber is null )
		{
			_fiber = fiber = taskManager.borrowFiber;
			fiber.reset(&rawExecute);
		}
		try
		{
			status = Status.executing;
			fiber.call;
		}
		catch(Throwable t)
		{
			thrownObject = t;
		}
		
		if( fiber.state == Fiber.State.TERM )
		{
			taskManager.recycleFiber(fiber);
			synchronized(this)
			{
				status = Status.done;
				fireFulfilled();
			}
		}
		else{
			//submit for next time execution
			taskManager.submit(this);
		}
	}

	abstract void rawExecute();

	void fireFulfilled()
	{
		Exception ex = cast(Exception) thrownObject;
		if( ex !is null )
		{
			fireFailure(ex);
		}
		else
		{
			fireSuccess();
		}
		fireDone();
	}

	void fireFailure(Exception ex)
	{
		fireCallback(_onFailureSet,ex);
	}

	void fireSuccess()
	{
		fireCallback(_onSuccessThrownSet, this.thrownObject);
		fireCallback(_onSuccessSet);
	}

	void fireDone()
	{
		fireCallback(_onDoneThrownSet, this.thrownObject);
		fireCallback(_onDoneSet);
	}

	void fireCallback(Delegates, Args...)(Delegates dgs, Args args)
	{
		if( isParallelTask )
		{
			foreach(void delegate(Args) dg; dgs)
			{
				parallelTask(dg, args);
			}
		}
		else
		{
			foreach(void delegate(Args) dg; dgs)
			{
				futureTask(dg, args);
			}
		}
	}

private:
	SetOf!(void delegate(Exception)) _onFailureSet;
	SetOf!(void delegate()) _onSuccessSet;
	SetOf!(void delegate(Throwable)) _onSuccessThrownSet;
	SetOf!(void delegate()) _onDoneSet;
	SetOf!(void delegate(Throwable)) _onDoneThrownSet;

	Fiber _fiber;
	size_t _queueNumber;
	sizediff_t _priority = 1;
	bool _isParallelTask = false;
	shared Status _status=Status.detached;
	Throwable _thrownObject=null;
	Task _next;
	Task _prev;
	long _id=0;

	__gshared
	{
		static long _nextTaskId=0;
	}
}

class FuncTask(Result) : Task{
	this() nothrow
	{
		super();
		_onDoneSet = new SetOf!(void delegate(FuncTask!Result))();
		_onThisSuccessSet = new SetOf!(void delegate(FuncTask!Result))();
		static if( !is(Result==void) )
		{
			_onSuccessResultSet = new SetOf!(void delegate(Result))();
		}
	}

	~this()
	{
		_onDoneSet.destroy;
	}

	static if( !is(Result == void))
	{
		private Result _result;

		public Result result() @property
		{
			return _result;
		}

		public void result(Result value) @property
		{
			_result = value;
		}
	}

	public Result workForce()
	{
		bool firstTime = true;
		while(status != Status.done)
		{
			execute;
			if( firstTime ){
				firstTime = false;
			}
			else{
				TaskManager.instance.runOnce;
			}
		}
		static if( !is(Result==void) )
		{
			return result;
		}
	}

	public Result wait()
	{
		while( status != Status.done )
		{
			if( TaskManager.instance.runOnce )
			{
				execute;
			}
		}
		static if( !is(Result==void) )
		{
			return result;
		}
	}

	alias onDone = super.onDone;
	alias onSuccess = super.onSuccess;

	void onDone(void delegate(FuncTask!Result) dg) @property
	{
		synchronized(this)
		{
			if( status == Status.done )
			{
				if( isParallelTask )
				{
					parallelTask(dg, this);
				}
				else
				{
					futureTask(dg, this);
				}
			}
			else
			{
				_onDoneSet ~= dg;
			}
		}
	}

protected:
	override protected void fireDone()
	{
		super.fireDone;
		fireEvent(_onDoneSet, this);
	}

	override protected void fireSuccess()
	{
		super.fireSuccess;
		static if( !is(Result==void) )
		{
			fireEvent(_onSuccessResultSet, this.result);
		}
		fireEvent(_onThisSuccessSet, this);
	}

private:
	SetOf!(void delegate(FuncTask!Result)) _onDoneSet;
	SetOf!(void delegate(FuncTask!Result)) _onThisSuccessSet;
	static if(!is(Result==void))
	{
		SetOf!(void delegate(Result)) _onSuccessResultSet;
	}
}

class FuncTaskImpl(Result, Func, Args...) : FuncTask!Result
{	
	this(Func func, Args args) nothrow
	{
		super();
		_func = func;
		_args = args;
	}
	
	protected override void rawExecute()
	{
		static if( is(Result==void) )
		{
			_func(_args);
		}
		else
		{
			result = _func(_args);
		}
	}
	
private:
	Func _func;
	Args _args;
}


class TaskManager{
	protected this() nothrow{
		_fiberMutex = new Mutex;
		_promiseMutex = new Mutex;
		_hasFutureTask = new Condition(_promiseMutex);
	}

	static TaskManager instance() nothrow{
		if( !_instanceCreated ){
			synchronized{
				if( _instance is null ){
					_instance = new TaskManager();
					_instanceCreated = true;
				}
			}
		}
		return _instance;
	}

	Task submit(Task task) nothrow{
		lockFutureTask;
		scope(exit) unlockFutureTask;
		return submitNoLock(task);
	}

	void yield() nothrow{
		try
		{
			Fiber fiber = Fiber.getThis;
			if( fiber !is null ){
				Fiber.yield;
			}
			else{
				Thread.yield;
			}
		}
		catch(Throwable t)
		{

		}
	}

	void main(){
		Thread thisThread = Thread.getThis;
		thisThread.priority = Thread.PRIORITY_MAX;
		run(true);
	}

	/**
	 * this should be fetch by main application loop
	 */
	void run(bool waitIfNoTask=false){
		while( runOnce(waitIfNoTask) ){}
	}

	bool runOnce(bool waitIfNoTask=false){
		Task task = peekActiveTask(waitIfNoTask);
		if( task is null )
			return false;
		task.execute;
		return true;
	}

	void terminate() nothrow
	{
		isTerminated = true;
		notifyAll;
	}

	bool isTerminated() nothrow @property
	{
        return _isTerminated;
	}

	void isTerminated(bool value) nothrow @property
	{
        _isTerminated = value;
	}
protected:
	Task detachTask(Task task){
		if(task._next is null && task._prev is null)
			return task;

		lockFutureTask;
		scope(exit) unlockFutureTask;
		detachTaskNoLock(_futureTasks, task);
		return task;
	}

	void detachTaskNoLock(Task task){
		detachTaskNoLock(_futureTasks, task);
	}

	void detachTaskNoLock(ref TaskChain chain, Task task){
		Task first = chain.first;
		Task last = chain.last;

		Task prev = task._prev;
		Task next = task._next;

		if( prev !is null ){
			prev._next = next;
		}

		if( next !is null ){
			next._prev = prev;
		}

		if( task == first ){
			chain.first = next;
		}

		if( task == last ){
			chain.last = prev;
		}
	}

	Task submitNoLock(Task task) nothrow
	{
		task.queueNumber = nextTaskQueue;
		submitChainNoLock(_futureTasks, task);
		notifyHasFutureTask();
		return task;
	}
	
	void submitChainNoLock(ref TaskChain chain, Task task) nothrow
	{
		Task first = chain.first;
		Task last = chain.last;
		if( last is null || first is null){
			chain.first = task;
			chain.last = task;
			task._next = null;
			task._prev = null;
		}
		else{
			last._next = task;
			task._next = null;
			task._prev = last;
			chain.last = task;
		}
	}
	
	/**
	 * peek best task for next execution
	 */
	Task peekActiveTask(bool waitIfNoTask=false){
		lockFutureTask;
		scope(exit) unlockFutureTask;
		return peekActiveTaskNoLock(waitIfNoTask);
	}

	Task peekActiveTaskNoLock(bool waitIfNoTask=false)
	{
		Task result = selectTask(_futureTasks);
		if( result is null)
		{
			if( waitIfNoTask && !isTerminated){
				import core.memory;
				GC.collect;
				debug(KernelTask){
					writeln("Garbage collected. Now waiting for new task.");
				}
				_hasFutureTask.wait();
				result = peekActiveTaskNoLock(waitIfNoTask);
			}
		}
		else
		{
			detachTaskNoLock(result);
		}
		return result;
	}

	Task selectTask(ref TaskChain chain){
		Task first = chain.first;
		if (first is null)
			return null;

		Task walk = first._next;
		Task result = first;

		immutable int maxTest = 16;
		for (int i=0; i<maxTest && walk !is null; i++){
			if( walk.priority > result.priority ){
				result = walk;
			}
		}
		return result;
	}

	Fiber borrowFiber(){
		lockFiber;
		scope(exit) unlockFiber;
		return borrowFiberNoLock;
	}
	
	Fiber borrowFiberNoLock(){
		sizediff_t j = _fibers.length;
		if( j > 0 ){
			auto result = _fibers[--j];
			_fibers[j] = null;
			_fibers.length = j;
			return result;
		}
		return new Fiber(delegate void(){});
	}

	void recycleFiber(Fiber fiber){
		lockFiber;
		scope(exit) unlockFiber;
		recycleFiberNoLock(fiber);
	}

	void recycleFiberNoLock(Fiber fiber){
		_fibers ~= fiber;
	}

	void lockFiber() nothrow
	{
		bool unlocked = true;
		while(unlocked)
		{
			try{
				while(!_fiberMutex.tryLock)
					yield;
				unlocked = false;
			}
			catch(Throwable t)
			{
				
			}
		}
	}
	
	void unlockFiber() nothrow
	{
		bool locked = true;
		while(locked){
			try{
				_fiberMutex.unlock;
				locked = false;
			}
			catch(Throwable t){

			}
		}
	}

	void lockFutureTask() nothrow
	{
		bool locked = false;
		while(!locked)
		{
			try
			{
				while(!_promiseMutex.tryLock)
					yield;
				locked = true;
			}
			catch(Throwable t)
			{
			}
		}
	}
	
	void unlockFutureTask() nothrow
	{
		bool unlocked = false;
		while( !unlocked )
		{
			try
			{
				_promiseMutex.unlock;
				unlocked = true;
			}
			catch(Throwable t)
			{
			}
		}
	}
	
	void notifyHasFutureTask() nothrow
	{
		try
		{
			_hasFutureTask.notify;
		}
		catch(Throwable t)
		{
		}
	}

	void notifyAll() nothrow{
		try
		{
			_hasFutureTask.notifyAll;
		}
		catch(Throwable t)
		{
		}
	}

	size_t nextTaskQueue() nothrow @property{
		synchronized{
			return _nextTaskQueue++;
		}
	}

private:
	struct TaskChain{
		Task first;
		Task last;
	}

	shared bool _isTerminated = false;
	Mutex _fiberMutex;
	Mutex _promiseMutex;
	Condition _hasFutureTask;

	Fiber[] _fibers;
	TaskChain _futureTasks;
	__gshared{
		static TaskManager _instance;
		static bool _instanceCreated = false;
		static size_t _nextTaskQueue=0;
	}
}

auto createTask(Func, Args...)(Func func, Args args) nothrow if(is(typeof(func(args))) && !isSafeTask!Func)
{
	alias Result = typeof(func(args));
	return new FuncTaskImpl!(Result, Func, Args)(func, args);
}

@trusted auto createTask(Func, Args...)(Func func, Args args) nothrow if(is(typeof(func(args))) && isSafeTask!Func)
{
	alias Result = typeof(func(args));
	return new FuncTaskImpl!(Result, Func, Args)(func, args);
}

auto createParallelTask(Func, Args...)(Func func, Args args) nothrow if(is(typeof(func(args))) && !isSafeTask!Func)
{
	auto result = createTask(func, args);
	result._isParallelTask = true;
	return result;
}

@trusted auto createParallelTask(Func, Args...)(Func func, Args args) nothrow if(is(typeof(func(args))) && isSafeTask!Func)
{
	auto result = createTask(func, args);
	result._isParallelTask = true;
	return result;
}

auto futureTask(Func, Args...)(Func func, Args args) nothrow if(is(typeof(func(args))) && !isSafeTask!Func)
{
	auto result = createTask(func, args);
	TaskManager.instance.submit(result);
	return result;
}

@trusted auto futureTask(Func, Args...)(Func func, Args args) nothrow if(is(typeof(func(args))) && isSafeTask!Func)
{
	auto result = createTask(func, args);
	TaskManager.instance.submit(result);
	return result;
}

auto parallelTask(Func, Args...)(Func func, Args args) nothrow if(is(typeof(func(args))) && !isSafeTask!Func)
{
	auto result = createParallelTask(func, args);
	TaskManager.instance.submit(result);
	return result;
}

@trusted auto parallelTask(Func, Args...)(Func func, Args args) nothrow if(is(typeof(func(args))) && isSafeTask!Func)
{
	auto result = createParallelTask(func, args);
	TaskManager.instance.submit(createParallelTask(func, args));
	return result;
}

void fireEvent(Func, Args...)(Func func, Args args) if( isFunction!Func || isDelegate!Func )
{
	if( func !is null )
		func(args);
}

void fireEvent(Func, Args...)(Func[] func, Args args) if( isFunction!Func || isDelegate!Func )
{
	foreach(Func f; func)
	{
		fireEvent(f, args);
	}
}

void fireEvent(Func, Args...)(SetOf!Func func, Args args) if( isFunction!Func || isDelegate!Func )
{
	foreach(Func f; func)
	{
		fireEvent(f, args);
	}
}

/*
@trusted void fireEvent(Func, Args...)(Func[] func, Args args) if(is(typeof(func(args))) && isSafeTask!Func)
{
	foreach(Func f; func)
	{
		if( func !is null )
		{
			func(args);
		}
	}
}
*/

private template hasUnsharedAliasing(T...)
{
	import std.meta : anySatisfy;
	import std.typecons : Rebindable;
	
	static if (!T.length)
	{
		enum hasUnsharedAliasing = false;
	}
	else static if (is(T[0] R: Rebindable!R))
	{
		enum hasUnsharedAliasing = hasUnsharedAliasing!R;
	}
	else
	{
		template unsharedDelegate(T)
		{
			enum bool unsharedDelegate = isDelegate!T
				&& !is(T == shared)
					&& !is(T == shared)
					&& !is(T == immutable)
					&& !is(FunctionTypeOf!T == shared)
					&& !is(FunctionTypeOf!T == immutable);
		}
		
		enum hasUnsharedAliasing =
			hasRawUnsharedAliasing!(T[0]) ||
				anySatisfy!(unsharedDelegate, RepresentationTypeTuple!(T[0])) ||
				hasUnsharedObjects!(T[0]) ||
				hasUnsharedAliasing!(T[1..$]);
	}
}

private template noUnsharedAliasing(T)
{
	enum bool noUnsharedAliasing = !hasUnsharedAliasing!T;
}

private template isSafeTask(F)
{
	enum bool isSafeTask =
		(functionAttributes!F & (FunctionAttribute.safe | FunctionAttribute.trusted)) != 0 &&
			(functionAttributes!F & FunctionAttribute.ref_) == 0 &&
			(isFunctionPointer!F || !hasUnsharedAliasing!F) &&
			allSatisfy!(noUnsharedAliasing, ParameterTypeTuple!F);
}

private template hasRawUnsharedAliasing(T...)
{
    template Impl(T...)
    {
        static if (T.length == 0)
        {
            enum Impl = false;
        }
        else
        {
            static if (is(T[0] foo : U*, U) && !isFunctionPointer!(T[0]))
                enum has = !is(U == immutable) && !is(U == shared);
            else static if (is(T[0] foo : U[], U) && !isStaticArray!(T[0]))
                enum has = !is(U == immutable) && !is(U == shared);
            else static if (isAssociativeArray!(T[0]))
                enum has = !is(T[0] == immutable) && !is(T[0] == shared);
            else
                enum has = false;

            enum Impl = has || Impl!(T[1 .. $]);
        }
    }

    enum hasRawUnsharedAliasing = Impl!(RepresentationTypeTuple!T);
}

private template hasUnsharedObjects(T...)
{
    static if (T.length == 0)
    {
        enum hasUnsharedObjects = false;
    }
    else static if (is(T[0] == struct))
    {
        enum hasUnsharedObjects = hasUnsharedObjects!(
            RepresentationTypeTuple!(T[0]), T[1 .. $]);
    }
    else
    {
        enum hasUnsharedObjects = ((is(T[0] == class) || is(T[0] == interface)) &&
                                !is(T[0] == immutable) && !is(T[0] == shared)) ||
            hasUnsharedObjects!(T[1 .. $]);
    }
}
