#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "SporterlayGameMode.generated.h"

// Spawns a RiderPawn on the level's RideRoute (set as the project's default game mode).
UCLASS()
class SPORTERLAYWORLD_API ASporterlayGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	ASporterlayGameMode();
};
