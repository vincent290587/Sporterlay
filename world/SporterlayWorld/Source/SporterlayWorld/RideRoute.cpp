#include "RideRoute.h"

#include "Components/SplineComponent.h"
#include "Components/SplineMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Engine/World.h"
#include "Misc/Paths.h"
#include "UObject/ConstructorHelpers.h"
#include "XmlFile.h"

DEFINE_LOG_CATEGORY_STATIC(LogRideRoute, Log, All);

ARideRoute::ARideRoute()
{
	PrimaryActorTick.bCanEverTick = false;
	Spline = CreateDefaultSubobject<USplineComponent>(TEXT("Spline"));
	SetRootComponent(Spline);
	// a 400 m straight to start from; edit the points in the viewport or import a GPX
	Spline->ClearSplinePoints(false);
	Spline->AddSplinePoint(FVector::ZeroVector, ESplineCoordinateSpace::Local, false);
	Spline->AddSplinePoint(FVector(40000.0f, 0.0f, 0.0f), ESplineCoordinateSpace::Local, true);

	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cube(TEXT("/Engine/BasicShapes/Cube.Cube"));
	if (Cube.Succeeded())
	{
		RoadMesh = Cube.Object;
	}
}

float ARideRoute::Length() const
{
	return Spline->GetSplineLength();
}

float ARideRoute::WrapDistance(float Distance) const
{
	const float L = Length();
	if (L <= 0.0f)
	{
		return 0.0f;
	}
	if (Spline->IsClosedLoop())
	{
		return FMath::Fmod(FMath::Fmod(Distance, L) + L, L);
	}
	return FMath::Clamp(Distance, 0.0f, L);
}

FVector ARideRoute::LocationAt(float Distance) const
{
	return Spline->GetLocationAtDistanceAlongSpline(WrapDistance(Distance), ESplineCoordinateSpace::World);
}

FVector ARideRoute::RightAt(float Distance) const
{
	FVector Right = Spline->GetRightVectorAtDistanceAlongSpline(WrapDistance(Distance), ESplineCoordinateSpace::World);
	Right.Z = 0.0f;  // keep the lane offset level even where the spline twists
	return Right.GetSafeNormal();
}

float ARideRoute::GradeAt(float Distance) const
{
	// near the ends of an open route, measure over what's left instead of clamping into a flat spot
	float A = Distance - GradeWindow, B = Distance + GradeWindow;
	if (!Spline->IsClosedLoop())
	{
		A = FMath::Max(A, 0.0f);
		B = FMath::Min(B, Length());
	}
	const float Along = B - A;
	if (Along < 1.0f)
	{
		return 0.0f;
	}
	const float Rise = LocationAt(B).Z - LocationAt(A).Z;
	const float Run = FMath::Sqrt(FMath::Max(Along * Along - Rise * Rise, 1.0f));
	return 100.0f * Rise / Run;
}

void ARideRoute::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	BuildRoad();
}

void ARideRoute::BuildRoad()
{
	if (!RoadMesh)
	{
		return;
	}
	const float L = Length();
	const int32 Count = FMath::Max(1, FMath::CeilToInt(L / SegmentLength));
	const float Step = L / Count;
	const FVector MeshSize = RoadMesh->GetBoundingBox().GetSize();
	const FVector2D Scale(RoadWidth / FMath::Max(MeshSize.Y, 1.0f), RoadThickness / FMath::Max(MeshSize.Z, 1.0f));
	const FVector Down(0.0f, 0.0f, -0.5f * RoadThickness);  // the top of the road is on the spline

	for (int32 i = 0; i < Count; ++i)
	{
		const float D0 = i * Step, D1 = (i + 1) * Step;
		USplineMeshComponent* Piece = NewObject<USplineMeshComponent>(this);
		Piece->CreationMethod = EComponentCreationMethod::UserConstructionScript;  // rebuilt on every construction
		Piece->SetMobility(EComponentMobility::Static);
		Piece->SetStaticMesh(RoadMesh);
		if (RoadMaterial)
		{
			Piece->SetMaterial(0, RoadMaterial);
		}
		Piece->SetForwardAxis(ESplineMeshAxis::X, false);
		const FVector P0 = Spline->GetLocationAtDistanceAlongSpline(D0, ESplineCoordinateSpace::Local) + Down;
		const FVector P1 = Spline->GetLocationAtDistanceAlongSpline(D1, ESplineCoordinateSpace::Local) + Down;
		const FVector T0 = Spline->GetDirectionAtDistanceAlongSpline(D0, ESplineCoordinateSpace::Local) * Step;
		const FVector T1 = Spline->GetDirectionAtDistanceAlongSpline(D1, ESplineCoordinateSpace::Local) * Step;
		Piece->SetStartAndEnd(P0, T0, P1, T1, false);
		Piece->SetStartScale(Scale, false);
		Piece->SetEndScale(Scale, false);
		Piece->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
		Piece->SetupAttachment(Spline);
		Piece->RegisterComponent();
		Piece->UpdateMesh();
	}
}

void ARideRoute::SnapToGround()
{
	UWorld* World = GetWorld();
	if (!World)
	{
		return;
	}
	Modify();
	Spline->Modify();
	FCollisionQueryParams Params(SCENE_QUERY_STAT(RideRouteSnap), true, this);  // ignore our own road
	int32 Snapped = 0;
	for (int32 i = 0; i < Spline->GetNumberOfSplinePoints(); ++i)
	{
		const FVector P = Spline->GetLocationAtSplinePoint(i, ESplineCoordinateSpace::World);
		FHitResult Hit;
		const FVector From(P.X, P.Y, P.Z + 500000.0f), To(P.X, P.Y, P.Z - 500000.0f);
		if (World->LineTraceSingleByChannel(Hit, From, To, ECC_WorldStatic, Params))
		{
			Spline->SetLocationAtSplinePoint(i, Hit.ImpactPoint + FVector(0, 0, 0.5f * RoadThickness), ESplineCoordinateSpace::World, false);
			++Snapped;
		}
	}
	Spline->UpdateSpline();
	UE_LOG(LogRideRoute, Log, TEXT("Snapped %d of %d points to the ground"), Snapped, Spline->GetNumberOfSplinePoints());
#if WITH_EDITOR
	RerunConstructionScripts();
#endif
}

static void CollectPoints(const FXmlNode* Node, TArray<const FXmlNode*>& Out)
{
	for (const FXmlNode* Child : Node->GetChildrenNodes())
	{
		const FString& Tag = Child->GetTag();
		if (Tag == TEXT("trkpt") || Tag == TEXT("rtept"))
		{
			Out.Add(Child);
		}
		else
		{
			CollectPoints(Child, Out);
		}
	}
}

void ARideRoute::ImportGpx()
{
	const FString Path = FPaths::ConvertRelativePathToFull(GpxFile.FilePath);
	FXmlFile Xml(Path, EConstructMethod::ConstructFromFile);
	if (!Xml.IsValid() || !Xml.GetRootNode())
	{
		UE_LOG(LogRideRoute, Error, TEXT("Can't read GPX %s: %s"), *Path, *Xml.GetLastError());
		return;
	}
	TArray<const FXmlNode*> Nodes;
	CollectPoints(Xml.GetRootNode(), Nodes);
	if (Nodes.Num() < 2)
	{
		UE_LOG(LogRideRoute, Error, TEXT("GPX %s has fewer than 2 track points"), *Path);
		return;
	}

	// local tangent plane around the first point: X = east, -Y = north (UE is left-handed), Z = up
	constexpr double EarthRadiusCm = 6371000.0 * 100.0;
	double Lat0 = 0.0, Lon0 = 0.0, Ele0 = 0.0, CosLat0 = 1.0;
	TArray<FVector> Points;
	for (const FXmlNode* N : Nodes)
	{
		const double Lat = FCString::Atod(*N->GetAttribute(TEXT("lat")));
		const double Lon = FCString::Atod(*N->GetAttribute(TEXT("lon")));
		const FXmlNode* EleNode = N->FindChildNode(TEXT("ele"));
		const double Ele = EleNode ? FCString::Atod(*EleNode->GetContent()) : 0.0;
		if (Points.Num() == 0)
		{
			Lat0 = Lat; Lon0 = Lon; Ele0 = Ele;
			CosLat0 = FMath::Cos(FMath::DegreesToRadians(Lat0));
		}
		const FVector P(
			FMath::DegreesToRadians(Lon - Lon0) * CosLat0 * EarthRadiusCm,
			-FMath::DegreesToRadians(Lat - Lat0) * EarthRadiusCm,
			bUseGpxElevation ? (Ele - Ele0) * 100.0 : 0.0);
		if (Points.Num() == 0 || FVector::Dist2D(P, Points.Last()) >= GpxMinSpacing)
		{
			Points.Add(P);
		}
	}
	// a track that ends where it started becomes a loop you can ride forever
	const bool bLoop = Points.Num() > 3 && FVector::Dist2D(Points[0], Points.Last()) < 3.0f * GpxMinSpacing;
	if (bLoop)
	{
		Points.Pop();
	}

	Modify();
	Spline->Modify();
	Spline->ClearSplinePoints(false);
	for (const FVector& P : Points)
	{
		Spline->AddSplinePoint(P, ESplineCoordinateSpace::Local, false);
	}
	Spline->SetClosedLoop(bLoop, false);
	Spline->UpdateSpline();
	UE_LOG(LogRideRoute, Log, TEXT("Imported %d points (%.1f km%s) from %s"),
		Points.Num(), Length() / 100000.0f, bLoop ? TEXT(", loop") : TEXT(""), *Path);
	if (!bUseGpxElevation)
	{
		SnapToGround();  // reruns the construction script
		return;
	}
#if WITH_EDITOR
	RerunConstructionScripts();
#endif
}
