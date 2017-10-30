module denpasar.base.classes;

import denpasar.kernel;

interface Executable{
	void execute();
}

abstract class Activable
{
	@property bool isActive()
	{
		return _isActive;
	}

	@property void isActive(bool value)
	{
		if( isActive == value )
			return;

		_isActive = value;
		scope(failure)
		{
			_isActive = !value;
		}

		if( value )
			activate;
		else
			deactivate;
	}
protected:
	void activate()
	{
		try
		{
			beforeActivation();
			rawActivate();
		}
		catch(Exception e){
			activationFailure(e);
			throw e;
		}
		activationSuccess();
	}

	void deactivate()
	{
		try
		{
			beforeDeactivation;
			rawDeactivate;
		}
		catch(Exception e)
		{
			deactivationFailure(e);
			throw e;
		}
		deactivationSuccess;
	}

	void beforeActivation()
	{
		callEvent(_onBeforeActivation, this);
	}

	void beforeDeactivation()
	{
		callEvent(_onBeforeDeactivation, this);
	}

	void activationSuccess()
	{
		callEvent(_onActivationSuccess, this);
	}

	void deactivationSuccess()
	{
		callEvent(_onDeactivationSuccess, this);
	}

	void activationFailure(Exception e)
	{
		callEvent(_onActivationFailure, this, e);
	}

	void deactivationFailure(Exception e)
	{
		callEvent(_onDeactivationFailure, this, e);
	}

	abstract void rawActivate();
	
	abstract void rawDeactivate();

private:
	bool _isActive = false;
	void delegate(Object)[] _onBeforeActivation, _onActivationSuccess, 
		_onBeforeDeactivation, _onDeactivationSuccess;
	void delegate(Object, Exception)[] _onActivationFailure, _onDeactivationFailure;
}
