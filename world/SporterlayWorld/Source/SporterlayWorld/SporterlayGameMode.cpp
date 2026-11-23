#include "SporterlayGameMode.h"

#include "RiderPawn.h"

ASporterlayGameMode::ASporterlayGameMode()
{
	DefaultPawnClass = ARiderPawn::StaticClass();
}
