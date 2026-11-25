// First-person rider on a RideRoute. Power comes from Sporterlay; speed is this world's own
// physics (gravity on the route's grade, rolling resistance, air drag, inertia), so climbs
// slow you down and descents speed you up. Nothing is sent back to the trainer.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "RiderPawn.generated.h"

class ARideRoute;
class UCameraComponent;
class USporterlayLink;

UCLASS(Config = Game)
class SPORTERLAYWORLD_API ARiderPawn : public APawn
{
	GENERATED_BODY()

public:
	ARiderPawn();

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Rider")
	TObjectPtr<UCameraComponent> Camera;

	// Route to ride; the first one in the level when empty.
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Rider")
	TObjectPtr<ARideRoute> Route;

	// --- physics (Config: [/Script/SporterlayWorld.RiderPawn] in DefaultGame.ini) ---
	UPROPERTY(EditAnywhere, Config, Category = "Rider|Physics", meta = (Units = "kg"))
	float TotalMassKg = 84.0f;  // rider + bike

	UPROPERTY(EditAnywhere, Config, Category = "Rider|Physics")
	float CdA = 0.32f;  // m², road bike on the hoods

	UPROPERTY(EditAnywhere, Config, Category = "Rider|Physics")
	float Crr = 0.004f;

	UPROPERTY(EditAnywhere, Config, Category = "Rider|Physics")
	float AirDensity = 1.225f;  // kg/m³

	UPROPERTY(EditAnywhere, Config, Category = "Rider|Physics")
	float DrivetrainEfficiency = 0.975f;

	// --- view ---
	UPROPERTY(EditAnywhere, Category = "Rider|View", meta = (Units = "cm"))
	float EyeHeight = 160.0f;

	// Distance right of the route's centre line (keep right).
	UPROPERTY(EditAnywhere, Category = "Rider|View", meta = (Units = "cm"))
	float LaneOffset = 150.0f;

	// The camera looks at the road this far ahead, which smooths corners.
	UPROPERTY(EditAnywhere, Category = "Rider|View", meta = (Units = "cm"))
	float LookAhead = 1200.0f;

	// Show speed, power and grade in the corner (Sporterlay's HUD has the rest).
	UPROPERTY(EditAnywhere, Config, Category = "Rider|View")
	bool bShowDebugText = true;

	UFUNCTION(BlueprintPure, Category = "Rider")
	float GetSpeedKmh() const { return Speed * 3.6f; }

	UFUNCTION(BlueprintPure, Category = "Rider")
	float GetGrade() const { return Grade; }

	UFUNCTION(BlueprintPure, Category = "Rider")
	float GetDistanceKm() const { return Odometer / 100000.0f; }

	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;

private:
	TWeakObjectPtr<USporterlayLink> Link;
	float Speed = 0.0f;     // m/s
	float Distance = 0.0f;  // cm along the route (wraps on a loop)
	float Odometer = 0.0f;  // cm ridden
	float Grade = 0.0f;     // %, smoothed
	bool bPlaced = false;

	void Integrate(float Watts, float Dt);
	void Place(float Dt);
};
