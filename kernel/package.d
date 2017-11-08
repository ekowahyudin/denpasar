module denpasar.kernel;

import core.atomic;
import core.sync.condition;
import core.sync.mutex;
import core.thread;
import denpasar.base.classes;
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

	~this(){
		debug(KernelTask){
			writefln("Task destroyed");
		}
	}
	
	public Status status() @property{
		return cast(Status) atomicLoad( _status );
	}

	public void status(Status value) @property{
		atomicStore(_status, value);
	}

	public Throwable thrownObject() @property{
		return _thrownObject;
	}

	public void thrownObject(Throwable value) @property{
		_thrownObject = value;
	}

	public bool isParallelTask() @property 
	{
		return _isParallelTask;
	}

	public sizediff_t priority() @property
	{
		return _priority;
	}

	public void priority(sizediff_t value) @property
	{
		_priority = value;
	}

	public size_t queueNumber(){
		return _queueNumber;
	}

	public void queueNumber(size_t value){
		_queueNumber = value;
	}
protected:
	Fiber _fiber;

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
			status = Status.done;
			//task is terminated
			taskManager.recycleFiber(fiber);
		}
		else{
			//submit for next time execution
			taskManager.submit(this);
		}
	}

	abstract void rawExecute();

private:
	size_t _queueNumber;
	sizediff_t _priority = 1;
	bool _isParallelTask = false;
	shared Status _status=Status.detached;
	Throwable _thrownObject=null;
	Task _next;
	Task _prev;
}

class FuncTask(Result) : Task{
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
}

class FuncTaskImpl(Result, Func, Args...) : FuncTask!Result
{	
	this(Func func, Args args)
	{
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
	protected this(){
		_fiberMutex = new Mutex;
		_promiseMutex = new Mutex;
		_hasFutureTask = new Condition(_promiseMutex);
	}

	static TaskManager instance(){
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

	Task submit(Task task){
		lockFutureTask;
		scope(exit) unlockFutureTask;
		return submitNoLock(task);
	}

	void yield(){
		Fiber fiber = Fiber.getThis;
		if( fiber !is null ){
			Fiber.yield;
		}
		else{
			Thread.yield;
		}
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

	void terminate()
	{
		_isTerminated = true;
		notifyAll;
	}

	bool isTerminated() @property
	{
		return cast(bool) atomicLoad(_isTerminated);
	}

	void isTerminated(bool value) @property
	{
		atomicStore(_isTerminated, value);
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

	Task submitNoLock(Task task){
		task.queueNumber = nextTaskQueue;
		submitChainNoLock(_futureTasks, task);
		notifyHasFutureTask();
		return task;
	}
	
	void submitChainNoLock(ref TaskChain chain, Task task){
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

	void lockFiber(){
		while(!_fiberMutex.tryLock)
			yield;
	}
	
	void unlockFiber()
	{
		_fiberMutex.unlock;
	}

	void lockFutureTask()
	{
		while(!_promiseMutex.tryLock)
			yield;
	}
	
	void unlockFutureTask()
	{
		_promiseMutex.unlock;
	}
	
	void notifyHasFutureTask()
	{
		_hasFutureTask.notify;
	}

	void notifyAll(){
		_hasFutureTask.notifyAll;
	}

	size_t nextTaskQueue() @property{
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
	static TaskManager _instance;
	static bool _instanceCreated = false;
	Mutex _fiberMutex;
	Mutex _promiseMutex;
	Condition _hasFutureTask;

	Fiber[] _fibers;
	TaskChain _futureTasks;
	__gshared{
		static size_t _nextTaskQueue=0;
	}
}

auto createTask(Func, Args...)(Func func, Args args)  if(is(typeof(func(args))) && !isSafeTask!Func)
{
	alias Result = typeof(func(args));
	return new FuncTaskImpl!(Result, Func, Args)(func, args);
}

@trusted auto createTask(Func, Args...)(Func func, Args args) if(is(typeof(func(args))) && isSafeTask!Func)
{
	alias Result = typeof(func(args));
	return new FuncTaskImpl!(Result, Func, Args)(func, args);
}

auto createParallelTask(Func, Args...)(Func func, Args args)  if(is(typeof(func(args))) && !isSafeTask!Func)
{
	auto result = createTask(func, args);
	result._isParallelTask = true;
	return result;
}

@trusted auto createParallelTask(Func, Args...)(Func func, Args args) if(is(typeof(func(args))) && isSafeTask!Func)
{
	auto result = createTask(func, args);
	result._isParallelTask = true;
	return result;
}

auto futureTask(Func, Args...)(Func func, Args args) if(is(typeof(func(args))) && !isSafeTask!Func)
{
	auto result = createTask(func, args);
	TaskManager.instance.submit(result);
	return result;
}

@trusted auto futureTask(Func, Args...)(Func func, Args args) if(is(typeof(func(args))) && isSafeTask!Func)
{
	auto result = createTask(func, args);
	TaskManager.instance.submit(result);
	return result;
}

auto parallelTask(Func, Args...)(Func func, Args args) if(is(typeof(func(args))) && !isSafeTask!Func)
{
	auto result = createParallelTask(func, args);
	TaskManager.instance.submit(result);
	return result;
}

@trusted auto parallelTask(Func, Args...)(Func func, Args args) if(is(typeof(func(args))) && isSafeTask!Func)
{
	auto result = createParallelTask(func, args);
	TaskManager.instance.submit(createParallelTask(func, args));
	return result;
}

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
