// Receives power from Sporterlay: one JSON datagram per tick (4 Hz) on 127.0.0.1:Port,
// {"v": 1, "power": 245}. One way: nothing is sent back (see sporterlay/world.py).

#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "SporterlayLink.generated.h"

class FSocket;

UCLASS(Config = Game)
class SPORTERLAYWORLD_API USporterlayLink : public UTickableWorldSubsystem
{
	GENERATED_BODY()

public:
	// Must match Sporterlay's world_port setting (settings.json).
	UPROPERTY(Config)
	int32 Port = 47810;

	// Power counts as gone (0 W) after this long without a datagram.
	UPROPERTY(Config)
	float TimeoutSeconds = 2.0f;

	UFUNCTION(BlueprintPure, Category = "Sporterlay")
	bool IsConnected() const;

	// Latest power in W, 0 when Sporterlay is quiet.
	UFUNCTION(BlueprintPure, Category = "Sporterlay")
	float GetPower() const { return IsConnected() ? Power : 0.0f; }

	const FString& GetError() const { return Error; }

	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;
	virtual void Tick(float DeltaTime) override;
	virtual TStatId GetStatId() const override;

protected:
	virtual bool DoesSupportWorldType(const EWorldType::Type WorldType) const override;

private:
	FSocket* Socket = nullptr;
	float Power = 0.0f;
	double LastReceived = -1.0e9;
	FString Error;
};
