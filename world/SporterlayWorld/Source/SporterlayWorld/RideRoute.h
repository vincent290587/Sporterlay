// The road the rider follows: a spline you draw on the landscape (or import from a GPX file),
// with a simple road surface laid along it from spline meshes.

#pragma once

#include "CoreMinimal.h"
#include "Engine/EngineTypes.h"
#include "GameFramework/Actor.h"
#include "RideRoute.generated.h"

class USplineComponent;
class UStaticMesh;
class UMaterialInterface;

UCLASS()
class SPORTERLAYWORLD_API ARideRoute : public AActor
{
	GENERATED_BODY()

public:
	ARideRoute();

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Route")
	TObjectPtr<USplineComponent> Spline;

	// Road surface stretched along the spline (forward axis X). Defaults to the engine cube;
	// clear it if the landscape already has a road (e.g. a landscape spline or a road kit).
	UPROPERTY(EditAnywhere, Category = "Route|Road")
	TObjectPtr<UStaticMesh> RoadMesh;

	UPROPERTY(EditAnywhere, Category = "Route|Road")
	TObjectPtr<UMaterialInterface> RoadMaterial;

	UPROPERTY(EditAnywhere, Category = "Route|Road", meta = (ClampMin = "100", Units = "cm"))
	float RoadWidth = 600.0f;

	UPROPERTY(EditAnywhere, Category = "Route|Road", meta = (ClampMin = "1", Units = "cm"))
	float RoadThickness = 20.0f;

	// Length of each road piece; shorter follows tight curves better, longer is cheaper.
	UPROPERTY(EditAnywhere, Category = "Route|Road", meta = (ClampMin = "100", Units = "cm"))
	float SegmentLength = 1000.0f;

	// Grade is measured over ±this distance, which hides small bumps in the terrain or GPX.
	UPROPERTY(EditAnywhere, Category = "Route", meta = (ClampMin = "100", Units = "cm"))
	float GradeWindow = 1500.0f;

	// GPX track to import (Import GPX button below). Lat/lon become metres around the first point.
	UPROPERTY(EditAnywhere, Category = "Route|GPX", meta = (FilePathFilter = "gpx"))
	FFilePath GpxFile;

	// Use the GPX elevation (true) or put every point on the landscape (false, then Snap To Ground).
	UPROPERTY(EditAnywhere, Category = "Route|GPX")
	bool bUseGpxElevation = true;

	// GPX points closer than this are skipped (GPS tracks are noisy at 1 s spacing).
	UPROPERTY(EditAnywhere, Category = "Route|GPX", meta = (ClampMin = "100", Units = "cm"))
	float GpxMinSpacing = 1000.0f;

	// Replace the spline's points with the GPX track.
	UFUNCTION(CallInEditor, Category = "Route|GPX")
	void ImportGpx();

	// Drop every spline point onto whatever is below it (landscape), plus half the road thickness.
	UFUNCTION(CallInEditor, Category = "Route")
	void SnapToGround();

	float Length() const;
	// Wraps on a closed loop, clamps otherwise.
	float WrapDistance(float Distance) const;
	FVector LocationAt(float Distance) const;
	FVector RightAt(float Distance) const;
	// Road grade in % at a distance along the route (positive = uphill in riding direction).
	float GradeAt(float Distance) const;

	virtual void OnConstruction(const FTransform& Transform) override;

private:
	void BuildRoad();
};
